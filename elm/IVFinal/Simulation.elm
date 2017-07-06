module IVFinal.Simulation exposing
  ( run
  )

import IVFinal.Simulation.Conversions as C 
import IVFinal.Simulation.Types exposing (Stage(..), HowFinished(..))

import IVFinal.Apparatus.Droplet as Droplet
import IVFinal.Apparatus.BagFluid as BagFluid
import IVFinal.Apparatus.ChamberFluid as ChamberFluid
import IVFinal.Apparatus.HoseFluid as HoseFluid
import IVFinal.Form.Types exposing (FinishedForm)
import IVFinal.Scenario exposing (Scenario)
import IVFinal.Types exposing (..)

import IVFinal.Generic.Measures as Measure

type alias CoreInfo =
  { minutes : Measure.Minutes           -- From hours and minutes
  , dripRate : Measure.DropsPerSecond   -- used for animation timings
  , flowRate : Measure.LitersPerMinute  -- Liters are more convenient than mils
  , containerVolume : Measure.Liters   
  , startingVolume : Measure.Liters
  , endingVolume : Measure.Liters
  }

run : Scenario -> FinishedForm -> ModelTransform
run scenario form =
  let
    core =
      extractCoreInfo scenario form
  in
    case Measure.isStrictlyNegative core.endingVolume of
      True -> overDrain core
      False -> partlyDrain core

{- This is what the student *should* achieve: a case where the
bag is still partly full at the end of the simulation.
-}
partlyDrain : CoreInfo -> ModelTransform
partlyDrain core = 
  let
    containerPercent =
      Measure.proportion core.endingVolume core.containerVolume
          
    -- animation
    beginTimeLapse =
      moveToWatchingStage core
      >> Droplet.entersTimeLapse core.dripRate
        (Continuation lowerBagLevel)
          
    lowerBagLevel =
      Droplet.flows core.dripRate
      >> BagFluid.lowers containerPercent core.minutes
         (Continuation endTimeLapse)
                  
    endTimeLapse = 
      Droplet.transitionsToDripping core.dripRate
        (Continuation finish)

    finish = 
        Droplet.falls core.dripRate
        >> moveToFinishedStage (FluidLeft core.endingVolume) core
  in
    beginTimeLapse

{- If too much time is specified, the bag, chamber, and hose will all empty
-}      
overDrain : CoreInfo -> ModelTransform
overDrain core = 
  let
    emptyTime =
      Measure.timeRequired core.flowRate core.startingVolume

    -- animation
    beginTimeLapse =
      moveToWatchingStage core
      >> Droplet.entersTimeLapse core.dripRate
        (Continuation emptyBag)

    emptyBag =
      Droplet.flows core.dripRate
      >> BagFluid.empties emptyTime
        (Continuation stopDripping)

    stopDripping = 
      Droplet.flowVanishes
        (Continuation emptyChamber)

    emptyChamber =
      ChamberFluid.empties
        (Continuation emptyHose)

    emptyHose =
      HoseFluid.empties
        (Continuation finish)

    finish =
      moveToFinishedStage (RanOutAfter emptyTime) core
  in
    beginTimeLapse



moveToWatchingStage : CoreInfo -> ModelTransform
moveToWatchingStage core model = 
  { model | stage = WatchingAnimation core.flowRate }

moveToFinishedStage : HowFinished -> CoreInfo -> ModelTransform
moveToFinishedStage howFinished core model =
  { model | stage = Finished core.flowRate howFinished }

extractCoreInfo : Scenario -> FinishedForm -> CoreInfo
extractCoreInfo scenario form =
  let 
    minutes = Measure.toMinutes form.hours form.minutes
    dripRate = form.dripRate
    flowRate = C.toFlowRate dripRate scenario
    containerVolume = scenario.containerVolume
    startingVolume = scenario.startingVolume
    endingVolume = C.toFinalLevel flowRate minutes scenario
  in
    { minutes = minutes
    , flowRate = flowRate
    , dripRate = dripRate
    , containerVolume = containerVolume
    , startingVolume = startingVolume
    , endingVolume = endingVolume
  }
      
