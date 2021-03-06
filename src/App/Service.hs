{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}

module App.Service
  ( handleStream
  ) where

import App.Application
import App.Codec                            (decodeMessage)
import Conduit
import Control.Lens                         (use, (%=), (%~), (&), (+=), (.~), (^.))
import Data.ByteString                      (ByteString)
import Data.Generics.Product.Any
import Data.Monoid                          ((<>))
import HaskellWorks.Data.Conduit.Combinator (effectC)
import Kafka.Avro                           (SchemaRegistry)
import Kafka.Conduit.Source                 (ConsumerRecord (..), Offset (..), PartitionId (..), TopicName (..))
import System.IO                            (Handle, IOMode (..), hClose, hFlush, openFile)
import Text.Printf

import qualified App.AppState.Type       as Z
import qualified Data.Aeson              as J
import qualified Data.Aeson.Text         as JT
import qualified Data.ByteString         as BS
import qualified Data.ByteString.Lazy    as LBS
import qualified Data.Map                as M
import qualified Data.Text.Lazy.Encoding as LT
import qualified System.Directory        as D
import qualified System.IO.Streams       as IO

-- | Handles the stream of incoming messages.
handleStream :: MonadApp o m
             => SchemaRegistry
             -> FilePath
             -> Conduit (ConsumerRecord (Maybe ByteString) (Maybe ByteString)) m ()
handleStream sr fp =
     effectC (const (the @"msgReadCount" += 1))
  .| mapMC (decodeMessage sr)
  .| effectC (writeDecodedMessage fp)
  .| effectC (const (the @"msgWriteCount" += 1))
  .| mapC (const ())

handleToClosingOutputStream :: Handle -> IO (IO.OutputStream ByteString)
handleToClosingOutputStream h = IO.makeOutputStream f
  where f Nothing  = hFlush h >> hClose h
        f (Just x) = if BS.null x then hFlush h else BS.hPut h x

-- TODO Inline this function when Ord Offset becomes available
updateOffset :: Offset -> Offset -> Offset
updateOffset (Offset a) (Offset b) = Offset (a `max` b)

outputStreamForMessage :: MonadApp o m => FilePath -> ConsumerRecord (Maybe BS.ByteString) J.Value -> m (IO.OutputStream BS.ByteString)
outputStreamForMessage parentPath msg = do
  entries <- use (the @"fileCache" . the @"entries")

  case M.lookup (crTopic msg, crPartition msg) entries of
    Just entry -> do
      (the @"fileCache" . the @"entries" %=) $ M.insert (crTopic msg, crPartition msg) $ entry
        & the @"backupEntry" . the @"offsetMax"     %~ updateOffset (crOffset msg)
        & the @"backupEntry" . the @"timestampLast" .~ crTimestamp msg
      return $ entry ^. the @"outputStream"
    Nothing -> do
      liftIO $ D.createDirectoryIfMissing True dirPath
      let filePath = dirPath <> "/" <> printf "%05d" partitionId <> ".json"
      h <- liftIO $ openFile filePath WriteMode
      os <- liftIO $ handleToClosingOutputStream h
      zos <- liftIO $ IO.gzip IO.defaultCompressionLevel os
      let entry = Z.FileCacheEntry
            { Z.backupEntry = Z.BackupEntry
              { Z.fileName       = filePath
              , Z.offsetFirst    = crOffset     msg
              , Z.timestampFirst = crTimestamp  msg
              , Z.timestampLast  = crTimestamp  msg
              , Z.offsetMax      = crOffset     msg
              , Z.topicName      = crTopic      msg
              , Z.partitionId    = crPartition  msg
              }
            , Z.outputStream   = zos
            }
      the @"fileCache" . the @"entries" %= M.insert (crTopic msg, crPartition msg) entry
      return zos
  where PartitionId partitionId = crPartition msg
        dirPath                 = parentPath <> "/" <> unTopicName (crTopic msg)

writeDecodedMessage :: MonadApp o m => FilePath -> ConsumerRecord (Maybe BS.ByteString) J.Value -> m ()
writeDecodedMessage parentPath msg = do
  os <- outputStreamForMessage parentPath msg
  liftIO $ IO.write (Just (LBS.toStrict (LT.encodeUtf8 (JT.encodeToLazyText (crValue msg))))) os
