{-# Language TypeFamilies, FlexibleContexts #-}
module Csound.Typed.Types.Evt where

import Data.Monoid

import Data.Boolean

import qualified Csound.Dynamic as C

import Csound.Typed.Types.Prim
import Csound.Typed.Types.Tuple
import Csound.Typed.Types.SERef
import Csound.Typed.Types.GlobalState

data Evt a = Evt { runEvt :: Bam a -> SE () }

type Bam a = a -> SE ()

instance Functor Evt where
    fmap f a = Evt $ \bam -> runEvt a (bam . f) 

instance Monoid (Evt a) where
    mempty = Evt $ const $ return ()
    mappend a b = Evt $ \bam -> runEvt a bam >> runEvt b bam
    
-- | Converts booleans to events.
boolToEvt :: BoolSig -> Evt ()
boolToEvt b = Evt $ \bam -> when b $ bam ()

-- | Triggers an event when signal equals to 1.
sigToEvt :: Sig -> Evt ()
sigToEvt = boolToEvt . ( ==* 1) . kr

-- | Filters events with predicate.
filterE :: (a -> BoolD) -> Evt a -> Evt a
filterE pr evt = Evt $ \bam -> runEvt evt $ \a ->
    when (boolSig $ pr a) $ bam a

-- | Accumulator for events with side effects.
accumSE :: (Tuple s) => s -> (a -> s -> SE (b, s)) -> Evt a -> Evt b
accumSE s0 update evt = Evt $ \bam -> do
    (readSt, writeSt) <- sensorsSE s0
    runEvt evt $ \a -> do
        s1 <- readSt
        (b, s2) <- update a s1
        bam b
        writeSt s2

-- | Accumulator for events.
accumE :: (Tuple s) => s -> (a -> s -> (b, s)) -> Evt a -> Evt b
accumE s0 update = accumSE s0 (\a s -> return $ update a s)

-- | Accumulator for events with side effects and filtering. Event triggers
-- only if the first element in the tripplet is true.
filterAccumSE :: (Tuple s) => s -> (a -> s -> SE (BoolD, b, s)) -> Evt a -> Evt b
filterAccumSE s0 update evt = Evt $ \bam -> do
    (readSt, writeSt) <- sensorsSE s0
    runEvt evt $ \a -> do
        s1 <- readSt
        (isOn, b, s2) <- update a s1
        when (boolSig isOn) $ bam b
        writeSt s2

-- | Accumulator with filtering. It can skip the events from the event stream.
-- If the third element of the triple equals to 1 then we should include the
-- event in the resulting stream. If the element equals to 0 we skip the event.
filterAccumE :: (Tuple s) => s -> (a -> s -> (BoolD, b, s)) -> Evt a -> Evt b
filterAccumE s0 update = filterAccumSE s0 $ \a s -> return $ update a s

-- | Get values of some signal at the given events.
snapshot :: (Tuple a, Tuple (Snap a)) => (Snap a -> b -> c) -> a -> Evt b -> Evt c
snapshot f asig evt = Evt $ \bam -> runEvt evt $ \a -> 
    bam (f (readSnap asig) a)

readSnap :: (Tuple (Snap a), Tuple a) => a -> Snap a
readSnap = toTuple . fromTuple

-- | Constructs an event stream that contains values from the
-- given signal. Events happens only when the signal changes.
snaps :: Sig -> Evt D
snaps asig = snapshot const asig trigger
    where 
        trigger = sigToEvt $ fromGE $ fmap changed $ toGE asig
        changed x = C.opcs "changed" [(C.Kr, [C.Kr])] [x]

-------------------------------------------------------------------
-- snap 

-- | A snapshot of the signal. It converts a type of the signal to the 
-- type of the value in the given moment. Instances:
--
--
-- > type instance Snap D   = D
-- > type instance Snap Str = Str
-- > type instance Snap Tab = Tab
-- >
-- > type instance Snap Sig = D
-- > 
-- > type instance Snap (a, b) = (Snap a, Snap b)
-- > type instance Snap (a, b, c) = (Snap a, Snap b, Snap c)
-- > type instance Snap (a, b, c, d) = (Snap a, Snap b, Snap c, Snap d)
-- > type instance Snap (a, b, c, d, e) = (Snap a, Snap b, Snap c, Snap d, Snap e)
-- > type instance Snap (a, b, c, d, e, f) = (Snap a, Snap b, Snap c, Snap d, Snap e, Snap f)
type family Snap a :: *

type instance Snap D   = D
type instance Snap Str = Str
type instance Snap Tab = Tab

type instance Snap Sig = D

type instance Snap (a, b) = (Snap a, Snap b)
type instance Snap (a, b, c) = (Snap a, Snap b, Snap c)
type instance Snap (a, b, c, d) = (Snap a, Snap b, Snap c, Snap d)
type instance Snap (a, b, c, d, e) = (Snap a, Snap b, Snap c, Snap d, Snap e)
type instance Snap (a, b, c, d, e, f) = (Snap a, Snap b, Snap c, Snap d, Snap e, Snap f)

-- | Converts an event to boolean signal. It forgets
-- everything about the event values. Signal equals to one when 
-- an event happens and zero otherwise.
evtToBool :: Evt a -> SE BoolSig
evtToBool evt = do
    var <- newSERef (double 0)
    writeSERef var (double 0)
    runEvt evt $ const $ writeSERef var (double 1)
    asig <- readSERef var
    return $ boolSig $ asig ==* (double 1)

-- | Converts events to signals.
stepper :: Tuple a => a -> Evt a -> SE a
stepper v0 evt = do
    (readSt, writeSt) <- sensorsSE v0
    runEvt evt $ \a -> writeSt a
    readSt 

