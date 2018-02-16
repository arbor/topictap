{-# LANGUAGE TemplateHaskell #-}

module App.AppState
  ( AppState(..)
  , appStateEmpty

  , stateReadCount
  , stateWriteCount
  , stateFileCache

  , fceFileName
  , fceOffsetFirst
  , fceOffsetLast
  , fceTopicName
  , fcePartitionId
  , fceHandle

  , fcEntries
  ) where

import Control.Lens
import Kafka.Consumer.Types
import Kafka.Types
import System.IO

import qualified Data.Map as M

data FileCacheEntry = FileCacheEntry
  { _fceFileName    :: FilePath
  , _fceOffsetFirst :: Offset
  , _fceOffsetLast  :: Offset
  , _fceTopicName   :: TopicName
  , _fcePartitionId :: PartitionId
  , _fceHandle      :: Handle
  } deriving (Eq, Show)

newtype FileCache = FileCache
  { _fcEntries :: M.Map (TopicName, PartitionId) FileCacheEntry
  } deriving (Eq, Show)

data AppState = AppState
  { _stateReadCount  :: Int
  , _stateWriteCount :: Int
  , _stateFileCache  :: FileCache
  } deriving (Eq, Show)

makeLenses ''FileCacheEntry
makeLenses ''FileCache
makeLenses ''AppState

appStateEmpty :: AppState
appStateEmpty = AppState 0 0 (FileCache M.empty)
