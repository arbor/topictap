module  App.Conduit.Time
where

import App.Types             (Seconds (..))
import Conduit
import Data.Time.Clock       (UTCTime)
import Data.Time.Clock.POSIX (getCurrentTime, utcTimeToPOSIXSeconds)

-- | Maps an effect every N seconds
-- and returns the result of the effect downstream.
-- Only one message per a given interval is taken into account,
-- other messages are filtered out and are not propagated downstream.
intervalMapC :: MonadIO m
             => Seconds
             -> (UTCTime -> a -> m b)
             -> Conduit a m b
intervalMapC (Seconds sec) handle = go 0
  where
    go t = do
      mmsg <- await
      case mmsg of
        Nothing -> pure ()
        Just msg -> do
          time <- liftIO getCurrentTime
          let ct = round (utcTimeToPOSIXSeconds time)
          if ct > t
            then yieldM (handle time msg) >> go (ct + sec)
            else go t
