module App.AWS.Env
( mkEnv
)
where

import           Arbor.Logger
import           Control.Lens
import           Control.Monad
import           Control.Monad.Trans.AWS       hiding (LogLevel)
import qualified Data.ByteString               as BS
import           Data.ByteString.Builder
import qualified Data.ByteString.Char8         as C8
import qualified Data.ByteString.Lazy          as L
import qualified Data.ByteString.Lazy.Internal as LBS

import qualified Network.AWS         as AWS
import           Network.HTTP.Client (HttpException (..), HttpExceptionContent (..))

mkEnv :: Region -> LogLevel -> TimedFastLogger -> IO AWS.Env
mkEnv region logLevel logger = do
  lgr <- newAwsLogger logLevel logger
  newEnv Discover
    <&> envLogger .~ lgr
    <&> envRegion .~ region
    <&> envRetryCheck .~ retryPolicy 5

newAwsLogger :: Monad m => LogLevel -> TimedFastLogger -> m AWS.Logger
newAwsLogger logLevel logger = return $ \y b ->
  when (logLevelToAWS logLevel >= y)
    $ applyLogMessage logger logLevel (toLazyByteString b)

applyLogMessage :: TimedFastLogger -> LogLevel -> LBS.ByteString -> IO ()
applyLogMessage logger level lbs =
  if BS.isInfixOf (C8.pack "404 Not Found") (L.toStrict lbs)
  then return ()
  else pushLogMessage logger level lbs

retryPolicy :: Int -> Int -> HttpException -> Bool
retryPolicy maxNum attempt ex = (attempt <= maxNum) && shouldRetry ex


logLevelToAWS :: LogLevel -> AWS.LogLevel
logLevelToAWS l = case l of
  LevelError -> AWS.Error
  LevelWarn  -> AWS.Error
  LevelInfo  -> AWS.Error
  LevelDebug -> AWS.Info
  _          -> AWS.Trace

shouldRetry :: HttpException -> Bool
shouldRetry ex = case ex of
  HttpExceptionRequest _ ctx -> case ctx of
    ResponseTimeout          -> True
    ConnectionTimeout        -> True
    ConnectionFailure _      -> True
    InvalidChunkHeaders      -> True
    ConnectionClosed         -> True
    InternalException _      -> True
    NoResponseDataReceived   -> True
    ResponseBodyTooShort _ _ -> True
    _                        -> False
  _ -> False
