{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE LambdaCase            #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module App.Persist
  ( uploadAllFiles
  ) where

import Antiope.Core                  (HasEnv, MonadAWS, runAWS, toText)
import Antiope.DynamoDB              (TableName, attributeValue, avN, avS, dynamoPutItem)
import Antiope.S3                    (BucketName (..), ObjectKey (..), S3Location (..), putFile)
import App.AppState.Type             (FileCache (..), FileCacheEntry (..), fileCacheEmpty)
import App.CancellationToken         (CancellationToken)
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
import Kafka.Consumer                (Millis (..), Offset (..), PartitionId (..), Timestamp (..), TopicName (..))

import qualified App.CancellationToken as CToken
import qualified App.Has               as H
import qualified App.Lens              as L
import qualified Data.ByteString.Lazy  as LBS
import qualified Data.HashMap.Strict   as Map
import qualified System.IO.Streams     as IO

-- | Uploads all files from FileCache (from State) to S3.
-- The file handles will be closed and files must not be used after this function returns.
-- The FileCache will be emptied in State.
uploadAllFiles :: ( MonadState s m, L.HasFileCache s FileCache
                  , MonadReader r m, H.HasAwsConfig r, H.HasStoreConfig r
                  , HasEnv r, MonadAWS m)
               => CancellationToken
               -> UTCTime
               -> m ()
uploadAllFiles ctoken timestamp = do
  cache     <- use L.fileCache
  entries   <- liftIO $ traverse (closeEntry . snd) (cache ^. L.entries & M.toList)
  uploadFiles ctoken timestamp entries
  L.fileCache .= fileCacheEmpty
  where closeEntry e = IO.write Nothing (e ^. L.outputStream) >> pure e

uploadFiles :: ( MonadAWS m, HasEnv r
               , MonadReader r m, H.HasAwsConfig r, H.HasStoreConfig r)
            => CancellationToken
            -> UTCTime
            -> [FileCacheEntry]
            -> m ()
uploadFiles ctoken timestamp fs = do
  aws <- ask
  bkt <- view $ H.storeConfig . L.bucket
  tbl <- view $ H.storeConfig . L.index
  par <- view $ H.awsConfig . L.uploadThreads
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
  void $ putFile bkt objKey (entry ^. L.backupEntry . L.fileName)
  void $ registerFile tbl timestamp entry (S3Location bkt objKey)

-------------------------------------------------------------------------------

recTimestamp :: Timestamp -> Int64
recTimestamp = \case
  CreateTime (Millis m)    -> m
  LogAppendTime (Millis m) -> m
  NoTimestamp              -> 0

mkS3Path :: UTCTime -> FileCacheEntry -> IO ObjectKey
mkS3Path t e = do
  let be = e ^. L.backupEntry
  hash <- toSha256Text <$> LBS.readFile (be ^. L.fileName)
  let TopicName topicName = be ^. L.topicName
  let PartitionId pid     = be ^. L.partitionId
  let Offset firstOffset  = be ^. L.offsetFirst
  let Offset maxOffset    = be ^. L.offsetMax
  let firstTimestamp      = be ^. L.timestampFirst
  let lastTimestamp       = be ^. L.timestampLast
  let partDir   = T.pack topicName <> "/" <> T.pack (show pid)
  let prefix    = T.take 5 $ toSha256Text partDir
  let fullDir   = prefix <> "/" <> partDir
  let timestamp = round $ utcTimeToPOSIXSeconds t :: Int64
  let at a b = toText a <> "@" <> toText b
  let fileName  = T.intercalate "-" [ firstOffset `at` recTimestamp firstTimestamp
                                    , maxOffset   `at` recTimestamp lastTimestamp
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
  let be = entry ^. L.backupEntry
  let TopicName topicName = be ^. L.topicName
  let PartitionId pid     = be ^. L.partitionId
  let Offset firstOffset  = be ^. L.offsetFirst
  let Offset maxOffset    = be ^. L.offsetMax
  let firstTimestamp      = be ^. L.timestampFirst
  let lastTimestamp       = be ^. L.timestampLast

  let row = Map.fromList
            [ ("TopicPartition",  attributeValue & avS ?~ (toText topicName <> ":" <> toText pid))
            , ("Topic",           attributeValue & avS ?~ toText topicName)
            , ("PartitionId",     attributeValue & avN ?~ toText pid)
            , ("Timestamp",       attributeValue & avS ?~ toText (show time))
            , ("OffsetFirst",     attributeValue & avN ?~ toText firstOffset)
            , ("TimestampFirst",  attributeValue & avN ?~ toText (recTimestamp firstTimestamp))
            , ("OffsetMax",       attributeValue & avN ?~ toText maxOffset)
            , ("TimestampLast",   attributeValue & avN ?~ toText (recTimestamp lastTimestamp))
            , ("LocationUri",     attributeValue & avS ?~ toText location)
            ]
  void $ dynamoPutItem table row
