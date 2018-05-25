module App.Options.Types where

import Antiope.Core         (Region (..))
import Antiope.DynamoDB     (TableName)
import Antiope.S3           (BucketName)
import App.Types            (Seconds (..))
import Data.Text            (Text)
import Kafka.Consumer.Types
import Kafka.Types
import Network.Socket       (HostName)
import Network.StatsD       (SampleRate (..))

newtype StatsTag = StatsTag (Text, Text) deriving (Show, Eq)

data KafkaConfig = KafkaConfig
  { _kafkaConfigBroker                :: BrokerAddress
  , _kafkaConfigSchemaRegistryAddress :: String
  , _kafkaConfigPollTimeoutMs         :: Timeout
  , _kafkaConfigQueuedMaxMsgKBytes    :: Int
  , _kafkaConfigConsumerGroupId       :: ConsumerGroupId
  , _kafkaConfigDebugOpts             :: String
  , _kafkaConfigCommitPeriodSec       :: Int
  } deriving (Show)

data StatsConfig = StatsConfig
  { _statsConfigHost       :: HostName
  , _statsConfigPort       :: Int
  , _statsConfigTags       :: [StatsTag]
  , _statsConfigSampleRate :: SampleRate
  } deriving (Show)

data StoreConfig = StoreConfig
  { _storeConfigBucket         :: BucketName
  , _storeConfigIndex          :: TableName
  , _storeConfigUploadInterval :: Seconds
  } deriving (Show)

data AwsConfig = AwsConfig
  { _awsConfigRegion        :: Region
  , _awsConfigUploadThreads :: Int
  } deriving (Show)

newtype Password = Password
  { _passwordValue :: Text
  } deriving (Read, Eq)

instance Show Password where
  show _ = "************"

data DbConfig = DbConfig
  { _dbConfigHost     :: Text
  , _dbConfigUser     :: Text
  , _dbConfigPassword :: Password
  , _dbConfigDatabase :: Text
  } deriving (Eq, Show)
