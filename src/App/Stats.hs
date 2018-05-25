{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables   #-}

module App.Stats where

import App.Application
import App.AppState.Type
import App.Options.Types
import Arbor.Logger
import Control.Exception   (bracket)
import Control.Lens        (use, (.=), (<&>), (^.))
import Control.Monad.State (MonadState)
import Data.Maybe          (catMaybes)
import Data.Semigroup      ((<>))
import Network.StatsD      as S

import qualified App.Lens as L

reportProgress :: (MonadLogger m, MonadStats m, MonadState AppState m) => m ()
reportProgress = do
  reads' <- use L.msgReadCount
  writes <- use L.msgWriteCount
  let drops = reads' - writes
  logInfo $ "Reads: " <> show reads' <> ", writes: " <> show writes
  sendMetric (addCounter (MetricName "scorefilter.read.count" ) id reads')
  sendMetric (addCounter (MetricName "scorefilter.write.count") id writes)
  sendMetric (addCounter (MetricName "scorefilter.drop.count") id drops)
  L.msgReadCount .= 0
  L.msgWriteCount .= 0

withStatsClient :: AppName -> StatsConfig -> (StatsClient -> IO ()) -> IO ()
withStatsClient appName statsConf f = do
  globalTags <- mkStatsTags statsConf
  let statsOpts = DogStatsSettings (statsConf ^. L.host) (statsConf ^. L.port)
  bracket (createStatsClient statsOpts (MetricName appName) globalTags) closeStatsClient f

mkStatsTags :: StatsConfig -> IO [Tag]
mkStatsTags statsConf = do
  deplId <- envTag "TASK_DEPLOY_ID" "deploy_id"
  let envTags = catMaybes [deplId]
  return $ envTags <> (statsConf ^. L.tags <&> toTag)
  where toTag (StatsTag (k, v)) = S.tag k v
