{-# LANGUAGE TemplateHaskell #-}

module App.Lens where

import App.Options
import Control.Lens

makeFields ''KafkaConfig
makeFields ''StatsConfig
makeFields ''StoreConfig
