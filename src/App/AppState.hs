{-# LANGUAGE TemplateHaskell #-}

module App.AppState where

import Control.Lens

data AppState = AppState
  { _readCount  :: Int
  , _writeCount :: Int
  }

makeLenses ''AppState

appStateEmpty :: AppState
appStateEmpty = AppState 0 0
