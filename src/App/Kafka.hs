{-# LANGUAGE MultiParamTypeClasses #-}

module App.Kafka where

import App.AppEnv
import App.Options
import Arbor.Logger
import Control.Lens                 hiding (cons)
import Control.Monad                (void)
import Control.Monad.Logger         (LogLevel (..))
import Control.Monad.Reader
import Control.Monad.Trans.Resource
import Data.Foldable
import Data.List.Split
import Data.Monoid                  ((<>))
import Kafka.Conduit.Sink           as KSnk
import Kafka.Conduit.Source         as KSrc
import Kafka.Metadata

import qualified Data.Map as M
import qualified Data.Set as S

type ConsumerGroupSuffix = String

rebalanceHandler :: ([(TopicName, PartitionId)] -> IO ()) -> KafkaConsumer -> RebalanceEvent -> IO ()
rebalanceHandler onRebalance _ e =
    case e of
      RebalanceBeforeAssign ps -> onRebalance ps
      RebalanceBeforeRevoke _  -> onRebalance []
      RebalanceAssign _        -> pure ()
      RebalanceRevoke _        -> pure ()

mkConsumer :: (MonadResource m, MonadReader r m, HasKafkaConfig r, HasAppLogger r)
            => Maybe ConsumerGroupSuffix
            -> [TopicName]
            -> ([(TopicName, PartitionId)] -> IO ())
            -> m KafkaConsumer
mkConsumer suffix ts onRebalance = do
  conf <- view kafkaConfig
  logs <- view appLogger
  let props = fold
        [ KSrc.brokersList [conf ^. broker]
        , conf ^. consumerGroupId    & adjustGroupId suffix & groupId
        , conf ^. queuedMaxMsgKBytes & queuedMaxMessagesKBytes
        , noAutoCommit
        , KSrc.suppressDisconnectLogs
        , KSrc.logLevel (kafkaLogLevel (logs ^. alLogLevel))
        , KSrc.debugOptions (kafkaDebugEnable (conf ^. debugOpts))
        , KSrc.setCallback (logCallback   (\l s1 s2 -> pushLogMessage (logs ^. alLogger) (kafkaLogLevelToLogLevel $ toEnum l) ("[" <> s1 <> "] " <> s2)))
        , KSrc.setCallback (errorCallback (\e s -> pushLogMessage (logs ^. alLogger) LevelError ("[" <> show e <> "] " <> s)))
        , KSrc.setCallback (rebalanceCallback (rebalanceHandler onRebalance))
        ]
      sub = topics ts <> offsetReset Earliest
      cons = newConsumer props sub >>= either throwM return
  snd <$> allocate cons (void . closeConsumer)

mkProducer :: (MonadResource m, MonadReader r m, HasKafkaConfig r, HasAppLogger r) => m KafkaProducer
mkProducer = do
  conf <- view kafkaConfig
  logs <- view appLogger
  let props = KSnk.brokersList [conf ^. broker]
           <> KSnk.suppressDisconnectLogs
           <> KSnk.sendTimeout (Timeout 0) -- message sending timeout, 0 means "no timeout"
           <> KSnk.compression Gzip
           <> KSnk.logLevel (kafkaLogLevel (logs ^. alLogLevel))
           <> KSnk.setCallback (logCallback   (\l s1 s2 -> pushLogMessage (logs ^. alLogger) (kafkaLogLevelToLogLevel $ toEnum l) ("[" <> s1 <> "] " <> s2)))
           <> KSnk.setCallback (errorCallback (\e s -> pushLogMessage (logs ^. alLogger) LevelError ("[" <> show e <> "] " <> s)))
           <> KSnk.setCallback (deliveryErrorsCallback (logAndDieHard (logs ^. alLogger)))
           <> KSnk.extraProps (M.singleton "linger.ms"                 "100")
           <> KSnk.extraProps (M.singleton "message.send.max.retries"  "0"  )
           <> KSnk.compression Gzip
      prod = newProducer props >>= either throwM return
  snd <$> allocate prod closeProducer

logAndDieHard :: TimedFastLogger -> KafkaError -> IO ()
logAndDieHard lgr err = do
  let errMsg = "Producer is unable to deliver messages: " <> show err
  pushLogMessage lgr LevelError errMsg
  error errMsg

adjustGroupId :: Maybe ConsumerGroupSuffix -> ConsumerGroupId -> ConsumerGroupId
adjustGroupId (Just suffix) (ConsumerGroupId txt) = ConsumerGroupId (txt <> "-" <> suffix)
adjustGroupId _ cgid                              = cgid

kafkaLogLevel :: LogLevel -> KafkaLogLevel
kafkaLogLevel l = case l of
  LevelDebug   -> KafkaLogDebug
  LevelInfo    -> KafkaLogInfo
  LevelWarn    -> KafkaLogWarning
  LevelError   -> KafkaLogErr
  LevelOther _ -> KafkaLogCrit

kafkaLogLevelToLogLevel :: KafkaLogLevel -> LogLevel
kafkaLogLevelToLogLevel l = case l of
  KafkaLogDebug   -> LevelDebug
  KafkaLogInfo    -> LevelInfo
  KafkaLogWarning -> LevelWarn
  KafkaLogErr     -> LevelError
  KafkaLogCrit    -> LevelError
  KafkaLogAlert   -> LevelWarn
  KafkaLogNotice  -> LevelInfo
  KafkaLogEmerg   -> LevelError

kafkaDebugEnable :: String -> [KafkaDebug]
kafkaDebugEnable str = map debug (splitWhen (== ',') str)
  where
    debug :: String -> KafkaDebug
    debug m = case m of
      "generic"  -> DebugGeneric
      "broker"   -> DebugBroker
      "topic"    -> DebugTopic
      "metadata" -> DebugMetadata
      "queue"    -> DebugQueue
      "msg"      -> DebugMsg
      "protocol" -> DebugProtocol
      "cgrp"     -> DebugCgrp
      "security" -> DebugSecurity
      "fetch"    -> DebugFetch
      "feature"  -> DebugFeature
      "all"      -> DebugAll
      _          -> DebugGeneric

getPartitionCount :: MonadIO m => KafkaConsumer -> TopicName -> m (Either KafkaError Int)
getPartitionCount consumer topicName = do
  kafkaMetadataResult <- topicMetadata consumer (Timeout 10000) topicName
  return $ do
    kafkaMetadata <- kafkaMetadataResult
    return (length (pmPartitionId  <$> (kmTopics kafkaMetadata >>= tmPartitions)))

getAssignedPartitions :: MonadIO m => KafkaConsumer -> m (Either KafkaError (S.Set PartitionId))
getAssignedPartitions k = do
  ass <- assignment k
  return $ ass <&> M.foldl' mappend [] <&> S.fromList
