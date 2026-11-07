||| Mouse-policy tests: screen-to-cell conversion, clicks, wheel and hover.
||| Every assertion is pure; no terminal is opened.
module MouseTest

import Data.List
import Data.Maybe
import LambdaRogue.App.Model
import LambdaRogue.App.Mouse
import LambdaRogue.App.Update
import LambdaRogue.Core.Dungeon
import LambdaRogue.Core.Game
import LambdaRogue.Core.Geometry
import LambdaRogue.Core.Replay
import LambdaRogue.Core.Types
import LambdaRogue.UI.MapView
import LambdaRogue.UI.Theme
import System
import TermUI.Canvas
import TermUI.Input
import TermUI.Len
import TermUI.Program
import TermUI.Style

check : String -> Bool -> IO ()
check name ok =
  if ok
     then putStrLn ("ok   " ++ name)
     else do
       putStrLn ("FAIL " ++ name)
       exitFailure

contains : String -> String -> Bool
contains needle hay = isInfixOf (unpack needle) (unpack hay)

leftDown : Len -> Len -> MouseEvent
leftDown c r = MkMouseEvent LeftButton ButtonDown c r noMods 1

leftDouble : Len -> Len -> MouseEvent
leftDouble c r = MkMouseEvent LeftButton ButtonDown c r noMods 2

moveAt : Len -> Len -> MouseEvent
moveAt c r = MkMouseEvent NoButton Move c r noMods 1

wheelUp : Len -> Len -> MouseEvent
wheelUp c r = MkMouseEvent WheelUp ButtonDown c r noMods 1

wheelDown : Len -> Len -> MouseEvent
wheelDown c r = MkMouseEvent WheelDown ButtonDown c r noMods 1

isMove : Dir -> Maybe Msg -> Bool
isMove d (Just (Do (Move d'))) = d == d'
isMove _ _ = False

isZap : Dir -> Maybe Msg -> Bool
isZap d (Just (Do (Zap 2 d'))) = d == d'
isZap _ _ = False

isThrow : Dir -> Maybe Msg -> Bool
isThrow d (Just (Do (Throw 2 d'))) = d == d'
isThrow _ _ = False

isDescend : Maybe Msg -> Bool
isDescend (Just (Do Descend)) = True
isDescend _ = False

isAscend : Maybe Msg -> Bool
isAscend (Just (Do Ascend)) = True
isAscend _ = False

isPickUp : Maybe Msg -> Bool
isPickUp (Just (Do PickUp)) = True
isPickUp _ = False

isSelect : ItemId -> Maybe Msg -> Bool
isSelect iid (Just (SelectItem iid')) = iid == iid'
isSelect _ _ = False

isAct : ItemAction -> ItemId -> Maybe Msg -> Bool
isAct act iid (Just (ActOnItem act' iid')) = act == act' && iid == iid'
isAct _ _ _ = False

isCloseInventory : Maybe Msg -> Bool
isCloseInventory (Just CloseInventory) = True
isCloseInventory _ = False

isHover : Maybe Coord -> Maybe Msg -> Bool
isHover c (Just (HoverCell c')) = c == c'
isHover _ _ = False

isPaletteSelect : Nat -> Maybe Msg -> Bool
isPaletteSelect n (Just (PaletteSelect n')) = n == n'
isPaletteSelect _ _ = False

isPaletteRun : Nat -> Maybe Msg -> Bool
isPaletteRun n (Just (PaletteRun n')) = n == n'
isPaletteRun _ _ = False

isPalettePrev : Maybe Msg -> Bool
isPalettePrev (Just PalettePrev) = True
isPalettePrev _ = False

isPaletteNext : Maybe Msg -> Bool
isPaletteNext (Just PaletteNext) = True
isPaletteNext _ = False

isClosePalette : Maybe Msg -> Bool
isClosePalette (Just ClosePalette) = True
isClosePalette _ = False

isCloseHelp : Maybe Msg -> Bool
isCloseHelp (Just CloseHelp) = True
isCloseHelp _ = False

isCloseScores : Maybe Msg -> Bool
isCloseScores (Just CloseScores) = True
isCloseScores _ = False

isCopySeed : Maybe Msg -> Bool
isCopySeed (Just CopySeed) = True
isCopySeed _ = False

isCloseShare : Maybe Msg -> Bool
isCloseShare (Just CloseShare) = True
isCloseShare _ = False

isFilter : Maybe Msg -> Bool
isFilter (Just CycleLogFilter) = True
isFilter _ = False

isFilterBack : Maybe Msg -> Bool
isFilterBack (Just CycleLogFilterBack) = True
isFilterBack _ = False

cellAt : Game -> Maybe Coord -> Coord -> Maybe Cell
cellAt g hovered c =
  case find (\(x, y, _) => x == c.x && y == c.y)
            (mapCellsWith ClassicCga hovered g) of
    Just (_, _, cell) => Just cell
    Nothing => Nothing

public export
run : IO ()
run = do
  c <- newCanvas (the Len 80) (the Len 22)
  let base = initModel c sampleGame
      classic : Model
      classic = { width := 80, height := 24 } base
      centered : Model
      centered = { width := 100, height := 30 } base
      wide : Model
      wide = { width := 120, height := 40 } base

  check "classic map starts below the latest-message line"
    (mapCellAt classic 0 1 == Just (MkCoord 0 0)
     && mapCellAt classic 79 22 == Just (MkCoord 79 21))
  check "the latest-message line is not the map"
    (isNothing (mapCellAt classic 0 0))
  check "the map is not wider than 80 cells"
    (isNothing (mapCellAt classic 80 1))
  check "a centered layout subtracts its origin"
    (mapCellAt centered 15 9 == Just (MkCoord 5 5))
  check "the wide layout has the same map offset"
    (mapCellAt wide 5 6 == Just (MkCoord 5 5))
  check "a too-small screen has no map cells"
    (isNothing (mapCellAt ({ width := 40, height := 10 } base) 0 0))

  check "a click one cell east requests one step east"
    (isMove E (mouseMsg classic (leftDown 5 6)))
  check "a click one cell north-east requests a diagonal step"
    (isMove NE (mouseMsg classic (leftDown 5 5)))
  check "a click farther away still requests one step"
    (isMove E (mouseMsg classic (leftDown 12 6)))
  check "a click on unexplored rock is ignored"
    (isNothing (mouseMsg classic (leftDown 0 1)))
  check "a click in the message line is ignored"
    (isNothing (mouseMsg classic (leftDown 10 0)))

  let mZap : Model
      mZap = { pendingDir := Just (ZapDir 2) } classic
  check "a map click answers the zap direction prompt"
    (isZap E (mouseMsg mZap (leftDown 5 6)))
  let mThrow : Model
      mThrow = { pendingDir := Just (ThrowDir 2) } classic
  check "a map click answers the throw direction prompt"
    (isThrow E (mouseMsg mThrow (leftDown 5 6)))

  let gStairs : Game
      gStairs = { player := { pos := MkCoord 3 8 } sampleGame.player } sampleGame
      mStairs : Model
      mStairs = { game := gStairs } classic
  check "a click on the player's up stairs ascends"
    (isAscend (mouseMsg mStairs (leftDown 3 9)))

  let gItem : Game
      gItem = { player := { pos := MkCoord 7 5 } sampleGame.player } sampleGame
      mItem : Model
      mItem = { game := gItem } classic
  check "a click on the player's item picks it up"
    (isPickUp (mouseMsg mItem (leftDown 7 6)))

  let potion : Item
      potion = MkItem 2 (Potion PotionHealing) InPack 1 0 False 0 False
      pPack : Player
      pPack = { inventory := [2] } sampleGame.player
      gPack : Game
      gPack = { player := pPack, items := [potion] } sampleGame
      mPack : Model
      mPack = { game := gPack } classic
      mInv : Model
      mInv = { inventoryOpen := True } mPack
      mInvIntent : Model
      mInvIntent = { inventoryOpen := True, inventoryIntent := Just EatAction } mPack
  check "the first classic inventory row is slot zero"
    (inventorySlotAt mInv 2 1 == Just 0)
  check "the right classic inventory column starts at slot 20"
    (inventorySlotAt mInv 45 1 == Just 20)
  check "a single click selects an inventory row"
    (isSelect 2 (mouseMsg mInv (leftDown 2 1)))
  check "a double click uses the row's default action"
    (isAct QuaffAction 2 (mouseMsg mInv (leftDouble 2 1)))
  check "a click with an item intent acts immediately"
    (isAct EatAction 2 (mouseMsg mInvIntent (leftDown 2 1)))
  check "the inventory wheel selects an item"
    (isSelect 2 (mouseMsg mInv (wheelDown 2 1)))
  check "a click outside the inventory closes it"
    (isCloseInventory (mouseMsg ({ width := 100, height := 30 } mInv) (leftDown 0 0)))

  check "the palette wheel-down and click select a row"
    (isPaletteSelect 15 (mouseMsg ({ paletteOpen := True } classic) (leftDown 5 17)))
  check "a palette double click runs the row"
    (isPaletteRun 15 (mouseMsg ({ paletteOpen := True } classic) (leftDouble 5 17)))
  check "the palette wheel moves down"
    (isPaletteNext (mouseMsg ({ paletteOpen := True } classic) (wheelDown 5 10)))
  check "the palette wheel moves up"
    (isPalettePrev (mouseMsg ({ paletteOpen := True } classic) (wheelUp 5 10)))
  check "a click outside the palette closes it"
    (isClosePalette (mouseMsg ({ width := 100, height := 30 } ({ paletteOpen := True } classic)) (leftDown 0 0)))

  check "a click closes help"
    (isCloseHelp (mouseMsg ({ helpOpen := True } classic) (leftDown 5 5)))
  check "a click closes the score screen"
    (isCloseScores (mouseMsg ({ scoreOpen := True } classic) (leftDown 5 5)))
  check "the share copy row copies the seed"
    (isCopySeed (mouseMsg ({ shareOpen := True } classic) (leftDown 10 11)))
  check "the share close row closes the screen"
    (isCloseShare (mouseMsg ({ shareOpen := True } classic) (leftDown 10 12)))
  check "a click outside the share panel closes it"
    (isCloseShare (mouseMsg ({ width := 100, height := 30 }
                               ({ shareOpen := True } classic)) (leftDown 0 0)))

  check "a move over the map yields a hover cell"
    (isHover (Just (MkCoord 5 5)) (mouseMsg classic (moveAt 5 6)))
  check "a move off the map clears the hover cell"
    (isHover Nothing (mouseMsg classic (moveAt 5 0)))
  check "a hover cell is painted with the inverse attribute"
    (case cellAt sampleGame (Just (MkCoord 4 5)) (MkCoord 4 5) of
       Just cell => cell.style == withAttr Inverse playerStyle
       Nothing => False)
  check "the hover description names the player"
    (case describeCell sampleGame (MkCoord 4 5) of
       Just text => contains "you" text
       Nothing => False)
  check "the hover description names a visible item"
    (case describeCell sampleGame (MkCoord 7 5) of
       Just text => contains "food ration" text
       Nothing => False)
  check "unexplored cells have no description"
    (isNothing (describeCell sampleGame (MkCoord 0 0)))

  check "the classic message line takes the next log filter on wheel down"
    (isFilter (mouseMsg classic (wheelDown 5 0)))
  check "the classic message line takes the previous filter on wheel up"
    (isFilterBack (mouseMsg classic (wheelUp 5 0)))
  check "the wide log pane takes the next log filter on wheel down"
    (isFilter (mouseMsg wide (wheelDown 10 31)))

  let hovered = fst (update (HoverCell (Just (MkCoord 5 5))) classic)
  check "a hover update records no command and consumes no turn"
    (hovered.hover == Just (MkCoord 5 5)
     && hovered.game.turn == classic.game.turn
     && hovered.replay.commands == classic.replay.commands)

  let mPlayback : Model
      mPlayback = { replay := recordCommand Wait (emptyReplay sampleGame.seed) } classic
      mPlaying = fst (update StartReplay mPlayback)
  check "mouse clicks are ignored during replay playback"
    (isNothing (mouseMsg mPlaying (leftDown 5 6)))

  check "a mouse click step records a command only after update"
    (let m' = fst (update (fromMaybe (Do Wait) (mouseMsg classic (leftDown 5 6))) classic)
     in length m'.replay.commands == 1
        && m'.game.turn == classic.game.turn + 1)

  putStrLn "mouse tests passed"
