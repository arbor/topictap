{-# LANGUAGE DuplicateRecordFields #-}

module App.AppState.Type where

import GHC.Generics
import Kafka.Consumer.Types
import Kafka.Types

import qualified Data.ByteString   as BS
import qualified Data.Map          as M
import qualified System.IO.Streams as IO

data BackupEntry = BackupEntry
  { fileName       :: FilePath
  , offsetFirst    :: Offset
  , timestampFirst :: Timestamp
  , offsetMax      :: Offset
  , timestampLast  :: Timestamp
  , topicName      :: TopicName
  , partitionId    :: PartitionId
  } deriving Generic

data FileCacheEntry = FileCacheEntry
  { backupEntry  :: BackupEntry
  , outputStream :: IO.OutputStream BS.ByteString
  } deriving Generic

newtype FileCache = FileCache
  { entries :: M.Map (TopicName, PartitionId) FileCacheEntry
  } deriving Generic

data AppState = AppState
  { msgReadCount  :: Int
  , msgWriteCount :: Int
  , fileCache     :: FileCache
  } deriving Generic

fileCacheEmpty :: FileCache
fileCacheEmpty = FileCache M.empty

appStateEmpty :: AppState
appStateEmpty = AppState 0 0 fileCacheEmpty
