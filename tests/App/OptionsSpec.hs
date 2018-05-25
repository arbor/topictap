{-# LANGUAGE OverloadedStrings #-}

module App.OptionsSpec
  ( spec
  ) where

import App.Options.Types
import HaskellWorks.Hspec.Hedgehog
import Hedgehog
import Test.Hspec

{-# ANN module ("HLint: ignore Redundant do"  :: String) #-}

spec :: Spec
spec = describe "App.OptionsSpec" $ do
  it "should parse tags" $ requireTest $ do
    string2Tags "club_name:indica,deploy_id:manual" === [StatsTag ("club_name", "indica"), StatsTag ("deploy_id", "manual")]
