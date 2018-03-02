module App.AWS.DynamoDB
( TableName (..)
, toText
, module DDB
, dynamoPutItem
)
where

import Control.Lens        ((&), (.~))
import Data.HashMap.Strict (HashMap)
import Data.String         (IsString)
import Data.Text           (Text)
import Network.AWS         (MonadAWS, send)
import Network.AWS.Data

import Network.AWS.DynamoDB as DDB

newtype TableName = TableName { unTableName :: Text } deriving (Eq, Show, IsString, ToText, FromText)

dynamoPutItem :: MonadAWS m => TableName -> HashMap Text AttributeValue -> m PutItemResponse
dynamoPutItem (TableName table) item =
    send $ putItem table & piItem .~ item
