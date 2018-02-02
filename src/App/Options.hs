{-# LANGUAGE TemplateHaskell #-}

module App.Options where

import Control.Lens
import Control.Monad.Logger (LogLevel (..))
import Data.Semigroup       ((<>))
import Network.Socket       (HostName)
import Network.StatsD       (SampleRate (..))

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

data Options = Options
  { _optLogLevel    :: LogLevel
  , _optInputTopics :: [TopicName]
  , _optKafkaConfig :: KafkaConfig
  , _optStatsConfig :: StatsConfig
  } deriving (Show)

makeClassy ''KafkaConfig
makeClassy ''StatsConfig
makeClassy ''Options

instance HasKafkaConfig Options where
  kafkaConfig = optKafkaConfig

instance HasStatsConfig Options where
  statsConfig = optStatsConfig

statsConfigParser :: Parser StatsConfig
statsConfigParser = StatsConfig
  <$> strOption
    (  long "statsd-host"
    <> metavar "HOST_NAME"
    <> showDefault <> value "127.0.0.1"
    <> help "StatsD host name or IP address")
  <*> readOption
    (  long "statsd-port"
    <> metavar "PORT"
    <> showDefault <> value 8125
    <> help "StatsD port"
    <> hidden)
  <*> ( string2Tags <$> strOption
    (  long "statsd-tags"
    <> metavar "TAGS"
    <> showDefault <> value []
    <> help "StatsD tags"))
  <*> ( SampleRate <$> readOption
    (  long "statsd-sample-rate"
    <> metavar "SAMPLE_RATE"
    <> showDefault <> value 0.01
    <> help "StatsD sample rate"))

kafkaConfigParser :: Parser KafkaConfig
kafkaConfigParser = KafkaConfig
  <$> ( BrokerAddress <$> strOption
    (  long "kafka-broker"
    <> metavar "ADDRESS:PORT"
    <> help "Kafka bootstrap broker"
    ))
  <*> strOption
    (  long "kafka-schema-registry"
    <> metavar "HTTP_URL:PORT"
    <> help "Schema registry address")
  <*> (Timeout <$> readOption
    (  long "kafka-poll-timeout-ms"
    <> metavar "KAFKA_POLL_TIMEOUT_MS"
    <> showDefault <> value 1000
    <> help "Kafka poll timeout (in milliseconds)"))
  <*> readOption
    (  long "kafka-queued-max-messages-kbytes"
    <> metavar "KAFKA_QUEUED_MAX_MESSAGES_KBYTES"
    <> showDefault <> value 100000
    <> help "Kafka queued.max.messages.kbytes")
  <*> ( ConsumerGroupId <$> strOption
    (  long "kafka-group-id"
    <> metavar "GROUP_ID"
    <> help "Kafka consumer group id"))
  <*> strOption
    (  long "kafka-debug-enable"
    <> metavar "KAFKA_DEBUG_ENABLE"
    <> showDefault <> value "broker,protocol"
    <> help "Kafka debug modules, comma separated names: see debug in CONFIGURATION.md"
    )
  <*> readOption
    (  long "kafka-consumer-commit-period-sec"
    <> metavar "KAFKA_CONSUMER_COMMIT_PERIOD_SEC"
    <> showDefault <> value 60
    <> help "Kafka consumer offsets commit period (in seconds)"
    )

optParser :: Parser Options
optParser = Options
  <$> readOptionMsg "Valid values are LevelDebug, LevelInfo, LevelWarn, LevelError"
    (  long "log-level"
    <> metavar "LOG_LEVEL"
    <> showDefault <> value LevelInfo
    <> help "Log level")
  <*> ( (TopicName <$>) . (>>= words) . (fmap commaToSpace <$>) <$> many topicOption)
  <*> kafkaConfigParser
  <*> statsConfigParser
  where topicOption = strOption
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
