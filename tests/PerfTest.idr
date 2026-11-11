||| M1 performance measurement: pure turn resolution and Canvas drawing.
|||
||| The numbers are printed, not asserted: the machine used for development
||| is recorded in doc/m1-measurements.md.  A separate regression threshold
||| can be added when the project has a stable benchmark host.
module PerfTest

import Data.List
import LambdaRogue.App.Canvas
import LambdaRogue.App.Model
import LambdaRogue.App.View
import LambdaRogue.Core.Bitset
import LambdaRogue.Core.Dungeon
import LambdaRogue.Core.Game
import LambdaRogue.Core.Replay
import LambdaRogue.Core.Rng
import LambdaRogue.Core.Types
import LambdaRogue.UI.Animation
import LambdaRogue.UI.Theme
import System
import System.Posix.Errno
import System.Posix.Time
import TermUI.Canvas
import TermUI.Frame
import TermUI.Len

timeNs : IO Int64
timeNs = do
  Right t <- clock_gettime CLOCK_MONOTONIC
    | Left _ => pure 0
  pure (t.tvSec * 1000000000 + t.tvNsec)

||| Every cell of the 80x22 map.  `count` must be 1760.
fullMapBits : Bitset
fullMapBits =
  foldl (\bs, xy => setBit (fst xy) (snd xy) bs) empty
    [(x, y) | x <- range 0 79, y <- range 0 21]

||| The worst case for `drawMap`: every cell is visible and explored.
fullGame : Game
fullGame =
  let g0 = sampleGame
      lvl : Level
      lvl = { explored := fullMapBits } (currentLevel g0)
      g1 : Game
      g1 = updateCurrentLevel (const lvl) g0
  in { visible := fullMapBits } g1

||| A generated level with a player who cannot be killed by the shallow
||| monsters, so the benchmark keeps exercising AI and combat for the whole
||| run instead of turning into no-ops after a death.
survivorGame : Game
survivorGame =
  let g = newGame sampleSeed
      p : Player
      p = { hp := 1000, maxHp := 1000, armor := 100 } g.player
  in { player := p } g

generateN : Nat -> Depth -> Rng -> Rng
generateN Z _ g = g
generateN (S k) d g =
  let gl = generateLevel d 1 1 g
  in generateN k d gl.rng

||| The 10,000-turn step benchmark must not turn into no-ops when the M3
||| hunger rules starve the fixture, so give it enough nutrition to stay
||| active for the whole run.
longLivedSampleGame : Game
longLivedSampleGame =
  let p : Player
      p = { hunger := 20000 } sampleGame.player
  in { player := p } sampleGame

runSteps : Nat -> Game -> Game
runSteps Z g = g
runSteps (S k) g = runSteps k (step Wait g).game

drawN : Nat -> Canvas -> Game -> IO ()
drawN Z _ _ = pure ()
drawN (S k) c g = drawMap c g >> drawN k c g

drawStepN : Nat -> Canvas -> Game -> IO ()
drawStepN Z _ _ = pure ()
drawStepN (S k) c g = do
  let g' = (step Wait g).game
  drawMap c g'
  drawStepN k c g'

||| Render the whole Elm view, including the sidebar, log and status line.
renderViewN : Nat -> Len -> Len -> Model -> IO ()
renderViewN Z _ _ _ = pure ()
renderViewN (S k) w h m = do
  frame <- render (view m) w h
  ls <- frameLines frame
  if length ls == 0
     then pure ()
     else renderViewN k w h m

inventoryIds : List ItemId
inventoryIds = map (\n => 100 + n) [0 .. 22]

inventoryItems : List Item
inventoryItems =
  map (\iid => MkItem iid (Food FoodRation) InPack 1 0 False 0 False)
      inventoryIds

inventoryGame : Game
inventoryGame =
  let p : Player
      p = { inventory := inventoryIds } sampleGame.player
  in { player := p, items := inventoryItems } sampleGame

report : String -> Nat -> Int64 -> IO ()
report label count totalNs =
  putStrLn (label ++ ": " ++ show count ++ " iterations, "
            ++ show (totalNs `div` 1000000) ++ " ms total, "
            ++ show (totalNs `div` cast count) ++ " ns/op")

public export
run : IO ()
run = do
  c <- newCanvas (the Len 80) (the Len 22)
  drawMap c sampleGame

  putStrLn ("full-map cells: " ++ show (count fullMapBits))
  if count fullMapBits /= 1760
     then do
       putStrLn "FAIL fullMapBits does not cover exactly 1760 cells"
       exitFailure
     else pure ()

  t0 <- timeNs
  drawN 1000 c sampleGame
  t1 <- timeNs
  report "render (initial FOV)" 1000 (t1 - t0)

  tFull0 <- timeNs
  drawN 500 c fullGame
  tFull1 <- timeNs
  report "render (full map)" 500 (tFull1 - tFull0)

  let mNormal = MkModel c sampleGame 80 24 False Nothing Nothing Nothing False False 0 AllMessages (emptyReplay sampleGame.seed) [] False False Nothing ClassicCga Nothing [] True Nothing defaultKeymap English
      mInventory = MkModel c inventoryGame 80 24 True Nothing Nothing Nothing False False 0 AllMessages (emptyReplay sampleGame.seed) [] False False Nothing ClassicCga Nothing [] True Nothing defaultKeymap English
      mWide = MkModel c sampleGame 120 40 False Nothing Nothing Nothing False False 0 AllMessages (emptyReplay sampleGame.seed) [] False False Nothing ClassicCga Nothing [] True Nothing defaultKeymap English
      mWideDark = { theme := ModernDark } mWide
      mWideInventory = MkModel c inventoryGame 120 40 True Nothing Nothing Nothing False False 0 AllMessages (emptyReplay sampleGame.seed) [] False False Nothing ClassicCga Nothing [] True Nothing defaultKeymap English
      mHelp = MkModel c sampleGame 80 24 False Nothing Nothing Nothing True False 0 AllMessages (emptyReplay sampleGame.seed) [] False False Nothing ClassicCga Nothing [] True Nothing defaultKeymap English
      mPalette = MkModel c sampleGame 80 24 False Nothing Nothing Nothing False True 2 AllMessages (emptyReplay sampleGame.seed) [] False False Nothing ClassicCga Nothing [] True Nothing defaultKeymap English
      mScore = MkModel c sampleGame 80 24 False Nothing Nothing Nothing False False 0 AllMessages (emptyReplay sampleGame.seed) [] True False (Just True) ClassicCga Nothing [] True Nothing defaultKeymap English
      mShare = MkModel c sampleGame 80 24 False Nothing Nothing Nothing False False 0 AllMessages (emptyReplay sampleGame.seed) [] False True Nothing ClassicCga Nothing [] True Nothing defaultKeymap English

  tView0 <- timeNs
  renderViewN 500 80 24 mNormal
  tView1 <- timeNs
  report "render view (80x24)" 500 (tView1 - tView0)

  tInv0 <- timeNs
  renderViewN 500 80 24 mInventory
  tInv1 <- timeNs
  report "render view (80x24, inventory)" 500 (tInv1 - tInv0)

  tWide0 <- timeNs
  renderViewN 500 120 40 mWide
  tWide1 <- timeNs
  report "render view (120x40)" 500 (tWide1 - tWide0)

  tDark0 <- timeNs
  renderViewN 500 120 40 mWideDark
  tDark1 <- timeNs
  report "render view (120x40, modern dark)" 500 (tDark1 - tDark0)

  tWideInv0 <- timeNs
  renderViewN 200 120 40 mWideInventory
  tWideInv1 <- timeNs
  report "render view (120x40, inventory)" 200 (tWideInv1 - tWideInv0)

  tHelp0 <- timeNs
  renderViewN 200 80 24 mHelp
  tHelp1 <- timeNs
  report "render view (80x24, help)" 200 (tHelp1 - tHelp0)

  tPalette0 <- timeNs
  renderViewN 200 80 24 mPalette
  tPalette1 <- timeNs
  report "render view (80x24, palette)" 200 (tPalette1 - tPalette0)

  tScore0 <- timeNs
  renderViewN 200 80 24 mScore
  tScore1 <- timeNs
  report "render view (80x24, scores)" 200 (tScore1 - tScore0)

  tShare0 <- timeNs
  renderViewN 200 80 24 mShare
  tShare1 <- timeNs
  report "render view (80x24, share seed)" 200 (tShare1 - tShare0)

  t2 <- timeNs
  let final = runSteps 10000 longLivedSampleGame
  t3 <- timeNs
  report "step" 10000 (t3 - t2)
  putStrLn ("final turn: " ++ show final.turn)

  t4 <- timeNs
  drawStepN 1000 c sampleGame
  t5 <- timeNs
  report "step+render (initial FOV)" 1000 (t5 - t4)

  tFull2 <- timeNs
  drawStepN 500 c fullGame
  tFull3 <- timeNs
  report "step+render (full map)" 500 (tFull3 - tFull2)

  let generatedGame = newGame sampleSeed
  tGen0 <- timeNs
  drawN 500 c generatedGame
  tGen1 <- timeNs
  report "render (generated level)" 500 (tGen1 - tGen0)

  tGenStep0 <- timeNs
  let generatedFinal = runSteps 1000 survivorGame
  tGenStep1 <- timeNs
  report "step (generated, survivable)" 1000 (tGenStep1 - tGenStep0)
  putStrLn ("generated final turn: " ++ show generatedFinal.turn)

  tGenDraw0 <- timeNs
  drawStepN 500 c survivorGame
  tGenDraw1 <- timeNs
  report "step+render (generated)" 500 (tGenDraw1 - tGenDraw0)

  tMake0 <- timeNs
  let generatedRng = generateN 100 10 (fromSeed 42)
  tMake1 <- timeNs
  report "generate level (depth 10)" 100 (tMake1 - tMake0)
  putStrLn ("generation RNG: " ++ stateHex generatedRng)

  putStrLn "perf test passed"
