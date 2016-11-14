{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE FlexibleContexts #-}

module CounterFSM (runCounterTests) where

import Test.Tasty
import Test.Tasty.HUnit

import CommonDefs

import Control.Concurrent
import Control.Concurrent.MVar
import Control.Monad
import Data.Aeson
import Data.Text
import Data.Typeable
import GHC.Generics

import FSM
import FSMApi
import FSMTable
import PostgresJSONStore as PGJSON
import MemoryStore       as MemStore
import Data.Time.Clock
import Data.UUID
import Data.UUID.V4
import Debug.Trace

data CounterState = Desu
    deriving (Eq,Show,Typeable)
instance ToJSON CounterState where
    toJSON _ = "Desu"
instance FromJSON CounterState where
    parseJSON "Desu" = return Desu

data CounterEvent = DesuEvent
    deriving (Eq,Show,Typeable)
instance ToJSON CounterEvent where
    toJSON _ = "DesuEvent"
instance FromJSON CounterEvent where
    parseJSON "DesuEvent" = return DesuEvent


-- NOP
data CounterAction = DesuDummyAction
    deriving (Eq,Show,Typeable,Generic)
instance ToJSON CounterAction where
    toJSON _ = "DesuDummyAction"
instance FromJSON CounterAction where
    parseJSON "DesuDummyAction" = return DesuDummyAction


counterTransition :: (CounterState, CounterEvent) -> (CounterState,[CounterAction])
counterTransition =
    \case (Desu, DesuEvent) -> (Desu,[DesuDummyAction])

counterEffects :: MVar () -> Msg CounterAction -> IO Bool
counterEffects mvar _ =
    putMVar mvar () >> return True


runCounterTests c = testGroup "CounterFSM" [
    testCase "CounterPG" (runTest $ PGJSON.mkStore c),
    testCase "CounterMem" (runTest (MemStore.mkStore :: Text -> IO (MemoryStore CounterState CounterEvent CounterAction)))
    ]

runTest c = do
    sync   <- newEmptyMVar

    st     <- c "CounterTest"

    let t   = FSMTable counterTransition (counterEffects sync)
    let fsm = FSMHandle "CounterFSM" t st st 900 3

    i      <- nextRandom
    post fsm i Desu

    replicateM_ 10 (do
        m <- mkMsgs [DesuEvent]
        patch fsm i m
        takeMVar sync)

    s <- get fsm i

    assert $ s == Just Desu
