module Main where

import App.Commands
import Control.Monad
import Data.Semigroup      ((<>))
import Options.Applicative

main :: IO ()
main = join
  $ customExecParser (prefs $ showHelpOnEmpty <> showHelpOnError)
  $ info (commandsParser <**> helper)
  $ (  fullDesc
    <> progDesc "Dump avro data from kafka topic to S3"
    <> header "Kafka to S3"
    )
