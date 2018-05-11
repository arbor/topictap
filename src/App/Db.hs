{-# LANGUAGE ScopedTypeVariables #-}

module App.Db where

import App.Type
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Logger   (runStderrLoggingT)
import Data.Function
import Data.Pool
import Data.Time.Clock        (getCurrentTime)
import Database.Persist.MySQL

import qualified App.Db.Type        as DT
import qualified Data.Text          as T
import qualified Data.Text.Encoding as T
import qualified System.IO          as IO

runDb :: DbConfig -> IO ()
runDb dbConfig = do
  let connectionInfo = mkMySQLConnectInfo
        (dbConfig & _dbConfigHost & T.unpack)
        (dbConfig & _dbConfigUser & T.encodeUtf8)
        (dbConfig & _dbConfigPassword & _passwordValue & T.encodeUtf8)
        (dbConfig & _dbConfigDatabase & T.encodeUtf8)

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
