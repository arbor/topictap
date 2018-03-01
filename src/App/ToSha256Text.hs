module App.ToSha256Text where

import qualified Crypto.Hash.SHA256     as H
import qualified Data.ByteString        as BS
import qualified Data.ByteString.Base16 as B16
import qualified Data.ByteString.Lazy   as LBS
import qualified Data.Text              as T
import qualified Data.Text.Encoding     as T

class ToSha256Text a where
  toSha256Text :: a -> T.Text

instance ToSha256Text BS.ByteString where
  toSha256Text = T.decodeUtf8 . B16.encode . H.hash

instance ToSha256Text T.Text where
  toSha256Text = toSha256Text . T.encodeUtf8

instance ToSha256Text LBS.ByteString where
  toSha256Text = T.decodeUtf8 . B16.encode . H.hashlazy
