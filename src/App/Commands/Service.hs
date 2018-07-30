{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TypeApplications      #-}

module App.Commands.Service
  ( cmdService
  , onRebalance
  ) where

import Antiope.Env                          (mkEnv)
import App.AppEnv
import App.Application
import App.CancellationToken                (newCancellationToken)
import App.Conduit
import App.Conduit.Time                     (sampleC)
import App.Kafka                            (mkConsumer)
import App.Log
import App.Persist                          (uploadAllFiles)
import App.Service                          (handleStream)
import App.Stats
import Arbor.Logger
import Conduit
import Control.Exception                    (IOException, catch)
import Control.Lens                         ((^.))
import Control.Monad                        (forM_, unless, void)
import Control.Monad.Logger                 (LogLevel (..))
import Data.Generics.Product.Any
import Data.Semigroup                       ((<>))
import HaskellWorks.Data.Conduit.Combinator (effectC, effectC', rightC)
import Kafka.Avro                           (schemaRegistry)
import Kafka.Conduit.Source
import Options.Applicative
import System.Directory                     (createDirectoryIfMissing, removeDirectoryRecursive)
import System.Environment                   (getProgName)
import System.IO.Error                      (ioeGetErrorType, isDoesNotExistErrorType)

import qualified App.Commands.Types  as Z
import qualified App.Options.Types   as Z
import qualified Data.Text           as T
import qualified Options.Applicative as OA

cmdService :: Mod CommandFields (IO ())
cmdService = command "service" $ flip info idm $ runService <$> optsService

runService :: Z.AppOptions -> IO ()
runService opt = do
  progName <- T.pack <$> getProgName
  let logLvl    = opt ^. the @"logLevel"
  let kafkaConf = opt ^. the @"kafkaConfig"
  let statsConf = opt ^. the @"statsConfig"

  ctoken <- newCancellationToken

  withStdOutTimedFastLogger $ \lgr -> do
    withStatsClient progName statsConf $ \stats -> do
      let envLogger = AppLogger lgr logLvl
      envAws <- mkEnv (opt ^. the @"awsConfig" . the @"region") (logAWS envLogger)
      let envApp = AppEnv opt stats envLogger envAws

      void . runApplication envApp $ do
        let inputTopics       = opt ^. the @"inputTopics"
        let stagingDirectory  = opt ^. the @"stagingDirectory"

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

        consumer <- mkConsumer Nothing (opt ^. the @"inputTopics") (const (pushLogMessage lgr LevelWarn ("Rebalance is in progress!" :: String)))

        logInfo "Instantiating Schema Registry"
        sr <- schemaRegistry (kafkaConf ^. the @"schemaRegistryAddress")

        logInfo "Running Kafka Consumer"
        runConduit $
          kafkaSourceNoClose consumer (kafkaConf ^. the @"pollTimeoutMs")
          .| throwLeftSatisfy isFatal                      -- throw any fatal error
          .| skipNonFatalExcept [isPollTimeout]            -- discard any non-fatal except poll timeouts
          .| rightC (handleStream sr (opt ^. the @"stagingDirectory"))
          .| sampleC (opt ^. the @"storeConfig" . the @"uploadInterval")
          .| effectC' (logInfo "Uploading files...")
          .| effectC (\(t, _) -> uploadAllFiles ctoken t)
          .| effectC' (logInfo "Uploading completed")
          .| effectC' reportProgress
          .| effectC' (commitAllOffsets OffsetCommit consumer)
          .| sinkNull

    pushLogMessage lgr LevelError ("Premature exit, must not happen." :: String)

optsService :: Parser Z.AppOptions
optsService = Z.AppOptions
  <$> Z.readOptionMsg "Valid values are LevelDebug, LevelInfo, LevelWarn, LevelError"
      (  long "log-level"
      <> metavar "LOG_LEVEL"
      <> showDefault <> OA.value LevelInfo
      <> help "Log level"
      )
  <*> ( (TopicName <$>) . (>>= words) . (fmap Z.commaToSpace <$>) <$> many topicOption)
  <*> strOption
      (  long "staging-directory"
      <> metavar "PATH"
      <> help "Staging directory where generated files are stored and scheduled for upload to S3"
      )
  <*> Z.awsConfigParser
  <*> Z.kafkaConfigParser
  <*> Z.statsConfigParser
  <*> Z.storeConfigParser
  where topicOption = strOption
          (  long "topic"
          <> metavar "TOPIC"
          <> help "Input topic.  Multiple topics can be supplied by repeating the flag or comma/space separating the topic names"
          )
