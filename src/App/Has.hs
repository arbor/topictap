{-# OPTIONS_GHC -Wno-orphans #-}

module App.Has where

import Antiope.Env    (HasEnv (..))
import App.Options
import Control.Lens
import Data.Function  (id)
import Network.StatsD (StatsClient)

import qualified App.AppEnv as E
import qualified App.Lens   as L

instance HasEnv E.AppEnv where
  environment = E.appEnvAws

class HasStatsClient a where
  statsClient :: Lens' a StatsClient

instance HasStatsClient StatsClient where
  statsClient = id

class HasKafkaConfig a where
  kafkaConfig :: Lens' a KafkaConfig

instance HasKafkaConfig KafkaConfig where
  kafkaConfig = id

class HasStatsConfig a where
  statsConfig :: Lens' a StatsConfig

instance HasStatsConfig StatsConfig where
  statsConfig = id

class HasStoreConfig a where
  storeConfig :: Lens' a StoreConfig

instance HasStoreConfig StoreConfig where
  storeConfig = id

class HasAwsConfig a where
  awsConfig :: Lens' a AwsConfig

instance HasAwsConfig AwsConfig where
  awsConfig = id

class HasAppOptions a where
  appOptions :: Lens' a AppOptions

instance HasAppOptions AppOptions where
  appOptions = id



instance HasStatsClient E.AppEnv where
  statsClient = E.appStatsClient

instance HasKafkaConfig E.AppEnv where
  kafkaConfig = E.appOptions . kafkaConfig

instance HasStatsConfig E.AppEnv where
  statsConfig = E.appOptions . statsConfig


instance E.HasAppLogger E.AppEnv where
  appLogger = E.appEnv . E.appLog

instance HasAwsConfig E.AppEnv where
  awsConfig = E.appOptions . awsConfig

instance HasStoreConfig E.AppEnv where
  storeConfig = E.appOptions . storeConfig

instance HasKafkaConfig AppOptions where
  kafkaConfig = L.kafkaConfig

instance HasStatsConfig AppOptions where
  statsConfig = L.statsConfig

instance HasStoreConfig AppOptions where
  storeConfig = L.storeConfig

instance HasAwsConfig AppOptions where
  awsConfig = L.awsConfig

