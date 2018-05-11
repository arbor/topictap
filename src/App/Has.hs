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
  environment = L.aws

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

