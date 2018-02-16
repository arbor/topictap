{-# LANGUAGE MultiParamTypeClasses #-}
module App.Persist
( uploadAllFiles
)
where

import App.AppState
import App.AWS.S3                    (putFile)
import App.Options                   (HasAwsConfig, awsConfig, storeBucket, uploadThreads)
import App.ToSha256Text              (toSha256Text)
import Control.Concurrent.Async.Pool (mapTasks, withTaskGroup)
import Control.Lens                  (use, view, (&), (.=), (^.))
import Control.Monad                 (unless, void)
import Control.Monad.IO.Class        (liftIO)
import Control.Monad.Reader          (MonadReader, ask)
import Control.Monad.State           (MonadState)
import Control.Monad.Trans.Resource  (runResourceT)
import Data.Map                      as M
import Data.Monoid                   ((<>))
import Data.Text                     as T
import Data.Time.Clock               (UTCTime)
import Data.Time.Clock.POSIX         (getCurrentTime, utcTimeToPOSIXSeconds)
import GHC.Int                       (Int64)
import Kafka.Consumer                (Offset (..), PartitionId (..), TopicName (..))
import Network.AWS                   (HasEnv, MonadAWS, runAWS)
import Network.AWS.S3.Types          (BucketName (..), ObjectKey (..))
import System.IO                     (hClose)

import           App.CancellationToken (CancellationToken)
import qualified App.CancellationToken as CToken
import qualified Data.ByteString.Lazy  as LBS

-- | Uploads all files from FileCache (from State) to S3.
-- The file handles will be closed and files must not be used after this function returns.
-- The FileCache will be emptied in State.
uploadAllFiles :: (MonadState s m, HasFileCache s, MonadReader r m, HasAwsConfig r, HasEnv r, MonadAWS m)
               => CancellationToken
               -> m ()
uploadAllFiles ctoken = do
  timestamp <- liftIO getCurrentTime
  cache     <- use fileCache
  entries   <- liftIO $ traverse (closeEntry . snd) (cache ^. fcEntries & M.toList)
  uploadFiles ctoken timestamp entries
  fileCache .= fileCacheEmpty
  where
    closeEntry e = e ^. fceHandle & hClose >> pure e

uploadFiles :: (HasEnv r, MonadReader r m, HasAwsConfig r, MonadAWS m)
            => CancellationToken
            -> UTCTime
            -> [FileCacheEntry]
            -> m ()
uploadFiles ctoken timestamp fs = do
  aws <- ask
  bkt <- view (awsConfig . storeBucket)
  par <- view (awsConfig . uploadThreads)
  liftIO . void $ mapConcurrently' par (go aws bkt) fs
  liftIO $ print fs
  where
    go e bkt file = do
      ctStatus <- CToken.status ctoken
      unless (ctStatus == CToken.Cancelled) $
        runResourceT $ runAWS e (uploadFile bkt timestamp file)

uploadFile :: MonadAWS m
           => BucketName
           -> UTCTime
           -> FileCacheEntry
           -> m ()
uploadFile bkt timestamp entry = do
  objKey <- liftIO $ mkS3Path timestamp entry
  void $ putFile bkt objKey (entry ^. fceFileName)

-------------------------------------------------------------------------------

mkS3Path :: UTCTime -> FileCacheEntry -> IO ObjectKey
mkS3Path t e = do
  hash <- md5File (e ^. fceFileName)
  let TopicName topicName = e ^. fceTopicName
  let PartitionId pid     = e ^. fcePartitionId
  let Offset firstOffset  = e ^. fceOffsetFirst
  let Offset lastOffset   = e ^. fceOffsetLast
  let partDir   = T.pack topicName <> "/" <> T.pack (show pid)
  let prefix    = T.take 5 $ toSha256Text partDir
  let fullDir   = prefix <> "/" <> partDir
  let timestamp = round $ utcTimeToPOSIXSeconds t :: Int64
  let fileName  = T.intercalate "-" [ T.pack (show firstOffset)
                                    , T.pack (show lastOffset)
                                    , T.pack (show timestamp)
                                    , hash
                                    ] <> ".json.gz"
  pure $ ObjectKey $ fullDir <> "/" <> fileName

md5File :: FilePath -> IO Text
md5File f = toSha256Text <$> LBS.readFile f

mapConcurrently' :: Traversable t => Int -> (b -> IO a) -> t b -> IO (t a)
mapConcurrently' n f args = withTaskGroup n $ \tg ->
  mapTasks tg (fmap f args)

