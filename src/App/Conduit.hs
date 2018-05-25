{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables   #-}

module App.Conduit
  ( onRebalance
  ) where

import App.AppError
import Arbor.Logger
import Conduit
import Control.Monad.Catch       (MonadThrow)
import Control.Monad.Trans.Class (lift)
import Kafka.Conduit.Source

import qualified Data.Map as M
import qualified Data.Set as S

onRebalance :: (MonadLogger m, MonadThrow m, MonadIO m) => KafkaConsumer -> TopicName -> (S.Set PartitionId -> m a) -> ConduitM o o m ()
onRebalance consumer topicName handleRebalance = go S.empty
  where go lastAssignment = do
          ma <- await
          case ma of
            Just a -> do
              assignmentMap <- assignment consumer >>= throwAs KafkaErr
              let currentAssignment = S.fromList (concat (M.lookup topicName assignmentMap))
              if currentAssignment /= lastAssignment && S.empty /= currentAssignment
                then do
                  _ <- lift $ handleRebalance currentAssignment
                  yield a
                  go currentAssignment
                else do
                  yield a
                  go lastAssignment
            Nothing -> return ()
