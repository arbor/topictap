{-# LANGUAGE ScopedTypeVariables #-}

module App.AWS.S3
( putFile
, copySingle
, BucketName(..)
, ObjectKey(..)
, S3Location(..)
, ETag(..)
, toS3Uri
) where

import Control.Lens
import Control.Monad
import Control.Monad.Trans.AWS hiding (send)
import Data.Monoid             ((<>))
import Data.Text               (Text)
import Network.AWS             (MonadAWS, send)
import Network.AWS.Data
import Network.AWS.S3

chunkSize :: ChunkSize
chunkSize = ChunkSize (1024*1024)

data S3Location = S3Location
  { s3Bucket    :: BucketName
  , s3ObjectKey :: ObjectKey
  } deriving (Show, Eq)

instance ToText S3Location where
  toText loc = toS3Uri (s3Bucket loc) (s3ObjectKey loc)

toS3Uri :: BucketName -> ObjectKey -> Text
toS3Uri (BucketName b) (ObjectKey k) =
  "s3://" <> b <> "/" <> k

-- | Puts file into a specified S3 bucket
putFile :: MonadAWS m
        => BucketName       -- ^ Target bucket
        -> ObjectKey        -- ^ File name on S3
        -> FilePath         -- ^ Source file path
        -> m (Maybe ETag)   -- ^ Etag when the operation is successful
putFile b k f = do
    req <- chunkedFile chunkSize f
    view porsETag <$> send (putObject b k req)

-- | Copies a single object within S3
copySingle :: MonadAWS m
           => BucketName          -- ^ Source bucket name
           -> ObjectKey           -- ^ Source key
           -> BucketName          -- ^ Target bucket name
           -> ObjectKey           -- ^ Target key
           -> m ()
copySingle sb sk tb tk =
  void . send $ copyObject tb (toText sb <> "/" <> toText sk) tk
     & coMetadataDirective .~ Just MDCopy
