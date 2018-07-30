{-# LANGUAGE DeriveGeneric #-}

module App.AppError where

import Control.Monad.Catch
import GHC.Generics
import Kafka.Avro
import Kafka.Types

data AppError = KafkaErr KafkaError
              | DecodeErr DecodeError
              | SchemaErr SchemaRegistryError
              | AppErr String
              deriving (Show, Eq, Generic)
instance Exception AppError

throwAs :: MonadThrow m => (e -> AppError) -> Either e a -> m a
throwAs f = either (throwM . f) pure
