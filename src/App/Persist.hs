{-# LANGUAGE MultiParamTypeClasses #-}
module App.Persist
where

import App.AppState
import App.AWS.S3
import Control.Lens
import Control.Monad.IO.Class
import Control.Monad.State
import Network.AWS

uploadAllFiles :: (MonadState s m, HasFileCache s, MonadAWS m)
            => m ()
uploadAllFiles = do
  cache <- use fileCache
  fileCache .= fileCacheEmpty

uploadFiles :: MonadAWS m
            => [FileCacheEntry]
            -> m ()
uploadFiles fs =
  liftIO $ print fs
