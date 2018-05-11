{-# LANGUAGE TemplateHaskell #-}

module App.Db.Lens where

import Control.Lens

import qualified App.Db.Type as T

makeFields ''T.TopicPartitionOffsets
