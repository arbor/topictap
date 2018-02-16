{-# LANGUAGE TupleSections #-}
module  App.Conduit.Time
where

import App.Types             (Seconds (..))
import Conduit
import Data.Time.Clock       (UTCTime)
import Data.Time.Clock.POSIX (getCurrentTime, utcTimeToPOSIXSeconds)

-- | Annotates every message with a timestamp.
timedC :: MonadIO m
       => Conduit a m (UTCTime, a)
timedC = awaitForever $ \a ->
  yieldM ((,a) <$> liftIO getCurrentTime)

-- | Samples messages, one per a specified interval
-- and annotates sampled messages with timestamps
sampleC :: MonadIO m
        => Seconds
        -> Conduit a m (UTCTime, a)
sampleC (Seconds sec) = go 0
  where
    go t = do
      mmsg <- await
      case mmsg of
        Nothing -> pure ()
        Just msg -> do
          time <- liftIO getCurrentTime
          case round (utcTimeToPOSIXSeconds time) of
            ct | t == 0 -> go (ct + sec)                      -- initial, returse to the next interval
            ct | ct > t -> yield (time, msg) >> go (ct + sec) -- yield and returse to the next interval
            _  -> go t                                        -- still sampling, recurse


