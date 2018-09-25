{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE StandaloneDeriving         #-}
{-# LANGUAGE TypeApplications           #-}

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
import Arbor.Network.StatsD         (MonadStats)
import Control.Lens
import Control.Monad.Base
import Control.Monad.Catch
import Control.Monad.IO.Class
import Control.Monad.Logger         (LoggingT, MonadLogger)
import Control.Monad.Reader
import Control.Monad.State.Strict   (MonadState (..), StateT, execStateT)
import Control.Monad.Trans.Resource
import Data.Generics.Product.Any
import Data.Generics.Product.Fields
import Data.Text                    (Text)

import qualified Arbor.Network.StatsD as S

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
  getStatsClient = reader (^. the @"statsClient")

runApplication ::
  ( Show o
  , HasField' "logLevel" o LogLevel)
  => AppEnv o
  -> Application o ()
  -> IO AppState
runApplication envApp f =
  runResourceT
    . runAWS envApp
    . runTimedLogT (envApp ^. the @"options" . the @"logLevel") (envApp ^. the @"logger" . the @"logger")
    . flip execStateT appStateEmpty
    $ do
        logInfo $ show (envApp ^. the @"options")
        runReaderT (unApp f) envApp
