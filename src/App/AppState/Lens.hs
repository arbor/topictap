{-# LANGUAGE TemplateHaskell #-}

module App.AppState.Lens where

import App.AppState.Type
import Control.Lens

makeFields ''FileCacheEntry
makeFields ''FileCache
makeFields ''AppState
