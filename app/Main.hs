{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables   #-}

module Main
  ( main
  , onRebalance
  ) where

import App
import App.AWS.Env
import App.CancellationToken                (newCancellationToken)
import App.Conduit.Time
import App.Kafka
import App.Persist
import App.Service
import Arbor.Logger
import Conduit
import Control.Exception
import Control.Lens
import Control.Monad                        (void)
import Control.Monad.Catch                  (MonadThrow)
import Control.Monad.State
import Control.Monad.Trans.Class            (lift)
import Data.Maybe                           (catMaybes)
import Data.Semigroup                       ((<>))
import HaskellWorks.Data.Conduit.Combinator
import Kafka.Avro                           (schemaRegistry)
import Kafka.Conduit.Sink
import Kafka.Conduit.Source
import Network.StatsD                       as S
import System.Directory
import System.Environment
import System.IO.Error

import qualified App.AppState.Lens as L
import qualified Data.Map          as M
import qualified Data.Set          as S
import qualified Data.Text         as T

reportProgress :: (MonadLogger m, MonadStats m, MonadState AppState m) => m ()
reportProgress = do
  reads' <- use L.msgReadCount
  writes <- use L.msgWriteCount
  let drops = reads' - writes
  logInfo $ "Reads: " <> show reads' <> ", writes: " <> show writes
  sendMetric (addCounter (MetricName "scorefilter.read.count" ) id reads')
  sendMetric (addCounter (MetricName "scorefilter.write.count") id writes)
  sendMetric (addCounter (MetricName "scorefilter.drop.count") id drops)
  L.msgReadCount .= 0
  L.msgWriteCount .= 0

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
  let logLvl    = opt ^. optLogLevel
  let kafkaConf = opt ^. optKafkaConfig
  let statsConf = opt ^. optStatsConfig

  ctoken <- newCancellationToken

  withStdOutTimedFastLogger $ \lgr -> do
    withStatsClient progName statsConf $ \stats -> do
      envAws <- mkEnv (opt ^. awsRegion) logLvl lgr
      let envApp = AppEnv opt stats (AppLogger lgr logLvl) envAws

      void . runApplication envApp $ do
        let inputTopics       = opt ^. optInputTopics
        let stagingDirectory  = opt ^. optStagingDirectory

        logInfo "Creating Kafka Consumer on the following topics:"
        forM_ inputTopics $ \inputTopic -> logInfo $ "  " <> show inputTopic

        logInfo $ "Preparing staging directory: " <> show stagingDirectory
        -- Ensure we our staging directory exists and that we have write access to the
        -- directory by creating a test ready directory.
        let readyDirectory = stagingDirectory <> "/ready"
        liftIO $ removeDirectoryRecursive readyDirectory `catch` \(e :: IOException) ->
          unless (isDoesNotExistErrorType (ioeGetErrorType e)) $ do
            pushLogMessage lgr LevelError ("Unable to prepare staging directory" :: String)
            throwM e
        liftIO $ createDirectoryIfMissing True readyDirectory

        consumer <- mkConsumer Nothing (opt ^. optInputTopics) (const (pushLogMessage lgr LevelWarn ("Rebalance is in progress!" :: String)))

        logInfo "Instantiating Schema Registry"
        sr <- schemaRegistry (kafkaConf ^. schemaRegistryAddress)

        logInfo "Running Kafka Consumer"
        runConduit $
          kafkaSourceNoClose consumer (kafkaConf ^. pollTimeoutMs)
          .| throwLeftSatisfy isFatal                      -- throw any fatal error
          .| skipNonFatalExcept [isPollTimeout]            -- discard any non-fatal except poll timeouts
          .| rightC (handleStream sr (opt ^. optStagingDirectory))
          .| sampleC (opt ^. storeUploadInterval)
          .| effectC' (logInfo "Uploading files...")
          .| effectC (\(t, _) -> uploadAllFiles ctoken t)
          .| effectC' (logInfo "Uploading completed")
          .| effectC' reportProgress
          .| effectC' (commitAllOffsets OffsetCommit consumer)
          .| sinkNull

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
