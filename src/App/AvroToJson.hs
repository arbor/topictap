module App.AvroToJson where

import Data.Avro ()

import qualified Data.Aeson             as J
import qualified Data.Avro.Schema       as S
import qualified Data.Avro.Types        as A
import qualified Data.ByteString.Base64 as B64
import qualified Data.Text.Encoding     as T

avroToJson :: A.Value S.Type -> J.Value
avroToJson A.Null          = J.Null
avroToJson (A.Boolean v)   = J.Bool v
avroToJson (A.String v)    = J.String v
avroToJson (A.Int v)       = J.Number . fromRational . toRational $ v
avroToJson (A.Long v)      = J.Number . fromRational . toRational $ v
avroToJson (A.Double v)    = J.Number . fromRational . toRational $ v
avroToJson (A.Float v)     = J.Number . fromRational . toRational $ v

avroToJson (A.Record _ v)  = J.Object $ avroToJson <$> v
avroToJson (A.Array v)     = J.Array  $ avroToJson <$> v
avroToJson (A.Map v)       = J.Object $ avroToJson <$> v
avroToJson (A.Enum _ _ v)  = J.String v

avroToJson (A.Union _ _ v) = avroToJson v

avroToJson (A.Fixed v)     = J.String $ T.decodeUtf8 (B64.encode v)
avroToJson (A.Bytes v)     = J.String $ T.decodeUtf8 (B64.encode v)
