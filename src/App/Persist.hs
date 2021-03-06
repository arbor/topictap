{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE LambdaCase            #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications      #-}

module App.Persist
  ( uploadAllFiles
  ) where

import Antiope.Core                  (HasEnv, MonadAWS, runAWS, toText)
import Antiope.DynamoDB              (TableName, attributeValue, avN, avS, dynamoPutItem)
import Antiope.S3                    (BucketName (..), ObjectKey (..), S3Location (..), putFile)
import App.CancellationToken         (CancellationToken)
import App.ToSha256Text              (toSha256Text)
import Control.Concurrent.Async.Pool (mapTasks, withTaskGroup)
import Control.Lens                  (use, view, (&), (.=), (?~), (^.))
import Control.Monad                 (unless, void)
import Control.Monad.IO.Class        (liftIO)
import Control.Monad.Reader          (MonadReader, ask)
import Control.Monad.State           (MonadState)
import Control.Monad.Trans.Resource  (runResourceT)
import Data.Generics.Product.Any
import Data.Generics.Product.Fields
import Data.Map                      as M
import Data.Monoid                   ((<>))
import Data.Text                     as T
import Data.Time.Clock               (UTCTime)
import Data.Time.Clock.POSIX         (utcTimeToPOSIXSeconds)
import GHC.Int                       (Int64)
import Kafka.Consumer                (Millis (..), Offset (..), PartitionId (..), Timestamp (..), TopicName (..))

import qualified App.AppState.Type     as Z
import qualified App.CancellationToken as CToken
import qualified App.Options.Types     as Z
import qualified Data.ByteString.Lazy  as LBS
import qualified Data.HashMap.Strict   as Map
import qualified System.IO.Streams     as IO

-- | Uploads all files from FileCache (from State) to S3.
-- The file handles will be closed and files must not be used after this function returns.
-- The FileCache will be emptied in State.
uploadAllFiles ::
  ( MonadState s m
  , HasField' "fileCache" s Z.FileCache
  , MonadReader r m
  , HasField' "options"     r ro
  , HasField' "awsConfig"   ro Z.AwsConfig
  , HasField' "storeConfig" ro Z.StoreConfig
  , HasEnv r
  , MonadAWS m)
  => CancellationToken
  -> UTCTime
  -> m ()
uploadAllFiles ctoken timestamp = do
  cache     <- use $ the @"fileCache"
  entries   <- liftIO $ traverse (closeEntry . snd) (cache ^. the @"entries" & M.toList)
  uploadFiles ctoken timestamp entries
  the @"fileCache" .= Z.fileCacheEmpty
  where closeEntry e = IO.write Nothing (e ^. the @"outputStream") >> pure e

uploadFiles ::
  ( MonadAWS m
  , HasEnv r
  , MonadReader r m
  , HasField' "options"     r ro
  , HasField' "awsConfig"   ro Z.AwsConfig
  , HasField' "storeConfig" ro Z.StoreConfig)
  => CancellationToken
  -> UTCTime
  -> [Z.FileCacheEntry]
  -> m ()
uploadFiles ctoken timestamp fs = do
  aws <- ask
  bkt <- view $ the @"options" . the @"storeConfig" . the @"bucket"
  tbl <- view $ the @"options" . the @"storeConfig" . the @"index"
  par <- view $ the @"options" . the @"awsConfig"   . the @"uploadThreads"
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
           -> Z.FileCacheEntry
           -> m ()
uploadFile bkt tbl timestamp entry = do
  objKey <- liftIO $ mkS3Path timestamp entry
  void $ putFile bkt objKey (entry ^. the @"backupEntry" . the @"fileName")
  void $ registerFile tbl timestamp entry (S3Location bkt objKey)

-------------------------------------------------------------------------------

recTimestamp :: Timestamp -> Int64
recTimestamp = \case
  CreateTime (Millis m)    -> m
  LogAppendTime (Millis m) -> m
  NoTimestamp              -> 0

mkS3Path :: UTCTime -> Z.FileCacheEntry -> IO ObjectKey
mkS3Path t e = do
  let be = e ^. the @"backupEntry"
  hash <- toSha256Text <$> LBS.readFile (be ^. the @"fileName")
  let TopicName topicName = be ^. the @"topicName"
  let PartitionId pid     = be ^. the @"partitionId"
  let Offset firstOffset  = be ^. the @"offsetFirst"
  let Offset maxOffset    = be ^. the @"offsetMax"
  let firstTimestamp      = be ^. the @"timestampFirst"
  let lastTimestamp       = be ^. the @"timestampLast"
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
             -> Z.FileCacheEntry
             -> S3Location
             -> m ()
registerFile table time entry location = do
  let be = entry ^. the @"backupEntry"
  let TopicName topicName = be ^. the @"topicName"
  let PartitionId pid     = be ^. the @"partitionId"
  let Offset firstOffset  = be ^. the @"offsetFirst"
  let Offset maxOffset    = be ^. the @"offsetMax"
  let firstTimestamp      = be ^. the @"timestampFirst"
  let lastTimestamp       = be ^. the @"timestampLast"

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
