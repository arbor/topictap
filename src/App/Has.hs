{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module App.Has where

import Antiope.Env        (HasEnv (..))
import App.AppEnv
import App.Commands.Types
import App.Options.Types
import Control.Lens
import Network.StatsD     (StatsClient)

import qualified App.AppEnv as E
import qualified App.Lens   as L

instance HasEnv (E.AppEnv o) where
  environment = L.aws

makeClassy ''AppLogger
makeClassy ''AppOptions
makeClassy ''AwsConfig
makeClassy ''KafkaConfig
makeClassy ''StatsClient
makeClassy ''StatsConfig
makeClassy ''StoreConfig

instance HasStatsClient (E.AppEnv o) where
  statsClient = L.statsClient

instance HasKafkaConfig o => HasKafkaConfig (E.AppEnv o) where
  kafkaConfig = L.options . kafkaConfig

instance HasStatsConfig o => HasStatsConfig (E.AppEnv o) where
  statsConfig = L.options . statsConfig

instance HasAppLogger (E.AppEnv o) where
  appLogger = L.log

instance HasAwsConfig o => HasAwsConfig (E.AppEnv o) where
  awsConfig = L.options . awsConfig

instance HasStoreConfig o => HasStoreConfig (E.AppEnv o) where
  storeConfig = L.options . storeConfig

instance HasKafkaConfig AppOptions where
  kafkaConfig = L.kafkaConfig

instance HasStatsConfig AppOptions where
  statsConfig = L.statsConfig

instance HasStoreConfig AppOptions where
  storeConfig = L.storeConfig

instance HasAwsConfig AppOptions where
  awsConfig = L.awsConfig
