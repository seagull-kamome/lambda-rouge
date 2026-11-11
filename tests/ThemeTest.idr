||| Presentation-theme tests: the theme is UI state only, never game state.
module ThemeTest

import Data.List
import LambdaRogue.App.Model
import LambdaRogue.App.Subs
import LambdaRogue.App.Update
import LambdaRogue.App.View
import LambdaRogue.Core.Dungeon
import LambdaRogue.Core.Game
import LambdaRogue.Core.Replay
import LambdaRogue.Core.Types
import LambdaRogue.UI.MapView
import LambdaRogue.UI.Theme
import System
import TermUI.Canvas
import TermUI.Frame
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

isTheme : Maybe Msg -> Bool
isTheme (Just CycleTheme) = True
isTheme _ = False

public export
run : IO ()
run = do
  check "there are seven themes"
    (length themes == 7)
  check "the theme list has no duplicates"
    (length (nub themes) == 7)
  check "the theme cycle returns to classic"
    (nextTheme (nextTheme (nextTheme (nextTheme (nextTheme (nextTheme
      (nextTheme ClassicCga)))))) == ClassicCga)
  check "the theme cycle advances in order"
    (nextTheme ClassicCga == ModernDark
     && nextTheme ModernDark == Amber
     && nextTheme Amber == GreenPhosphor
     && nextTheme GreenPhosphor == HighContrast
     && nextTheme HighContrast == ColorblindSafe
     && nextTheme ColorblindSafe == Monochrome)
  check "each theme has a distinct title style"
    (length (nub (map (\t => styleFor t TitleRole) themes)) == 7)

  check "theme ids round-trip"
    (all (\t => themeFromId (themeId t) == Just t) themes)
  check "the monochrome id parses"
    (themeFromId "monochrome" == Just Monochrome)
  check "an unknown theme id is rejected"
    (themeFromId "neon" == Nothing)

  check "NO_COLOR selects monochrome"
    (detectColourSupport (Just "1") Nothing Nothing == NoColour)
  check "TERM=dumb selects monochrome"
    (detectColourSupport Nothing Nothing (Just "dumb") == NoColour)
  check "COLORTERM=truecolor selects TrueColor"
    (detectColourSupport Nothing (Just "truecolor") Nothing == TrueColour)
  check "a plain terminal selects ANSI colour"
    (detectColourSupport Nothing Nothing (Just "xterm-256color")
       == AnsiColour)
  check "NO_COLOR beats COLORTERM"
    (detectColourSupport (Just "1") (Just "truecolor") Nothing == NoColour)
  check "an empty NO_COLOR is ignored"
    (detectColourSupport (Just "") Nothing Nothing == AnsiColour)
  check "NO_MOTION requests reduced motion"
    (detectReducedMotion (Just "1") && not (detectReducedMotion Nothing))

  check "no colour forces the monochrome theme"
    (themeForSupport NoColour ModernDark == Monochrome
     && themeForSupport NoColour Monochrome == Monochrome)
  check "an ANSI terminal downgrades an RGB theme"
    (themeForSupport AnsiColour ModernDark == ClassicCga
     && themeForSupport AnsiColour Amber == ClassicCga)
  check "an ANSI terminal keeps ANSI themes"
    (themeForSupport AnsiColour ClassicCga == ClassicCga
     && themeForSupport AnsiColour HighContrast == HighContrast)
  check "TrueColor keeps the requested theme"
    (themeForSupport TrueColour ModernDark == ModernDark
     && themeForSupport TrueColour Monochrome == Monochrome)
  check "the monochrome theme uses attributes only"
    (styleFor Monochrome BodyRole == plain
     && styleFor Monochrome TitleRole == withAttr Bold plain
     && styleFor Monochrome PlayerRole
          == withAttr Inverse (withAttr Bold plain))

  check "classic player style is unchanged"
    (styleFor ClassicCga PlayerRole == playerStyle)
  check "classic monster style is unchanged"
    (styleFor ClassicCga MonsterRole == monsterStyle)
  check "classic item style is unchanged"
    (styleFor ClassicCga ItemRole == itemStyle)
  check "classic trap style is unchanged"
    (styleFor ClassicCga TrapRole == trapStyle)

  check "a themed map cell uses the theme player style"
    (case cellForIn ModernDark sampleGame (MkCoord 4 5) Floor of
       Just c => c.glyph == '@' && c.style == playerStyleIn ModernDark
       Nothing => False)
  check "a theme does not change which map cells exist"
    (length (mapCellsIn ModernDark sampleGame)
       == length (mapCells sampleGame))
  check "modern dark differs from classic on the map"
    (playerStyleIn ModernDark /= playerStyle)

  check "warning messages use the danger style"
    (messageStyleFor ModernDark WarningMsg
       == styleFor ModernDark DangerRole)
  check "item messages use the item style"
    (messageStyleFor Amber ItemMsg == styleFor Amber ItemRole)
  check "story messages use the dim style"
    (messageStyleFor GreenPhosphor StoryMsg
       == styleFor GreenPhosphor DimRole)

  c <- newCanvas (the Len 80) (the Len 22)
  let m = initModel c sampleGame
  check "F3 requests a theme cycle"
    (isTheme (key m (Press (KF 3) noMods)))
  let out = update CycleTheme m
      m' = fst out
  check "the update changes only the theme"
    (m'.theme == ModernDark
     && m'.game.turn == m.game.turn
     && m'.replay.commands == m.replay.commands
     && m'.width == m.width && m'.height == m.height)

  let wide : Model
      wide = { width := 120, height := 40 } m
      wideDark : Model
      wideDark = { theme := ModernDark } wide
  fClassic <- render (view wide) 120 40
  cClassic : TermUI.Frame.Cell <- getCell fClassic 0 0
  fDark <- render (view wideDark) 120 40
  cDark : TermUI.Frame.Cell <- getCell fDark 0 0
  check "the view paints the header in the theme colour"
    (cClassic.style == settle (styleFor ClassicCga HeaderRole)
     && cDark.style == settle (styleFor ModernDark HeaderRole)
     && cClassic.style /= cDark.style)

  putStrLn "theme tests passed"
