||| Pure map-presentation tests: overlays, FOV filtering and dimming.
module MapViewTest

import Data.List
import Data.Maybe
import LambdaRogue.Core.Bitset
import LambdaRogue.Core.Dungeon
import LambdaRogue.Core.Fov
import LambdaRogue.Core.Types
import LambdaRogue.UI.MapView
import System
import TermUI.Style

check : String -> Bool -> IO ()
check name ok =
  if ok
     then putStrLn ("ok   " ++ name)
     else do
       putStrLn ("FAIL " ++ name)
       exitFailure

moveFov : Coord -> Game -> Game
moveFov c g =
  let lvl0 = currentLevel g
      vis = compute lvl0.tiles lvl0.rooms c
      explored = union lvl0.explored vis
      lvl : Level
      lvl = { explored := explored } lvl0
      p : Player
      p = { pos := c } g.player
      g1 : Game
      g1 = updateCurrentLevel (const lvl) g
  in { visible := vis, player := p } g1

public export
run : IO ()
run = do
  let g0 = sampleGame
      start = MkCoord 4 5
      itemPos = MkCoord 7 5
      monsterPos = MkCoord 36 5

  check "the player is drawn as @"
    (case cellFor g0 start Floor of
       Just c => c.glyph == '@' && c.style == playerStyle
       Nothing => False)
  check "a visible item is drawn"
    (case cellFor g0 itemPos Floor of
       Just c => c.glyph == '%'
       Nothing => False)
  check "an unexplored monster is not drawn"
    (isNothing (cellFor g0 monsterPos Floor))
  check "an unexplored cell is not in mapCells"
    (not (any (\(x, y, _) => x == 36 && y == 5) (mapCells g0)))
  check "mapCells covers exactly the explored cells"
    (length (mapCells g0) == count (currentLevel g0).explored)
  check "mapCells contains the player"
    (elem (4, 5, MkCell '@' playerStyle) (mapCells g0))

  let gRoom = moveFov (MkCoord 31 5) g0
  check "a visible monster is drawn"
    (case cellFor gRoom monsterPos Floor of
       Just c => c.glyph == 'K'
       Nothing => False)
  check "remembered terrain is dimmed"
    (case cellFor gRoom (MkCoord 5 5) Floor of
       Just c => c.glyph == '.' && hasAttr Dim c.style
       Nothing => False)
  check "currently visible terrain is not dimmed"
    (case cellFor gRoom (MkCoord 32 5) Floor of
       Just c => c.glyph == '.' && not (hasAttr Dim c.style)
       Nothing => False)

  let amulet = MkItem 9 Amulet (OnFloor 1 (MkCoord 8 5)) 1 0 False 0 False
      gAmulet = { items := [amulet] } g0
  check "the amulet is drawn as a quote"
    (case cellFor gAmulet (MkCoord 8 5) Floor of
       Just c => c.glyph == '"'
       Nothing => False)

  let scrollItem = MkItem 10 (Scroll ScrollMagicMapping) (OnFloor 1 (MkCoord 8 5)) 1 0 False 0 False
      wandItem = MkItem 11 (Wand WandLightning) (OnFloor 1 (MkCoord 9 5)) 1 0 False 5 False
      ringItem = MkItem 12 (Ring RingProtection) (OnFloor 1 (MkCoord 10 5)) 1 0 False 0 False
      gKinds = { items := [scrollItem, wandItem, ringItem] } g0
  check "a scroll is drawn as a question mark"
    (case cellFor gKinds (MkCoord 8 5) Floor of
       Just c => c.glyph == '?'
       Nothing => False)
  check "a wand is drawn as a slash"
    (case cellFor gKinds (MkCoord 9 5) Floor of
       Just c => c.glyph == '/'
       Nothing => False)
  check "a ring is drawn as an equals sign"
    (case cellFor gKinds (MkCoord 10 5) Floor of
       Just c => c.glyph == '='
       Nothing => False)

  let gRemembered = moveFov (MkCoord 20 8) gRoom
  check "a remembered monster is hidden without detection"
    (case cellFor gRemembered monsterPos Floor of
       Just c => c.glyph == '.'
       Nothing => False)
  let pDetect : Player
      pDetect = { statuses := [MkStatus DetectMonsters 5] }
                  gRemembered.player
      gDetect : Game
      gDetect = { player := pDetect } gRemembered
  check "detect monsters reveals remembered monsters"
    (case cellFor gDetect monsterPos Floor of
       Just c => c.glyph == 'K' && c.style == detectedMonsterStyle
       Nothing => False)

  check "remembered food is hidden without detection"
    (case cellFor gRoom (MkCoord 7 5) Floor of
       Just c => c.glyph == '.'
       Nothing => False)
  let pFood : Player
      pFood = { statuses := [MkStatus DetectFood 5] } gRoom.player
      gFood : Game
      gFood = { player := pFood } gRoom
  check "detect food reveals remembered food"
    (case cellFor gFood (MkCoord 7 5) Floor of
       Just c => c.glyph == '%' && c.style == detectedItemStyle
       Nothing => False)

  let stalker = MkMonster 5 Phantom monsterPos 10 10 Chasing []
      lvlStalker : Level
      lvlStalker = { monsters := [stalker] } (currentLevel gRoom)
      gStalker : Game
      gStalker = updateCurrentLevel (const lvlStalker) gRoom
  check "a distant invisible phantom is hidden"
    (case cellFor gStalker monsterPos Floor of
       Just c => c.glyph == '.'
       Nothing => False)

  let gAdjacent = moveFov (MkCoord 35 5) gStalker
  check "an adjacent invisible phantom is revealed"
    (case cellFor gAdjacent monsterPos Floor of
       Just c => c.glyph == 'P'
       Nothing => False)

  let pSee : Player
      pSee = { statuses := MkStatus SeeInvisible 5 :: gStalker.player.statuses }
               gStalker.player
      gSee : Game
      gSee = { player := pSee } gStalker
  check "see invisible reveals a distant stalker"
    (case cellFor gSee monsterPos Floor of
       Just c => c.glyph == 'P'
       Nothing => False)

  let ring = MkItem 13 (Ring RingSeeInvisible) InPack 1 0 False 0 False
      pRing : Player
      pRing = { inventory := [13], leftRing := Just 13 } gStalker.player
      gRing : Game
      gRing = { player := pRing, items := ring :: gStalker.items } gStalker
  check "a ring of see invisible reveals a distant stalker"
    (case cellFor gRing monsterPos Floor of
       Just c => c.glyph == 'P'
       Nothing => False)

  let mini = minimapRows sampleGame
  check "the minimap has 8 rows" (length mini == 8)
  check "each minimap row is 36 columns"
    (all (\r => length (unpack r) == 36) mini)
  check "the minimap marks the player"
    (any (\r => elem '@' (unpack r)) mini)
  check "the minimap shows explored stairs"
    (any (\r => elem '<' (unpack r)) mini)

  let miniSmall = minimapRowsWith 10 4 sampleGame
  check "the minimap can be resized"
    (length miniSmall == 4
     && all (\r => length (unpack r) == 10) miniSmall)

  let lvlHidden : Level
      lvlHidden = { explored := empty } (currentLevel sampleGame)
      gHidden : Game
      gHidden = updateCurrentLevel (const lvlHidden) sampleGame
      hiddenChars : List Char
      hiddenChars = concatMap unpack (minimapRows gHidden)
  check "the minimap hides unexplored cells"
    (length (filter (== '@') hiddenChars) == 1
     && all (\c => c == ' ' || c == '@') hiddenChars)

  let gSeen = moveFov (MkCoord 31 5) sampleGame
  check "the minimap never shows monsters"
    (not (any (\r => elem 'K' (unpack r)) (minimapRows gSeen)))

  putStrLn "map view tests passed"
