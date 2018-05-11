{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module App.Has where

import Antiope.Env    (HasEnv (..))
import App.Options
import Control.Lens
import Network.StatsD (StatsClient)

import qualified App.AppEnv as E
import qualified App.Lens   as L

instance HasEnv E.AppEnv where
  environment = L.aws

makeClassy ''StatsClient
makeClassy ''KafkaConfig
makeClassy ''StatsConfig
makeClassy ''StoreConfig
makeClassy ''AwsConfig
makeClassy ''AppOptions

instance HasStatsClient E.AppEnv where
  statsClient = L.statsClient

instance HasKafkaConfig E.AppEnv where
  kafkaConfig = L.options . kafkaConfig

instance HasStatsConfig E.AppEnv where
  statsConfig = L.options . statsConfig

instance E.HasAppLogger E.AppEnv where
  appLogger = L.log

instance HasAwsConfig E.AppEnv where
  awsConfig = L.options . awsConfig

instance HasStoreConfig E.AppEnv where
  storeConfig = L.options . storeConfig

instance HasKafkaConfig AppOptions where
  kafkaConfig = L.kafkaConfig

instance HasStatsConfig AppOptions where
  statsConfig = L.statsConfig

instance HasStoreConfig AppOptions where
  storeConfig = L.storeConfig

instance HasAwsConfig AppOptions where
  awsConfig = L.awsConfig
