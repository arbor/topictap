{-# LANGUAGE ScopedTypeVariables #-}

module App.Db where

import Control.Monad.IO.Class (liftIO)
import Control.Monad.Logger   (runStderrLoggingT)
import Data.Pool
import Data.Time.Clock        (getCurrentTime)
import Database.Persist.MySQL

import qualified App.Db.Type as DT
import qualified System.IO   as IO

runDb :: IO ()
runDb = do
  let connectionInfo = mkMySQLConnectInfo "infrastructure.cravo7sxkiuc.us-west-2.rds.amazonaws.com" "admin" "9xi&9fqXeiY4TNX,iA6y" "topictap"

  _ <- runStderrLoggingT $ withMySQLPool connectionInfo 10 $ \(pool :: Pool SqlBackend) -> liftIO $ do
    currentTime <- getCurrentTime
    flip runSqlPersistMPool pool $ do
      printMigration DT.migrateAll
      runMigration DT.migrateAll
      _ <- insert DT.TopicPartitionOffsets
        { DT.topicPartitionOffsetsTopicPartition  = 1
        , DT.topicPartitionOffsetsTopic           = "moo"
        , DT.topicPartitionOffsetsPartitionId     = 2
        , DT.topicPartitionOffsetsTimestamp       = currentTime
        , DT.topicPartitionOffsetsOffsetFirst     = 3
        , DT.topicPartitionOffsetsTimestampFirst  = currentTime
        , DT.topicPartitionOffsetsOffsetMax       = 4
        , DT.topicPartitionOffsetsTimestampLast   = currentTime
        , DT.topicPartitionOffsetsLocationUri     = "url"
        }

      rows <- selectList [DT.TopicPartitionOffsetsPartitionId >. 0, DT.TopicPartitionOffsetsPartitionId <=. 30] []

      liftIO $ IO.print rows

      return ()


  return ()
