module App.AppState.Type where

import Kafka.Consumer.Types
import Kafka.Types

import qualified Data.ByteString   as BS
import qualified Data.Map          as M
import qualified System.IO.Streams as IO

data FileCacheEntry = FileCacheEntry
  { _fileCacheEntryFileName       :: FilePath
  , _fileCacheEntryOffsetFirst    :: Offset
  , _fileCacheEntryTimestampFirst :: Timestamp
  , _fileCacheEntryOffsetMax      :: Offset
  , _fileCacheEntryTimestampLast  :: Timestamp
  , _fileCacheEntryTopicName      :: TopicName
  , _fileCacheEntryPartitionId    :: PartitionId
  , _fileCacheEntryOutputStream   :: IO.OutputStream BS.ByteString
  }

newtype FileCache = FileCache
  { _fileCacheEntries :: M.Map (TopicName, PartitionId) FileCacheEntry
  }

data AppState = AppState
  { _appStateMsgReadCount  :: Int
  , _appStateMsgWriteCount :: Int
  , _appStateFileCache     :: FileCache
  }

fileCacheEmpty :: FileCache
fileCacheEmpty = FileCache M.empty

appStateEmpty :: AppState
appStateEmpty = AppState 0 0 fileCacheEmpty
