{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE StandaloneDeriving         #-}

module App.Application
  ( AppName
  , MonadApp
  , Application (..)
  , runApplication
  ) where

import Antiope.Core                 (AWS, MonadAWS, runAWS)
import App.AppEnv
import App.AppState.Type
import App.Orphans                  ()
import Arbor.Logger
import Control.Lens
import Control.Monad.Base
import Control.Monad.Catch
import Control.Monad.IO.Class
import Control.Monad.Logger         (LoggingT, MonadLogger)
import Control.Monad.Reader
import Control.Monad.State.Strict   (MonadState (..), StateT, execStateT)
import Control.Monad.Trans.Resource
import Data.Text                    (Text)
import Network.StatsD               as S

import qualified App.Has  as H ()
import qualified App.Lens as L

type AppName = Text

class ( MonadReader (AppEnv o) m
      , MonadState AppState m
      , MonadLogger m
      , MonadStats m
      , MonadAWS m
      , MonadResource m
      , MonadThrow m
      , MonadCatch m
      , MonadIO m) => MonadApp o m where

newtype Application o a = Application
  { unApp :: ReaderT (AppEnv o) (StateT AppState (LoggingT AWS)) a
  } deriving ( Functor
             , Applicative
             , Monad
             , MonadIO
             , MonadBase IO
             , MonadThrow
             , MonadCatch
             , MonadMask
             , MonadReader (AppEnv o)
             , MonadState AppState
             , MonadAWS
             , MonadLogger
             , MonadResource)

deriving instance MonadApp o (Application o)

instance MonadStats (Application o) where
  getStatsClient = reader _appEnvStatsClient

runApplication :: (Show o, L.HasLogLevel o LogLevel) => AppEnv o -> Application o () -> IO AppState
runApplication envApp f =
  runResourceT
    . runAWS envApp
    . runTimedLogT (envApp ^. L.options . L.logLevel) (envApp ^. L.log . L.logger)
    . flip execStateT appStateEmpty
    $ do
        logInfo $ show (envApp ^. L.options)
        runReaderT (unApp f) envApp
