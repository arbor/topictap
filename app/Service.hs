{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections       #-}

module Service
  ( handleStream
  , mkObjectKey
  ) where

import App
import App.ToSha256Text
import Conduit
import Control.Arrow                        (left)
import Control.Lens                         ((+=), (<&>))
import Control.Monad.Catch                  (MonadThrow)
import Control.Monad.IO.Class               (MonadIO)
import Data.Aeson                           (object, (.=))
import Data.Avro.Schema                     ()
import Data.Avro.Types                      ()
import Data.ByteString                      (ByteString)
import Data.ByteString.Lazy                 (fromStrict)
import Data.Monoid                          ((<>))
import HaskellWorks.Data.Conduit.Combinator
import Kafka.Avro
import Kafka.Conduit.Source

import qualified Data.Aeson              as J
import qualified Data.Aeson.Text         as JT
import qualified Data.Avro.Decode        as A
import qualified Data.Avro.Schema        as A
import qualified Data.Avro.Types         as A
import qualified Data.ByteString         as BS
import qualified Data.ByteString.Base16  as Base16
import qualified Data.ByteString.Lazy    as LBS
import qualified Data.Text               as T
import qualified Data.Text.Encoding      as T
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
  .| effectC (const (readCount += 1))
  .| effectC (const (writeCount += 1))
  .| mapC (const ())

decodeMessage :: (MonadIO m, MonadThrow m)
              => SchemaRegistry
              -> ConsumerRecord (Maybe ByteString) (Maybe ByteString)
              -> m (ConsumerRecord (Maybe ByteString) J.Value)
decodeMessage sr msg = do
  let (_, v) = (crKey msg, crValue msg)
  res <- traverse decodeAvroMessage v
  let payload = object [ "offset"        .= unOffset (crOffset msg)
                       , "timestamp"     .= unTimeStamp (crTimestamp msg)
                       , "partitionId"   .= unPartitionId (crPartition msg)
                       , "key"           .= (encodeBs <$> crKey msg)
                       , "valueSchemaId" .= ((unSchemaId . fst) <$> res)
                       , "value"         .= (snd <$> res)
                       ]
  return $ const payload <$> msg
  where
    decodeAvroMessage bs = decodeAvro sr (fromStrict bs) >>= throwAs DecodeErr
    unPartitionId (PartitionId v) = v
    unSchemaId (SchemaId v) = v
    unOffset (Offset v) = v
    unTimeStamp = \case
      CreateTime (Millis m)    -> Just (object ["type" .= J.String "CreatedTime",   "value" .= m])
      LogAppendTime (Millis m) -> Just (object ["type" .= J.String "LogAppendTime", "value" .= m])
      NoTimestamp              -> Nothing
    encodeBs bs = "\\u" <> T.decodeUtf8 (Base16.encode bs)

writeDecodedMessage :: MonadIO m => FilePath -> ConsumerRecord (Maybe BS.ByteString) J.Value -> m ()
writeDecodedMessage parentPath msg = liftIO $ do
  D.createDirectoryIfMissing True dirPath
  LBS.appendFile (dirPath <> "/" <> show partitionId) (LT.encodeUtf8 (JT.encodeToLazyText (crValue msg)))
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

decodeAvro :: MonadIO m
        => SchemaRegistry
        -> LBS.ByteString
        -> m (Either DecodeError (SchemaId, A.Value A.Type))
decodeAvro sr bs =
  case schemaData of
    Left err -> return $ Left err
    Right (sid, payload) -> do
      res <- left DecodeRegistryError <$> loadSchema sr sid
      return $ res >>= decode payload <&> (sid,)
  where
    schemaData = maybe (Left BadPayloadNoSchemaId) Right (extractSchemaId bs)
    decode p s = left (DecodeError s) (A.decodeAvro s p)

