{-# LANGUAGE TemplateHaskell #-}

module App.Options where

import App.AWS.DynamoDB      (TableName)
import App.Types             (Seconds (..))
import Control.Lens
import Control.Monad.Logger  (LogLevel (..))
import Data.Semigroup        ((<>))
import Network.AWS.Data.Text (FromText (..), fromText)
import Network.AWS.S3.Types  (BucketName, Region (..))
import Network.Socket        (HostName)
import Network.StatsD        (SampleRate (..))

import Options.Applicative
import Text.Read           (readEither)

import Kafka.Consumer.Types
import Kafka.Types

import           Data.Text (Text)
import qualified Data.Text as T

newtype StatsTag = StatsTag (Text, Text) deriving (Show, Eq)

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

makeClassy ''KafkaConfig
makeClassy ''StatsConfig
makeClassy ''AwsConfig
makeClassy ''Options
makeClassy ''StoreConfig

instance HasKafkaConfig Options where
  kafkaConfig = optKafkaConfig

instance HasStatsConfig Options where
  statsConfig = optStatsConfig

instance HasStoreConfig Options where
  storeConfig = optStoreConfig

instance HasAwsConfig Options where
  awsConfig = optAwsConfig

statsConfigParser :: Parser StatsConfig
statsConfigParser = StatsConfig
  <$> strOption
      (   long "statsd-host"
      <>  metavar "HOST_NAME"
      <>  showDefault <> value "127.0.0.1"
      <>  help "StatsD host name or IP address"
      )
  <*> readOption
      (   long "statsd-port"
      <>  metavar "PORT"
      <>  showDefault <> value 8125
      <>  help "StatsD port"
      <>  hidden
      )
  <*> ( string2Tags <$> strOption
        (   long "statsd-tags"
        <>  metavar "TAGS"
        <>  showDefault <> value []
        <>  help "StatsD tags"
        )
      )
  <*> ( SampleRate <$> readOption
        (   long "statsd-sample-rate"
        <>  metavar "SAMPLE_RATE"
        <>  showDefault <> value 0.01
        <>  help "StatsD sample rate"
        )
      )

kafkaConfigParser :: Parser KafkaConfig
kafkaConfigParser = KafkaConfig
  <$> ( BrokerAddress <$> strOption
        (   long "kafka-broker"
        <>  metavar "ADDRESS:PORT"
        <>  help "Kafka bootstrap broker"
        )
      )
  <*> strOption
      (   long "kafka-schema-registry"
      <>  metavar "HTTP_URL:PORT"
      <>  help "Schema registry address")
  <*> ( Timeout <$> readOption
        (   long "kafka-poll-timeout-ms"
        <>  metavar "KAFKA_POLL_TIMEOUT_MS"
        <>  showDefault <> value 1000
        <>  help "Kafka poll timeout (in milliseconds)")
        )
  <*> readOption
      (   long "kafka-queued-max-messages-kbytes"
      <>  metavar "KAFKA_QUEUED_MAX_MESSAGES_KBYTES"
      <>  showDefault <> value 100000
      <>  help "Kafka queued.max.messages.kbytes"
      )
  <*> ( ConsumerGroupId <$> strOption
        (   long "kafka-group-id"
        <>  metavar "GROUP_ID"
        <>  help "Kafka consumer group id"
        )
      )
  <*> strOption
      (   long "kafka-debug-enable"
      <>  metavar "KAFKA_DEBUG_ENABLE"
      <>  showDefault <> value "broker,protocol"
      <>  help "Kafka debug modules, comma separated names: see debug in CONFIGURATION.md"
      )
  <*> readOption
      (   long "kafka-consumer-commit-period-sec"
      <>  metavar "KAFKA_CONSUMER_COMMIT_PERIOD_SEC"
      <>  showDefault <> value 60
      <>  help "Kafka consumer offsets commit period (in seconds)"
      )

awsConfigParser :: Parser AwsConfig
awsConfigParser = AwsConfig
  <$> readOrFromTextOption
      (  long "region"
      <> metavar "AWS_REGION"
      <> showDefault <> value Oregon
      <> help "The AWS region in which to operate"
      )
  <*> readOption
      (  long "upload-threads"
      <> metavar "NUM_THREADS"
      <> showDefault <> value 20
      <> help "Number of parallel S3 operations"
      )

storeConfigParser :: Parser StoreConfig
storeConfigParser = StoreConfig
  <$> readOrFromTextOption
      (  long "output-bucket"
      <> metavar "BUCKET"
      <> help "Output bucket.  Data from input topics will be written to this bucket"
      )
  <*> fromTextOption
      (  long "index-table"
      <> metavar "TABLE_NAME"
      <> help "The name of the DynamoDB table to store the index"
      )
  <*> ( Seconds <$> readOption
        (  long "upload-interval"
        <> metavar "SECONDS"
        <> help "Interval in seconds to upload files to S3"
        )
      )

optParser :: Parser Options
optParser = Options
  <$> readOptionMsg "Valid values are LevelDebug, LevelInfo, LevelWarn, LevelError"
      (  long "log-level"
      <> metavar "LOG_LEVEL"
      <> showDefault <> value LevelInfo
      <> help "Log level"
      )
  <*> ( (TopicName <$>) . (>>= words) . (fmap commaToSpace <$>) <$> many topicOption)
  <*> strOption
      (  long "staging-directory"
      <> metavar "PATH"
      <> help "Staging directory where generated files are stored and scheduled for upload to S3"
      )
  <*> awsConfigParser
  <*> kafkaConfigParser
  <*> statsConfigParser
  <*> storeConfigParser
  where
    topicOption = strOption
      (  long "topic"
      <> metavar "TOPIC"
      <> help "Input topic.  Multiple topics can be supplied by repeating the flag or comma/space separating the topic names"
      )

commaToSpace :: Char -> Char
commaToSpace ',' = ' '
commaToSpace c   = c

readOption :: Read a => Mod OptionFields a -> Parser a
readOption = option $ eitherReader readEither

readOptionMsg :: Read a => String -> Mod OptionFields a -> Parser a
readOptionMsg msg = option $ eitherReader (either (Left . const msg) Right . readEither)

fromTextOption :: (FromText a) => Mod OptionFields a -> Parser a
fromTextOption = option $ eitherReader (fromText . T.pack)

readOrFromTextOption :: (Read a, FromText a) => Mod OptionFields a -> Parser a
readOrFromTextOption =
  let fromStr s = readEither s <|> fromText (T.pack s)
  in option $ eitherReader fromStr

string2Tags :: String -> [StatsTag]
string2Tags s = StatsTag . splitTag <$> splitTags
  where
    splitTags = T.split (==',') (T.pack s)
    splitTag t = T.drop 1 <$> T.break (==':') t

optParserInfo :: ParserInfo Options
optParserInfo = info (helper <*> optParser)
  (  fullDesc
  <> progDesc "Dump avro data from kafka topic to S3"
  <> header "Kafka to S3"
  )

parseOptions :: IO Options
parseOptions = execParser optParserInfo
