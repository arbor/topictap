{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE MultiParamTypeClasses  #-}
{-# LANGUAGE TemplateHaskell        #-}
module App.AppEnv
where

import App.Options
import Arbor.Logger   (LogLevel, TimedFastLogger)
import Control.Lens
import Network.AWS    (Env, HasEnv (..))
import Network.StatsD (StatsClient)

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

makeClassy ''AppLogger
makeClassy ''AppEnv

instance HasEnv AppEnv where
  environment = appEnvAws

class HasStatsClient a where
  statsClient :: Lens' a StatsClient

instance HasStatsClient StatsClient where
  statsClient = id

instance HasStatsClient AppEnv where
  statsClient = appStatsClient

instance HasKafkaConfig AppEnv where
  kafkaConfig = appOptions . kafkaConfig

instance HasStatsConfig AppEnv where
  statsConfig = appOptions . statsConfig

instance HasAppLogger AppEnv where
  appLogger = appEnv . appLog

instance HasAwsConfig AppEnv where
  awsConfig = appOptions . optAwsConfig
