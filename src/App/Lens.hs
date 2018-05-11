{-# LANGUAGE TemplateHaskell #-}

module App.Lens where

import App.Options
import Control.Lens

makeFields ''AwsConfig
makeFields ''KafkaConfig
makeFields ''AppOptions
makeFields ''StatsConfig
makeFields ''StoreConfig
