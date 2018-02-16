module App.Types
where

newtype Seconds = Seconds { unSeconds :: Int } deriving (Show, Eq)
