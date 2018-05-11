{-# OPTIONS_GHC -fno-warn-orphans #-}
module App.Orphans where

import Antiope.Core               (MonadAWS, liftAWS)
import Control.Monad.Logger       (LoggingT)
import Control.Monad.State.Strict (lift)
import Data.Conduit

instance MonadAWS m => MonadAWS (LoggingT m) where liftAWS = lift . liftAWS
instance MonadAWS m => MonadAWS (ConduitM i o m) where liftAWS = lift . liftAWS
