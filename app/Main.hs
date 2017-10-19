{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables   #-}

module Main where

import App
import App.Kafka
import Arbor.Logger
import Control.Exception
import Control.Lens
import Control.Monad                        (void)
import Control.Monad.Catch                  (MonadThrow)
import Control.Monad.State
import Control.Monad.Trans.Class            (lift)
import Data.Conduit
import Data.Maybe                           (catMaybes)
import Data.Semigroup                       ((<>))
import HaskellWorks.Data.Conduit.Combinator
import Kafka.Avro                           (schemaRegistry)
import Kafka.Conduit.Sink                   hiding (logLevel)
import Kafka.Conduit.Source
import Network.StatsD                       as S
import System.Environment

import qualified Data.Map  as M
import qualified Data.Set  as S
import qualified Data.Text as T

reportProgress :: (MonadLogger m, MonadStats m, MonadState AppState m) => m ()
reportProgress = do
  reads' <- use readCount
  writes <- use writeCount
  let drops = reads' - writes
  logInfo $ "Reads: " <> show reads' <> ", writes: " <> show writes
  sendMetric (addCounter (MetricName "scorefilter.read.count" ) id reads')
  sendMetric (addCounter (MetricName "scorefilter.write.count") id writes)
  sendMetric (addCounter (MetricName "scorefilter.drop.count") id drops)
  readCount .= 0
  writeCount .= 0

onRebalance :: (MonadLogger m, MonadThrow m, MonadIO m) => KafkaConsumer -> TopicName -> (S.Set PartitionId -> m a) -> ConduitM o o m ()
onRebalance consumer topicName handleRebalance = go S.empty
  where go lastAssignment = do
          ma <- await
          case ma of
            Just a -> do
              assignmentMap <- assignment consumer >>= throwAs KafkaErr
              let currentAssignment = S.fromList (concat (M.lookup topicName assignmentMap))
              if currentAssignment /= lastAssignment && S.empty /= currentAssignment
                then do
                  _ <- lift $ handleRebalance currentAssignment
                  yield a
                  go currentAssignment
                else do
                  yield a
                  go lastAssignment
            Nothing -> return ()

main :: IO ()
main = do
  opt <- parseOptions
  progName <- T.pack <$> getProgName
  let aLogLevel = opt ^. optLogLevel
  let kafkaConf = opt ^. optKafkaConfig
  let statsConf = opt ^. optStatsConfig

  withStdOutTimedFastLogger $ \lgr -> do
    withStatsClient progName statsConf $ \stats -> do
      let envApp = AppEnv opt stats (AppLogger lgr aLogLevel)

      void . runApplication envApp $ do
        let inputTopic = opt ^. optInputTopic
        logInfo $ "Creating Kafka Consumer on " <> show inputTopic
        consumer <- mkConsumer Nothing (opt ^. optInputTopic) (const (pushLogMessage lgr LevelWarn ("Rebalance is in progress!" :: String)))
        producer <- mkProducer

        logInfo "Instantiating Schema Registry"
        sr <- schemaRegistry (kafkaConf ^. schemaRegistryAddress)

        inPartitionCount <- getPartitionCount consumer inputTopic >>= throwAs KafkaErr
        logInfo $ "Input topic " <> show inputTopic <> " has " <> show inPartitionCount <> " partitions"

        logInfo "Running Kafka Consumer"
        runConduit $
          kafkaSourceNoClose consumer (kafkaConf ^. pollTimeoutMs)
          .| onRebalance consumer inputTopic (\_ -> logInfo "Handling rebalance")
          .| throwLeftSatisfy isFatal                      -- throw any fatal error
          .| skipNonFatalExcept [isPollTimeout]            -- discard any non-fatal except poll timeouts
          .| everyNSeconds (kafkaConf ^. commitPeriodSec)  -- only commit ever N seconds, so we don't hammer Kafka.
          .| effectC' reportProgress
          .| flushThenCommitSink consumer producer

    pushLogMessage lgr LevelError ("Premature exit, must not happen." :: String)

withStatsClient :: AppName -> StatsConfig -> (StatsClient -> IO ()) -> IO ()
withStatsClient appName statsConf f = do
  globalTags <- mkStatsTags statsConf
  let statsOpts = DogStatsSettings (statsConf ^. statsHost) (statsConf ^. statsPort)
  bracket (createStatsClient statsOpts (MetricName appName) globalTags) closeStatsClient f

mkStatsTags :: StatsConfig -> IO [Tag]
mkStatsTags statsConf = do
  deplId <- envTag "TASK_DEPLOY_ID" "deploy_id"
  let envTags = catMaybes [deplId]
  return $ envTags <> (statsConf ^. statsTags <&> toTag)
  where
    toTag (StatsTag (k, v)) = S.tag k v
