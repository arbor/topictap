{-# LANGUAGE MultiParamTypeClasses #-}
module App.Persist
( uploadAllFiles
)
where

import App.AppState
import App.AWS.DynamoDB
import App.AWS.S3                    (S3Location (..), putFile)
import App.Options                   (HasAwsConfig (..), HasStoreConfig (..))
import App.ToSha256Text              (toSha256Text)
import Control.Concurrent.Async.Pool (mapTasks, withTaskGroup)
import Control.Lens                  (use, view, (&), (.=), (?~), (^.))
import Control.Monad                 (unless, void)
import Control.Monad.IO.Class        (liftIO)
import Control.Monad.Reader          (MonadReader, ask)
import Control.Monad.State           (MonadState)
import Control.Monad.Trans.Resource  (runResourceT)
import Data.Map                      as M
import Data.Monoid                   ((<>))
import Data.Text                     as T
import Data.Time.Clock               (UTCTime)
import Data.Time.Clock.POSIX         (utcTimeToPOSIXSeconds)
import GHC.Int                       (Int64)
import Kafka.Consumer                (Offset (..), PartitionId (..), TopicName (..))
import Network.AWS                   (HasEnv, MonadAWS, runAWS)
import Network.AWS.Data              (toText)
import Network.AWS.S3.Types          (BucketName (..), ObjectKey (..))
import System.IO                     (hClose)

import           App.CancellationToken (CancellationToken)
import qualified App.CancellationToken as CToken
import qualified Data.ByteString.Lazy  as LBS
import qualified Data.HashMap.Strict   as Map

-- | Uploads all files from FileCache (from State) to S3.
-- The file handles will be closed and files must not be used after this function returns.
-- The FileCache will be emptied in State.
uploadAllFiles :: ( MonadState s m, HasFileCache s
                  , MonadReader r m, HasAwsConfig r, HasStoreConfig r
                  , HasEnv r, MonadAWS m)
               => CancellationToken
               -> UTCTime
               -> m ()
uploadAllFiles ctoken timestamp = do
  cache     <- use fileCache
  entries   <- liftIO $ traverse (closeEntry . snd) (cache ^. fcEntries & M.toList)
  uploadFiles ctoken timestamp entries
  fileCache .= fileCacheEmpty
  where
    closeEntry e = e ^. fceHandle & hClose >> pure e

uploadFiles :: ( MonadAWS m, HasEnv r
               , MonadReader r m, HasAwsConfig r, HasStoreConfig r)
            => CancellationToken
            -> UTCTime
            -> [FileCacheEntry]
            -> m ()
uploadFiles ctoken timestamp fs = do
  aws <- ask
  bkt <- view storeBucket
  tbl <- view storeIndex
  par <- view (awsConfig . uploadThreads)
  liftIO . void $ mapConcurrently' par (go aws bkt tbl) fs
  where
    go e b t file = do
      ctStatus <- CToken.status ctoken
      unless (ctStatus == CToken.Cancelled) $
        runResourceT $ runAWS e (uploadFile b t timestamp file)

uploadFile :: MonadAWS m
           => BucketName
           -> TableName
           -> UTCTime
           -> FileCacheEntry
           -> m ()
uploadFile bkt tbl timestamp entry = do
  objKey <- liftIO $ mkS3Path timestamp entry
  void $ putFile bkt objKey (entry ^. fceFileName)
  void $ registerFile tbl timestamp entry (S3Location bkt objKey)

-------------------------------------------------------------------------------

mkS3Path :: UTCTime -> FileCacheEntry -> IO ObjectKey
mkS3Path t e = do
  hash <- toSha256Text <$> LBS.readFile (e ^. fceFileName)
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

mapConcurrently' :: Traversable t => Int -> (b -> IO a) -> t b -> IO (t a)
mapConcurrently' n f args = withTaskGroup n $ \tg ->
  mapTasks tg (fmap f args)

registerFile :: MonadAWS m
             => TableName
             -> UTCTime
             -> FileCacheEntry
             -> S3Location
             -> m ()
registerFile table time entry location = do
  let TopicName topicName = entry ^. fceTopicName
  let PartitionId pid     = entry ^. fcePartitionId
  let Offset firstOffset  = entry ^. fceOffsetFirst
  let Offset lastOffset   = entry ^. fceOffsetLast

  let row = Map.fromList
            [ ("TopicPartition",  attributeValue & avS ?~ (toText topicName <> ":" <> toText pid))
            , ("Topic",           attributeValue & avS ?~ toText topicName)
            , ("PartitionId",     attributeValue & avN ?~ toText pid)
            , ("Timestamp",       attributeValue & avS ?~ toText (show time))
            , ("OffsetFirst",     attributeValue & avN ?~ toText firstOffset)
            , ("OffsetLast",      attributeValue & avN ?~ toText lastOffset)
            , ("LocationUri",     attributeValue & avS ?~ toText location)
            ]
  void $ dynamoPutItem table row
