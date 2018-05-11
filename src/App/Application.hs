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

import App.AppState.Type
import App.Orphans                  ()
import App.Type
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
import Network.AWS                  as AWS hiding (LogLevel)
import Network.StatsD               as S

import qualified App.Lens as L

type AppName = Text

class ( MonadReader AppEnv m
      , MonadState AppState m
      , MonadLogger m
      , MonadStats m
      , MonadAWS m
      , MonadResource m
      , MonadThrow m
      , MonadCatch m
      , MonadIO m) => MonadApp m where

newtype Application a = Application
  { unApp :: ReaderT AppEnv (StateT AppState (LoggingT AWS)) a
  } deriving ( Functor
             , Applicative
             , Monad
             , MonadIO
             , MonadBase IO
             , MonadThrow
             , MonadCatch
             , MonadMask
             , MonadReader AppEnv
             , MonadState AppState
             , MonadAWS
             , MonadLogger
             , MonadResource)

deriving instance MonadApp Application

instance MonadStats Application where
  getStatsClient = reader _appStatsClient

runApplication :: AppEnv -> Application () -> IO AppState
runApplication envApp f =
  runResourceT
    . runAWS envApp
    . runTimedLogT (envApp ^. L.appOptions . L.optLogLevel) (envApp ^. L.appLog . L.alLogger)
    . flip execStateT appStateEmpty
    $ do
        logInfo $ show (envApp ^. L.appOptions)
        runReaderT (unApp f) envApp
