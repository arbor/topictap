module App.Type where

import App.AWS.DynamoDB     (TableName)
import Arbor.Logger         (LogLevel, TimedFastLogger)
import Data.Text            (Text)
import Kafka.Consumer.Types
import Kafka.Types
import Network.AWS          (Env)
import Network.AWS.S3.Types (BucketName, Region (..))
import Network.Socket       (HostName)
import Network.StatsD       (SampleRate (..), StatsClient)

newtype Seconds = Seconds { unSeconds :: Int } deriving (Show, Eq)

newtype StatsTag = StatsTag (Text, Text) deriving (Show, Eq)

data AppLogger = AppLogger
  { _alLogger   :: TimedFastLogger
  , _alLogLevel :: LogLevel
  }

data AppEnv = AppEnv
  { _appOptions     :: Options
  , _appStatsClient :: StatsClient
  , _appLog         :: AppLogger
  , _appEnvAws      :: Env
  }

data KafkaConfig = KafkaConfig
  { _broker                :: BrokerAddress
  , _schemaRegistryAddress :: String
  , _pollTimeoutMs         :: Timeout
  , _queuedMaxMsgKBytes    :: Int
  , _consumerGroupId       :: ConsumerGroupId
  , _debugOpts             :: String
  , _commitPeriodSec       :: Int
  } deriving (Show)

data StatsConfig = StatsConfig
  { _statsHost       :: HostName
  , _statsPort       :: Int
  , _statsTags       :: [StatsTag]
  , _statsSampleRate :: SampleRate
  } deriving (Show)

data StoreConfig = StoreConfig
  { _storeBucket         :: BucketName
  , _storeIndex          :: TableName
  , _storeUploadInterval :: Seconds
  } deriving (Show)

data Options = Options
  { _optLogLevel         :: LogLevel
  , _optInputTopics      :: [TopicName]
  , _optStagingDirectory :: FilePath
  , _optAwsConfig        :: AwsConfig
  , _optKafkaConfig      :: KafkaConfig
  , _optStatsConfig      :: StatsConfig
  , _optStoreConfig      :: StoreConfig
  } deriving (Show)

data AwsConfig = AwsConfig
  { _awsRegion     :: Region
  , _uploadThreads :: Int
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
