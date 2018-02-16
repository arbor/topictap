{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections       #-}

module Service
  ( handleStream
  ) where

import App
import Conduit
import Control.Lens                         ((+=), (<&>))
import Control.Monad.Catch                  (MonadThrow)
import Control.Monad.IO.Class               (MonadIO)
import Data.Avro.Schema                     ()
import Data.Avro.Types                      ()
import Data.ByteString                      (ByteString)
import Data.ByteString.Lazy                 (fromStrict)
import Data.Monoid                          ((<>))
import HaskellWorks.Data.Conduit.Combinator
import Kafka.Avro
import Kafka.Conduit.Source

import Data.Aeson (object, (.=))

import qualified Data.Aeson             as J
import qualified Data.Avro.Decode       as D
import qualified Data.Avro.Schema       as S
import qualified Data.Avro.Types        as T
import qualified Data.ByteString.Base16 as Base16
import qualified Data.ByteString.Lazy   as LBS
import qualified Data.Conduit.List      as L
import qualified Data.Text.Encoding     as T

-- | Handles the stream of incoming messages.
handleStream :: MonadApp m
             => SchemaRegistry
             -> Conduit (ConsumerRecord (Maybe ByteString) (Maybe ByteString)) m ()
handleStream sr =
  bisequenceValue                   -- extracting both key and value from consumer records
  .| L.catMaybes                    -- discard empty values
  .| mapMC (decodeMessage sr)       -- decode avro message.
  .| effectC (const (readCount += 1))
  .| effectC (const (writeCount += 1))
  .| mapC (const ())

decodeMessage :: (MonadIO m, MonadThrow m) => SchemaRegistry -> ConsumerRecord ByteString ByteString -> m (ConsumerRecord ByteString J.Value)
decodeMessage sr msg = do
  let (_, v) = (crKey msg, crValue msg)
  (sid, val) <- decodeWithSchema2 sr (fromStrict v) >>= throwAs DecodeErr
  let payload = object [ "offset"        .= unOffset (crOffset msg)
                       , "timestamp"     .= unTimeStamp (crTimestamp msg)
                       , "partitionId"   .= unPartitionId (crPartition msg)
                       , "key"           .= encodeBs (crKey msg)
                       , "valueSchemaId" .= unSchemaId sid
                       , "value"         .= val
                       ]
  return $ const payload <$> msg
  where
    unPartitionId (PartitionId v) = v
    unSchemaId (SchemaId v) = v
    unOffset (Offset v) = v
    unTimeStamp = \case
      CreateTime (Millis m)    -> Just m
      LogAppendTime (Millis m) -> Just m
      NoTimestamp              -> Nothing
    encodeBs bs = "\\u" <> T.decodeUtf8 (Base16.encode bs)

leftMap :: (e -> e') -> Either e r -> Either e' r
leftMap _ (Right r) = Right r
leftMap f (Left e)  = Left (f e)

decodeWithSchema2 :: (MonadIO m)
                 => SchemaRegistry
                 -> LBS.ByteString
                 -> m (Either DecodeError (SchemaId, T.Value S.Type))
decodeWithSchema2 sr bs =
  case schemaData of
    Left err -> return $ Left err
    Right (sid, payload) -> do
      res <- leftMap DecodeRegistryError <$> loadSchema sr sid
      return $ res >>= decode payload <&> (sid,)
  where
    schemaData = maybe (Left BadPayloadNoSchemaId) Right (extractSchemaId bs)
    decode p s = resultToEither s (D.decodeAvro s p)

resultToEither :: S.Schema -> Either String a -> Either DecodeError a
resultToEither sc res = case res of
  Right a  -> Right a
  Left msg -> Left $ DecodeError sc msg
