{-# LANGUAGE DeriveGeneric #-}

module App.CancellationToken where

import Data.IORef
import GHC.Generics

data CancellationStatus = Cancelled | Running deriving (Show, Eq, Generic)

newtype CancellationToken = CancellationToken (IORef CancellationStatus)

newCancellationToken :: IO CancellationToken
newCancellationToken = CancellationToken <$> newIORef Running

status :: CancellationToken -> IO CancellationStatus
status (CancellationToken ref) = readIORef ref
{-# INLINE status #-}

cancel :: CancellationToken -> IO ()
cancel (CancellationToken ref) = atomicWriteIORef ref Cancelled
{-# INLINE cancel #-}

reset :: CancellationToken -> IO ()
reset (CancellationToken ref) = atomicWriteIORef ref Running
{-# INLINE reset #-}
