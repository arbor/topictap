{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications      #-}

module App.AppEnv where

import Antiope.Env               (Env, HasEnv (..))
import Arbor.Logger              (LogLevel, TimedFastLogger)
import Data.Generics.Product.Any
import GHC.Generics
import Network.StatsD            (StatsClient)

data AppLogger = AppLogger
  { logger   :: TimedFastLogger
  , logLevel :: LogLevel
  } deriving Generic

data AppEnv o = AppEnv
  { options     :: o
  , statsClient :: StatsClient
  , logger      :: AppLogger
  , aws         :: Env
  } deriving Generic

instance HasEnv (AppEnv o) where
  environment = the @"aws"
