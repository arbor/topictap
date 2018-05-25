{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE MultiParamTypeClasses  #-}
{-# LANGUAGE TemplateHaskell        #-}

module App.AppEnv where

import Antiope.Env    (Env)
import Arbor.Logger   (LogLevel, TimedFastLogger)
import Network.StatsD (StatsClient)

data AppLogger = AppLogger
  { _appLoggerLogger   :: TimedFastLogger
  , _appLoggerLogLevel :: LogLevel
  }

data AppEnv o = AppEnv
  { _appEnvOptions     :: o
  , _appEnvStatsClient :: StatsClient
  , _appEnvLog         :: AppLogger
  , _appEnvAws         :: Env
  }
