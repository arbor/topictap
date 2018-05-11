{-# LANGUAGE TemplateHaskell #-}

{-# OPTIONS_GHC -Wno-orphans #-}

module App.Lens where

import App.Type
import Control.Lens
import Network.AWS    (HasEnv (..))
import Network.StatsD (StatsClient)

makeClassy ''KafkaConfig
makeClassy ''StatsConfig
makeClassy ''AwsConfig
makeClassy ''Options
makeClassy ''StoreConfig
makeClassy ''AppLogger
makeClassy ''AppEnv

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

class HasStatsClient a where
  statsClient :: Lens' a StatsClient

instance HasKafkaConfig Options where
  kafkaConfig = optKafkaConfig

instance HasStatsConfig Options where
  statsConfig = optStatsConfig

instance HasStoreConfig Options where
  storeConfig = optStoreConfig

instance HasAwsConfig Options where
  awsConfig = optAwsConfig

instance HasEnv AppEnv where
  environment = appEnvAws

