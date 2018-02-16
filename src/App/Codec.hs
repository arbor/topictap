{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections       #-}

module App.Codec
  ( decodeMessage
  , decodeAvro
  ) where

import App
import Control.Arrow          (left)
import Control.Lens           ((<&>))
import Control.Monad.Catch    (MonadThrow)
import Control.Monad.IO.Class (MonadIO)
import Data.Aeson             (object, (.=))
import Data.Avro.Schema       ()
import Data.Avro.Types        ()
import Data.ByteString        (ByteString)
import Data.ByteString.Lazy   (fromStrict)
import Data.Monoid            ((<>))
import Kafka.Avro
import Kafka.Conduit.Source

import qualified Data.Aeson             as J
import qualified Data.Avro.Decode       as A
import qualified Data.Avro.Schema       as A
import qualified Data.Avro.Types        as A
import qualified Data.ByteString.Base16 as Base16
import qualified Data.ByteString.Lazy   as LBS
import qualified Data.Text.Encoding     as T

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
                       , "valueSchemaId" .= (unSchemaId . fst <$> res)
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
