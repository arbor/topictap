module App.Commands.Types where

import App.Options.Types
import Control.Monad.Logger (LogLevel (..))
import Kafka.Types

data AppOptions = AppOptions
  { _appOptionsLogLevel         :: LogLevel
  , _appOptionsInputTopics      :: [TopicName]
  , _appOptionsStagingDirectory :: FilePath
  , _appOptionsAwsConfig        :: AwsConfig
  , _appOptionsKafkaConfig      :: KafkaConfig
  , _appOptionsStatsConfig      :: StatsConfig
  , _appOptionsStoreConfig      :: StoreConfig
  } deriving (Show)
