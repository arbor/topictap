{-# LANGUAGE TemplateHaskell #-}

module App.Lens where

import App.AppEnv
import App.Commands.Types
import App.Options.Types
import Control.Lens

makeFields ''AppEnv
makeFields ''AppLogger
makeFields ''AwsConfig
makeFields ''KafkaConfig
makeFields ''AppOptions
makeFields ''StatsConfig
makeFields ''StoreConfig
