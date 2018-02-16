{-# LANGUAGE ScopedTypeVariables #-}

module App.Service
  ( handleStream
  , mkObjectKey
  ) where

import App
import App.Codec
import App.ToSha256Text
import Conduit
import Control.Lens                         ((+=))
import Data.Avro.Schema                     ()
import Data.Avro.Types                      ()
import Data.ByteString                      (ByteString)
import Data.Monoid                          ((<>))
import HaskellWorks.Data.Conduit.Combinator
import Kafka.Avro
import Kafka.Conduit.Source

import qualified Data.Aeson              as J
import qualified Data.Aeson.Text         as JT
import qualified Data.ByteString         as BS
import qualified Data.ByteString.Lazy    as LBS
import qualified Data.Text               as T
import qualified Data.Text.Lazy.Encoding as LT
import qualified System.Directory        as D

-- | Handles the stream of incoming messages.
handleStream :: MonadApp m
             => SchemaRegistry
             -> FilePath
             -> Conduit (ConsumerRecord (Maybe ByteString) (Maybe ByteString)) m ()
handleStream sr fp =
  mapMC (decodeMessage sr)
  .| effectC (writeDecodedMessage fp)
  .| effectC (const (stateReadCount += 1))
  .| effectC (const (stateWriteCount += 1))
  .| mapC (const ())

writeDecodedMessage :: MonadApp m => FilePath -> ConsumerRecord (Maybe BS.ByteString) J.Value -> m ()
writeDecodedMessage parentPath msg = do
  liftIO $ D.createDirectoryIfMissing True dirPath
  liftIO $ LBS.appendFile (dirPath <> "/" <> show partitionId) (LT.encodeUtf8 (JT.encodeToLazyText (crValue msg)))
  where TopicName topicName     = crTopic msg
        PartitionId partitionId = crPartition msg
        dirPath                 = parentPath <> "/" <> topicName

mkDirFilename :: TopicName -> PartitionId -> (T.Text, T.Text)
mkDirFilename (TopicName topicName) (PartitionId partitionId) = (path, T.pack (show partitionId) <> "/" <> ".json")
    where path = T.pack topicName

mkObjectKey :: TopicName -> Timestamp -> PartitionId -> ByteString -> T.Text
mkObjectKey (TopicName topicName) currentTime (PartitionId partitionId) bs = toSha256Text path <> "/" <> path
    where contentHash = toSha256Text bs
          path        = T.pack topicName <> "/" <> T.pack (show partitionId) <> "/" <> T.pack (show currentTime) <> "-" <> contentHash <> ".json"
