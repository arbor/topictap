{-# OPTIONS_GHC -Wno-orphans #-}

module App.Has where

import Antiope.Env    (HasEnv (..))
import App.AppEnv
import App.Options
import Control.Lens
import Network.StatsD (StatsClient)

instance HasEnv AppEnv where
  environment = appEnvAws

class HasStatsClient a where
  statsClient :: Lens' a StatsClient

class HasKafkaConfig a where
  kafkaConfig :: Lens' a KafkaConfig

class HasStatsConfig a where
  statsConfig :: Lens' a StatsConfig

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

instance HasStoreConfig AppEnv where
  storeConfig = appOptions . optStoreConfig

instance HasKafkaConfig Options where
  kafkaConfig = optKafkaConfig

instance HasStatsConfig Options where
  statsConfig = optStatsConfig

instance HasStoreConfig Options where
  storeConfig = optStoreConfig

instance HasAwsConfig Options where
  awsConfig = optAwsConfig

