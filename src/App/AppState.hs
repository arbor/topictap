{-# LANGUAGE TemplateHaskell #-}

module App.AppState
  ( AppState(..)
  , HasAppState(..)
  , FileCache(..), HasFileCache(..)
  , FileCacheEntry(..)
  , fileCacheEmpty
  , appStateEmpty

  , fceFileName
  , fceOffsetFirst
  , fceOffsetLast
  , fceTopicName
  , fcePartitionId
  , fceOutputStream

  ) where

import Control.Lens
import Kafka.Consumer.Types
import Kafka.Types

import qualified Data.ByteString   as BS
import qualified Data.Map          as M
import qualified System.IO.Streams as IO

data FileCacheEntry = FileCacheEntry
  { _fceFileName     :: FilePath
  , _fceOffsetFirst  :: Offset
  , _fceOffsetLast   :: Offset
  , _fceTopicName    :: TopicName
  , _fcePartitionId  :: PartitionId
  , _fceOutputStream :: IO.OutputStream BS.ByteString
  }

newtype FileCache = FileCache
  { _fcEntries :: M.Map (TopicName, PartitionId) FileCacheEntry
  }

data AppState = AppState
  { _stateMsgReadCount  :: Int
  , _stateMsgWriteCount :: Int
  , _stateFileCache     :: FileCache
  }

makeLenses ''FileCacheEntry
makeClassy ''FileCache
makeClassy ''AppState

instance HasFileCache AppState where
  fileCache = stateFileCache

fileCacheEmpty :: FileCache
fileCacheEmpty = FileCache M.empty

appStateEmpty :: AppState
appStateEmpty = AppState 0 0 fileCacheEmpty
