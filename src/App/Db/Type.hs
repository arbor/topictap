{-# LANGUAGE QuasiQuotes     #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies    #-}

module App.Db.Type where

import Data.Text           (Text)
import Data.Time.Clock     (UTCTime)
import Database.Persist.TH

share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
TopicPartitionOffsets
    topicPartition  Int
    topic           Text
    partitionId     Int
    timestamp       UTCTime
    offsetFirst     Int
    timestampFirst  UTCTime
    offsetMax       Int
    timestampLast   UTCTime
    locationUri     Text
    deriving Show
|]

deriving instance Eq TopicPartitionOffsets
