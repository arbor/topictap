{-# LANGUAGE ScopedTypeVariables #-}

module App.Service
  ( handleStream
  ) where

import App
import App.Codec
import Conduit
import Control.Lens
import Control.Monad.State.Class
import Data.Avro.Schema                     ()
import Data.Avro.Types                      ()
import Data.ByteString                      (ByteString)
import Data.Monoid                          ((<>))
import HaskellWorks.Data.Conduit.Combinator
import Kafka.Avro
import Kafka.Conduit.Source
import System.IO
import Text.Printf

import qualified Data.Aeson              as J
import qualified Data.Aeson.Text         as JT
import qualified Data.ByteString         as BS
import qualified Data.ByteString.Lazy    as LBS
import qualified Data.Map                as M
import qualified Data.Text.Lazy.Encoding as LT
import qualified System.Directory        as D

-- | Handles the stream of incoming messages.
handleStream :: MonadApp m
             => SchemaRegistry
             -> FilePath
             -> Conduit (ConsumerRecord (Maybe ByteString) (Maybe ByteString)) m ()
handleStream sr fp =
     effectC (const (stateMsgReadCount += 1))
  .| mapMC (decodeMessage sr)
  .| effectC (writeDecodedMessage fp)
  .| effectC (const (stateMsgWriteCount += 1))
  .| mapC (const ())

handleForMessage :: MonadApp m => FilePath -> ConsumerRecord (Maybe BS.ByteString) J.Value -> m Handle
handleForMessage parentPath msg = do
  s <- get

  case M.lookup (crTopic msg, crPartition msg) (s ^. stateFileCache . fcEntries) of
    Just entry -> do
      put $ s & stateFileCache . fcEntries %~ M.insert (crTopic msg, crPartition msg) (entry & fceOffsetLast .~ crOffset msg)
      return $ entry ^. fceHandle
    Nothing -> do
      liftIO $ D.createDirectoryIfMissing True dirPath
      let filePath = dirPath <> "/" <> printf "%05d" partitionId <> ".json"
      h <- liftIO $ openFile filePath WriteMode
      let entry = FileCacheEntry
            { _fceFileName     = filePath
            , _fceOffsetFirst  = crOffset     msg
            , _fceOffsetLast   = crOffset     msg
            , _fceTopicName    = crTopic      msg
            , _fcePartitionId  = crPartition  msg
            , _fceHandle       = h
            }
      put $ s & stateFileCache . fcEntries %~ M.insert (crTopic msg, crPartition msg) entry
      return h
  where TopicName topicName     = crTopic msg
        PartitionId partitionId = crPartition msg
        dirPath                 = parentPath <> "/" <> topicName

writeDecodedMessage :: MonadApp m => FilePath -> ConsumerRecord (Maybe BS.ByteString) J.Value -> m ()
writeDecodedMessage parentPath msg = do
  h <- handleForMessage parentPath msg
  liftIO $ LBS.hPut h (LT.encodeUtf8 (JT.encodeToLazyText (crValue msg)))
