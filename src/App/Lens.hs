{-# LANGUAGE TemplateHaskell #-}

module App.Lens where

import App.AppEnv
import App.AppState.Type
import App.Commands.Types
import App.Options.Types
import Control.Lens

makeFields ''AppEnv
makeFields ''AppLogger
makeFields ''AppOptions
makeFields ''AppState
makeFields ''AwsConfig
makeFields ''BackupEntry
makeFields ''FileCache
makeFields ''FileCacheEntry
makeFields ''KafkaConfig
makeFields ''StatsConfig
makeFields ''StoreConfig
