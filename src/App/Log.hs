{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TypeApplications      #-}

module App.Log where

import App.AppEnv
import Arbor.Logger
import Control.Lens              ((^.))
import Control.Monad             (when)
import Data.Generics.Product.Any

import qualified Antiope.Env          as AWS
import qualified Arbor.Logger         as Log
import qualified Data.ByteString.Lazy as LBS

logAWS :: AppLogger -> AWS.LogLevel -> LBS.ByteString -> IO ()
logAWS lgr awsLvl msg = do
  let lvl = lgr ^. the @"logLevel"
  when (logLevelToAWS lvl >= awsLvl)
    $ pushLogMessage (lgr ^. the @"logger") lvl msg

logLevelToAWS :: Log.LogLevel -> AWS.LogLevel
logLevelToAWS l = case l of
  Log.LevelError -> AWS.Error
  Log.LevelWarn  -> AWS.Error
  Log.LevelInfo  -> AWS.Error
  Log.LevelDebug -> AWS.Info
  _              -> AWS.Trace
