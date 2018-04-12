module DevApp where

import App.AppState.Type
import App.AWS.Env
import App.Orphans                  ()
import Arbor.Logger
import Control.Monad.Base
import Control.Monad.Catch
import Control.Monad.IO.Class
import Control.Monad.Logger         (LoggingT, MonadLogger)
import Control.Monad.State.Strict   (MonadState (..), StateT, execStateT)
import Control.Monad.Trans.Resource
import Network.AWS                  as AWS hiding (LogLevel)
import Network.StatsD               as S

newtype DevApp a = DevApp
  { unDevApp :: StateT AppState (LoggingT AWS) a
  } deriving ( Functor, Applicative, Monad, MonadIO, MonadBase IO, MonadThrow, MonadCatch
             , MonadState AppState, MonadMask, MonadAWS, MonadLogger, MonadResource)

instance MonadStats DevApp where
  getStatsClient = pure Dummy

runDevApp' :: HasEnv e => e -> TimedFastLogger -> DevApp a -> IO AppState
runDevApp' e logger f =
  runResourceT
  . runAWS e
  . runTimedLogT LevelInfo logger
  . flip execStateT appStateEmpty
  $ unDevApp f


runDevApp :: DevApp a -> IO AppState
runDevApp f =
  withStdOutTimedFastLogger $ \logger -> do
    env <- mkEnv Oregon LevelInfo logger
    runDevApp' env logger f
