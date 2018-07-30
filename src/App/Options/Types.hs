{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE DuplicateRecordFields #-}

module App.Options.Types where

import Antiope.Core         (FromText (..), Region (..), fromText)
import Antiope.DynamoDB     (TableName)
import Antiope.S3           (BucketName)
import App.Types            (Seconds (..))
import Data.Semigroup       ((<>))
import Data.Text            (Text)
import GHC.Generics
import Kafka.Consumer.Types
import Kafka.Types
import Network.Socket       (HostName)
import Network.StatsD       (SampleRate (..))
import Options.Applicative
import Text.Read            (readEither)

import qualified Data.Text           as T
import qualified Options.Applicative as OA

newtype StatsTag = StatsTag (Text, Text) deriving (Show, Eq)

data KafkaConfig = KafkaConfig
  { broker                :: BrokerAddress
  , schemaRegistryAddress :: String
  , pollTimeoutMs         :: Timeout
  , queuedMaxMsgKBytes    :: Int
  , consumerGroupId       :: ConsumerGroupId
  , debugOpts             :: String
  , commitPeriodSec       :: Int
  } deriving (Show, Generic)

data StatsConfig = StatsConfig
  { host       :: HostName
  , port       :: Int
  , tags       :: [StatsTag]
  , sampleRate :: SampleRate
  } deriving (Show, Generic)

data StoreConfig = StoreConfig
  { bucket         :: BucketName
  , index          :: TableName
  , uploadInterval :: Seconds
  } deriving (Show, Generic)

data AwsConfig = AwsConfig
  { region        :: Region
  , uploadThreads :: Int
  } deriving (Show, Generic)

newtype Password = Password
  { value :: Text
  } deriving (Read, Eq, Generic)

instance Show Password where
  show _ = "************"

data DbConfig = DbConfig
  { host     :: Text
  , user     :: Text
  , password :: Password
  , database :: Text
  } deriving (Eq, Show, Generic)

statsConfigParser :: Parser StatsConfig
statsConfigParser = StatsConfig
  <$> strOption
      (   long "statsd-host"
      <>  metavar "HOST_NAME"
      <>  showDefault <> OA.value "127.0.0.1"
      <>  help "StatsD host name or IP address"
      )
  <*> readOption
      (   long "statsd-port"
      <>  metavar "PORT"
      <>  showDefault <> OA.value 8125
      <>  help "StatsD port"
      <>  hidden
      )
  <*> ( string2Tags <$> strOption
        (   long "statsd-tags"
        <>  metavar "TAGS"
        <>  showDefault <> OA.value []
        <>  help "StatsD tags"
        )
      )
  <*> ( SampleRate <$> readOption
        (   long "statsd-sample-rate"
        <>  metavar "SAMPLE_RATE"
        <>  showDefault <> OA.value 0.01
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
        <>  showDefault <> OA.value 1000
        <>  help "Kafka poll timeout (in milliseconds)")
        )
  <*> readOption
      (   long "kafka-queued-max-messages-kbytes"
      <>  metavar "KAFKA_QUEUED_MAX_MESSAGES_KBYTES"
      <>  showDefault <> OA.value 100000
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
      <>  showDefault <> OA.value "broker,protocol"
      <>  help "Kafka debug modules, comma separated names: see debug in CONFIGURATION.md"
      )
  <*> readOption
      (   long "kafka-consumer-commit-period-sec"
      <>  metavar "KAFKA_CONSUMER_COMMIT_PERIOD_SEC"
      <>  showDefault <> OA.value 60
      <>  help "Kafka consumer offsets commit period (in seconds)"
      )

awsConfigParser :: Parser AwsConfig
awsConfigParser = AwsConfig
  <$> readOrFromTextOption
      (  long "region"
      <> metavar "AWS_REGION"
      <> showDefault <> OA.value Oregon
      <> help "The AWS region in which to operate"
      )
  <*> readOption
      (  long "upload-threads"
      <> metavar "NUM_THREADS"
      <> showDefault <> OA.value 20
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
