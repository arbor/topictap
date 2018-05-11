{-# LANGUAGE ScopedTypeVariables #-}

module App.Service
  ( handleStream
  ) where

import App
import App.Codec                            (decodeMessage)
import Conduit
import Control.Lens                         (use, (%=), (%~), (&), (+=), (.~), (^.))
import Data.ByteString                      (ByteString)
import Data.Monoid                          ((<>))
import HaskellWorks.Data.Conduit.Combinator (effectC)
import Kafka.Avro                           (SchemaRegistry)
import Kafka.Conduit.Source                 (ConsumerRecord (..), Offset (..), PartitionId (..), TopicName (..))
import System.IO                            (Handle, IOMode (..), hClose, hFlush, openFile)
import Text.Printf

import qualified App.AppState.Lens       as L
import qualified Data.Aeson              as J
import qualified Data.Aeson.Text         as JT
import qualified Data.ByteString         as BS
import qualified Data.ByteString.Lazy    as LBS
import qualified Data.Map                as M
import qualified Data.Text.Lazy.Encoding as LT
import qualified System.Directory        as D
import qualified System.IO.Streams       as IO

-- | Handles the stream of incoming messages.
handleStream :: MonadApp m
             => SchemaRegistry
             -> FilePath
             -> Conduit (ConsumerRecord (Maybe ByteString) (Maybe ByteString)) m ()
handleStream sr fp =
     effectC (const (L.msgReadCount += 1))
  .| mapMC (decodeMessage sr)
  .| effectC (writeDecodedMessage fp)
  .| effectC (const (L.msgWriteCount += 1))
  .| mapC (const ())

handleToClosingOutputStream :: Handle -> IO (IO.OutputStream ByteString)
handleToClosingOutputStream h = IO.makeOutputStream f
  where f Nothing  = hFlush h >> hClose h
        f (Just x) = if BS.null x then hFlush h else BS.hPut h x

-- TODO Inline this function when Ord Offset becomes available
updateOffset :: Offset -> Offset -> Offset
updateOffset (Offset a) (Offset b) = Offset (a `max` b)

outputStreamForMessage :: MonadApp m => FilePath -> ConsumerRecord (Maybe BS.ByteString) J.Value -> m (IO.OutputStream BS.ByteString)
outputStreamForMessage parentPath msg = do
  entries <- use (L.fileCache . L.entries)

  case M.lookup (crTopic msg, crPartition msg) entries of
    Just entry -> do
      (L.fileCache . L.entries %=) $ M.insert (crTopic msg, crPartition msg) $ entry
        & L.offsetMax     %~ updateOffset (crOffset msg)
        & L.timestampLast .~ crTimestamp msg
      return $ entry ^. L.outputStream
    Nothing -> do
      liftIO $ D.createDirectoryIfMissing True dirPath
      let filePath = dirPath <> "/" <> printf "%05d" partitionId <> ".json"
      h <- liftIO $ openFile filePath WriteMode
      os <- liftIO $ handleToClosingOutputStream h
      zos <- liftIO $ IO.gzip IO.defaultCompressionLevel os
      let entry = FileCacheEntry
            { _fileCacheEntryFileName       = filePath
            , _fileCacheEntryOffsetFirst    = crOffset     msg
            , _fileCacheEntryTimestampFirst = crTimestamp  msg
            , _fileCacheEntryTimestampLast  = crTimestamp  msg
            , _fileCacheEntryOffsetMax      = crOffset     msg
            , _fileCacheEntryTopicName      = crTopic      msg
            , _fileCacheEntryPartitionId    = crPartition  msg
            , _fileCacheEntryOutputStream   = zos
            }
      L.fileCache . L.entries %= M.insert (crTopic msg, crPartition msg) entry
      return zos
  where PartitionId partitionId = crPartition msg
        dirPath                 = parentPath <> "/" <> unTopicName (crTopic msg)

writeDecodedMessage :: MonadApp m => FilePath -> ConsumerRecord (Maybe BS.ByteString) J.Value -> m ()
writeDecodedMessage parentPath msg = do
  os <- outputStreamForMessage parentPath msg
  liftIO $ IO.write (Just (LBS.toStrict (LT.encodeUtf8 (JT.encodeToLazyText (crValue msg))))) os
