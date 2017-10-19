module App.AvroToJson where

import Data.Avro ()

import qualified Data.Aeson       as J
import qualified Data.Avro.Schema as S
import qualified Data.Avro.Types  as T

avroToJson :: T.Value S.Type -> J.Value
avroToJson T.Null          = J.Null
avroToJson (T.Boolean v)   = J.Bool v
avroToJson (T.String v)    = J.String v
avroToJson (T.Int v)       = J.Number . fromRational . toRational $ v
avroToJson (T.Long v)      = J.Number . fromRational . toRational $ v
avroToJson (T.Double v)    = J.Number . fromRational . toRational $ v

avroToJson (T.Record _ v)  = J.Object $ avroToJson <$> v
avroToJson (T.Array v)     = J.Array  $ avroToJson <$> v
avroToJson (T.Map v)       = J.Object $ avroToJson <$> v
avroToJson (T.Enum _ _ v)  = J.String v

avroToJson (T.Union _ _ v) = avroToJson v
avroToJson (T.Fixed _)     = error "Not Implemented Fixed"
avroToJson (T.Float _)     = error "Not Implemented Float"
avroToJson (T.Bytes _)     = error "Not Implemented Bytes"
