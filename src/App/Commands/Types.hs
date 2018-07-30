{-# LANGUAGE DeriveGeneric #-}

module App.Commands.Types where

import App.Options.Types
import Control.Monad.Logger (LogLevel (..))
import GHC.Generics
import Kafka.Types

data AppOptions = AppOptions
  { logLevel         :: LogLevel
  , inputTopics      :: [TopicName]
  , stagingDirectory :: FilePath
  , awsConfig        :: AwsConfig
  , kafkaConfig      :: KafkaConfig
  , statsConfig      :: StatsConfig
  , storeConfig      :: StoreConfig
  } deriving (Show, Generic)
