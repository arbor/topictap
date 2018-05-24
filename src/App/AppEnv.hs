{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE MultiParamTypeClasses  #-}
{-# LANGUAGE TemplateHaskell        #-}

module App.AppEnv where

import Antiope.Env    (Env)
import App.Options
import Arbor.Logger   (LogLevel, TimedFastLogger)
import Control.Lens
import Network.StatsD (StatsClient)

data AppLogger = AppLogger
  { _alLogger   :: TimedFastLogger
  , _alLogLevel :: LogLevel
  }

data AppEnv = AppEnv
  { _appEnvOptions     :: AppOptions
  , _appEnvStatsClient :: StatsClient
  , _appEnvLog         :: AppLogger
  , _appEnvAws         :: Env
  }

makeClassy ''AppLogger
