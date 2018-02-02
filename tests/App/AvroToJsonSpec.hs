{-# LANGUAGE DeriveGeneric      #-}
{-# LANGUAGE OverloadedStrings  #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TemplateHaskell    #-}

module App.AvroToJsonSpec
  ( spec
  ) where

import Control.Lens
import Data.Aeson.Lens
import Data.Avro
import Data.Avro.Deriving
import Data.Text          (Text)

import qualified Data.ByteString.Base64 as B64
import qualified Data.Text              as T
import qualified Data.Text.Encoding     as T

import App.AvroToJson

import Test.Hspec

import           HaskellWorks.Hspec.Hedgehog
import           Hedgehog
import qualified Hedgehog.Gen                as G
import qualified Hedgehog.Range              as R

{-# ANN module ("HLint: ignore Redundant do"  :: String) #-}

deriveAvro "tests/resources/simple.avsc"

eitherGen :: MonadGen m => m a -> m b -> m (Either a b)
eitherGen genA genB = G.choice [Left <$> genA, Right <$> genB]

smallStringGen :: MonadGen m => m Text
smallStringGen = G.text (R.linear 0 125) G.unicode

simpleRecordGen :: MonadGen m => m SimpleRecord
simpleRecordGen = SimpleRecord
  <$> G.bool
  <*> smallStringGen
  <*> G.int R.constantBounded
  <*> G.int64 R.constantBounded
  <*> G.double (R.linearFrac (-12345) 12345)
  <*> G.bytes (R.linear 0 125)
  <*> G.maybe smallStringGen
  <*> eitherGen (G.int R.constantBounded) smallStringGen
  <*> G.enum SuitSPADES SuitCLUBS
  <*> (InnerRecord <$> G.int R.constantBounded <*> smallStringGen)

spec :: Spec
spec = describe "App.AvroToJsonSpec" $ do
  it "should format json" $ require $ property $ do
    value <- forAll simpleRecordGen
    let res = avroToJson (toAvro value)
    res ^? key "boolean" . _Bool     === Just (simpleRecordBoolean value)
    res ^? key "string"  . _String   === Just (simpleRecordString value)
    res ^? key "int"     . _Integral === Just (simpleRecordInt value)
    res ^? key "long"    . _Integral === Just (simpleRecordLong value)
    res ^? key "double"  . _Double   === Just (simpleRecordDouble value)
    res ^? key "bytes"   . _String   === Just (T.decodeUtf8 $ B64.encode $ simpleRecordBytes value)
    res ^? key "maybe"   . _String   === simpleRecordMaybe value

    ((res ^? key "enum" . _String) <&> (mappend "Suit")) === Just (T.pack . show $ simpleRecordEnum value)

    case simpleRecordEither value of
      Left a  -> res ^? key "either" . _Integral === Just a
      Right b -> res ^? key "either" . _String === Just b

    res ^? key "record" . _Value . key "id" . _Integral === Just (innerRecordId $ simpleRecordRecord value)
    res ^? key "record" . _Value . key "value" . _String === Just (innerRecordValue $ simpleRecordRecord value)


