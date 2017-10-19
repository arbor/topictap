{-# LANGUAGE ScopedTypeVariables #-}

module Service
  ( handleStream
  ) where

import App
import App.AvroToJson
import Conduit
import Control.Lens
import Control.Monad.Catch                  (MonadThrow)
import Control.Monad.IO.Class               (MonadIO)
import Data.Avro.Schema                     ()
import Data.Avro.Types                      ()
import Data.ByteString                      (ByteString)
import Data.ByteString.Lazy                 (fromStrict)
import HaskellWorks.Data.Conduit.Combinator
import Kafka.Avro
import Kafka.Conduit.Sink
import Kafka.Conduit.Source

import qualified Data.Aeson           as J
import qualified Data.Avro.Decode     as D
import qualified Data.Avro.Schema     as S
import qualified Data.Avro.Types      as T
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Conduit.List    as L

-- | Handles the stream of incoming messages.
handleStream :: MonadApp m
             => SchemaRegistry
             -> TopicName
             -> KafkaProducer
             -> Conduit (ConsumerRecord (Maybe ByteString) (Maybe ByteString)) m ()
handleStream sr topic prod =
  bisequenceValue                   -- extracting both key and value from consumer records
  .| L.catMaybes                    -- discard empty values
  .| mapMC (decodeMessage sr)       -- decode avro message.
  .| effectC (const (readCount += 1))
  .| effectC (const (writeCount += 1))
  .| mapC (const ())

decodeMessage :: (MonadIO m, MonadThrow m) => SchemaRegistry -> ConsumerRecord ByteString ByteString -> m J.Value
decodeMessage sr msg = do
  let (k, v) = (crKey msg, crValue msg)
  value <- decodeWithSchema2 sr (fromStrict v) >>= throwAs DecodeErr
  return (avroToJson value)

leftMap :: (e -> e') -> Either e r -> Either e' r
leftMap _ (Right r) = Right r
leftMap f (Left e)  = Left (f e)

decodeWithSchema2 :: (MonadIO m)
                 => SchemaRegistry
                 -> LBS.ByteString
                 -> m (Either DecodeError (T.Value S.Type))
decodeWithSchema2 sr bs =
  case schemaData of
    Left err -> return $ Left err
    Right (sid, payload) -> do
      res <- leftMap DecodeRegistryError <$> loadSchema sr sid
      return $ res >>= decode payload
  where
    schemaData = maybe (Left BadPayloadNoSchemaId) Right (extractSchemaId bs)
    decode p s = resultToEither s (D.decodeAvro s p)

resultToEither :: S.Schema -> Either String a -> Either DecodeError a
resultToEither sc res = case res of
  Right a  -> Right a
  Left msg -> Left $ DecodeError sc msg
