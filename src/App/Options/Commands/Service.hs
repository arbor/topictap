module App.Options.Commands.Service where

import App.Options.Types
import Control.Monad.Logger (LogLevel (..))
import Kafka.Types

data CmdServiceOptions = CmdServiceOptions
  { _cmdServiceOptionsLogLevel         :: LogLevel
  , _cmdServiceOptionsInputTopics      :: [TopicName]
  , _cmdServiceOptionsStagingDirectory :: FilePath
  , _cmdServiceOptionsAwsConfig        :: AwsConfig
  , _cmdServiceOptionsKafkaConfig      :: KafkaConfig
  , _cmdServiceOptionsStatsConfig      :: StatsConfig
  , _cmdServiceOptionsStoreConfig      :: StoreConfig
  } deriving (Show)

