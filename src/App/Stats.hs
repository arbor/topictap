{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TypeApplications      #-}

module App.Stats where

import App.Application
import App.AppState.Type
import App.Options.Types
import Arbor.Logger
import Arbor.Network.StatsD      (MonadStats)
import Arbor.Network.StatsD      (StatsClient)
import Control.Exception         (bracket)
import Control.Lens              (use, (.=), (<&>), (^.))
import Control.Monad.State
import Data.Generics.Product.Any
import Data.Maybe                (catMaybes)
import Data.Semigroup            ((<>))

import qualified Arbor.Network.StatsD      as S
import qualified Arbor.Network.StatsD.Type as Z

reportProgress :: (MonadLogger m, MonadStats m, MonadState AppState m) => m ()
reportProgress = do
  reads' <- use $ the @"msgReadCount"
  writes <- use $ the @"msgWriteCount"
  let drops = reads' - writes
  logInfo $ "Reads: " <> show reads' <> ", writes: " <> show writes
  S.sendMetric (S.addCounter (Z.MetricName "scorefilter.read.count" ) id reads')
  S.sendMetric (S.addCounter (Z.MetricName "scorefilter.write.count") id writes)
  S.sendMetric (S.addCounter (Z.MetricName "scorefilter.drop.count" ) id drops)
  the @"msgReadCount" .= 0
  the @"msgWriteCount" .= 0

withStatsClient :: AppName -> StatsConfig -> (StatsClient -> IO ()) -> IO ()
withStatsClient appName statsConf f = do
  globalTags <- mkStatsTags statsConf
  let statsOpts = Z.DogStatsSettings (statsConf ^. the @"host") (statsConf ^. the @"port")
  bracket (S.createStatsClient statsOpts (Z.MetricName appName) globalTags) S.closeStatsClient f

mkStatsTags :: StatsConfig -> IO [Z.Tag]
mkStatsTags statsConf = do
  deplId <- S.envTag "TASK_DEPLOY_ID" "deploy_id"
  let envTags = catMaybes [deplId]
  return $ envTags <> (statsConf ^. the @"tags" <&> toTag)
  where toTag (StatsTag (k, v)) = S.tag k v
