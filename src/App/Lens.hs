{-# LANGUAGE TemplateHaskell #-}

module App.Lens where

import App.AppEnv
import App.Options
import Control.Lens

makeFields ''AppEnv
makeFields ''AppLogger
makeFields ''AwsConfig
makeFields ''KafkaConfig
makeFields ''AppOptions
makeFields ''StatsConfig
makeFields ''StoreConfig
