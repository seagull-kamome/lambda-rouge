||| Presentation-only colour themes.
|||
||| A theme changes styles, never game state.  The Core does not import this
||| module, and switching a theme does not consume a turn or any randomness.
module LambdaRogue.UI.Theme

import LambdaRogue.Core.Types
import TermUI.Style

%default covering

public export
data Theme
  = ClassicCga
  | ModernDark
  | Amber
  | GreenPhosphor
  | HighContrast
  | ColorblindSafe
  | Monochrome

public export
Eq Theme where
  ClassicCga == ClassicCga = True
  ModernDark == ModernDark = True
  Amber == Amber = True
  GreenPhosphor == GreenPhosphor = True
  HighContrast == HighContrast = True
  ColorblindSafe == ColorblindSafe = True
  Monochrome == Monochrome = True
  _ == _ = False

public export
Show Theme where
  show ClassicCga = "Classic CGA"
  show ModernDark = "Modern Dark"
  show Amber = "Amber"
  show GreenPhosphor = "Green Phosphor"
  show HighContrast = "High Contrast"
  show ColorblindSafe = "Colorblind Safe"
  show Monochrome = "Monochrome"

||| The order used by `F3` and the command palette.
public export
themes : List Theme
themes =
  [ ClassicCga
  , ModernDark
  , Amber
  , GreenPhosphor
  , HighContrast
  , ColorblindSafe
  , Monochrome
  ]

public export
nextTheme : Theme -> Theme
nextTheme ClassicCga = ModernDark
nextTheme ModernDark = Amber
nextTheme Amber = GreenPhosphor
nextTheme GreenPhosphor = HighContrast
nextTheme HighContrast = ColorblindSafe
nextTheme ColorblindSafe = Monochrome
nextTheme Monochrome = ClassicCga

||| Stable names for `settings.json`.  These are independent of display
||| names and of the order in `themes`.
public export
themeId : Theme -> String
themeId ClassicCga = "classic-cga"
themeId ModernDark = "modern-dark"
themeId Amber = "amber"
themeId GreenPhosphor = "green-phosphor"
themeId HighContrast = "high-contrast"
themeId ColorblindSafe = "colorblind-safe"
themeId Monochrome = "monochrome"

public export
themeFromId : String -> Maybe Theme
themeFromId "classic-cga" = Just ClassicCga
themeFromId "modern-dark" = Just ModernDark
themeFromId "amber" = Just Amber
themeFromId "green-phosphor" = Just GreenPhosphor
themeFromId "high-contrast" = Just HighContrast
themeFromId "colorblind-safe" = Just ColorblindSafe
themeFromId "monochrome" = Just Monochrome
themeFromId _ = Nothing

||| What the terminal can actually display.  Themes are downgraded rather
||| than emitting unsupported RGB escapes: `NO_COLOR` selects monochrome,
||| and a terminal without TrueColor falls back to an ANSI-only theme.
public export
data ColourSupport = NoColour | AnsiColour | TrueColour

public export
Eq ColourSupport where
  NoColour == NoColour = True
  AnsiColour == AnsiColour = True
  TrueColour == TrueColour = True
  _ == _ = False

public export
Show ColourSupport where
  show NoColour = "none"
  show AnsiColour = "ansi"
  show TrueColour = "truecolor"

nonEmpty : Maybe String -> Bool
nonEmpty (Just "") = False
nonEmpty (Just _) = True
nonEmpty Nothing = False

||| `NO_COLOR` (any non-empty value) and `TERM=dumb` mean no colour.
||| `COLORTERM=truecolor` or `24bit` means RGB is safe; everything else
||| gets the conservative ANSI palette.
public export
detectColourSupport : Maybe String -> Maybe String -> Maybe String
                    -> ColourSupport
detectColourSupport noColor colorterm term =
  if nonEmpty noColor || term == Just "dumb"
     then NoColour
     else if colorterm == Just "truecolor" || colorterm == Just "24bit"
             then TrueColour
             else AnsiColour

||| The usual `prefers-reduced-motion` equivalent for a terminal.  A
||| non-empty `NO_MOTION` asks for no animation; the startup flag does the
||| same even when this is unset.
public export
detectReducedMotion : Maybe String -> Bool
detectReducedMotion = nonEmpty

||| Pick a theme the terminal can render.  Monochrome survives every
||| capability; ANSI-only terminals avoid the RGB themes.
public export
themeForSupport : ColourSupport -> Theme -> Theme
themeForSupport NoColour _ = Monochrome
themeForSupport AnsiColour Monochrome = Monochrome
themeForSupport AnsiColour HighContrast = HighContrast
themeForSupport AnsiColour ColorblindSafe = HighContrast
themeForSupport AnsiColour ClassicCga = ClassicCga
themeForSupport AnsiColour _ = ClassicCga
themeForSupport TrueColour theme = theme

||| Semantic style slots used by the view and the map.  Keeping this list
||| small means a new theme only has to fill in presentation decisions, not
||| game rules.
public export
data StyleRole
  = BackgroundRole
  | BodyRole
  | TitleRole
  | HeaderRole
  | DimRole
  | DimCellRole
  | StatusRole
  | DangerRole
  | BorderRole
  | MinimapRole
  | RockRole
  | FloorRole
  | CorridorRole
  | DoorRole
  | StairsRole
  | MonsterRole
  | DetectedMonsterRole
  | ItemRole
  | DetectedItemRole
  | TrapRole
  | PlayerRole
  | SystemRole

boldFg : Color -> Style
boldFg c = withAttr Bold (fgColor c plain)

dimFg : Color -> Style
dimFg c = withAttr Dim (fgColor c plain)

statusOf : Color -> Color -> Style
statusOf bg fg = bgColor bg (fgColor fg plain)

-- Classic CGA keeps the original 16-colour ANSI palette and is the default.
classicStyle : StyleRole -> Style
classicStyle BackgroundRole = bgColor (Indexed 0) (fgColor (Indexed 8) plain)
classicStyle BodyRole = fgColor (Indexed 7) plain
classicStyle TitleRole = boldFg (Indexed 11)
classicStyle HeaderRole = boldFg (Indexed 6)
classicStyle DimRole = fgColor (Indexed 8) plain
classicStyle DimCellRole = dimFg (Indexed 8)
classicStyle StatusRole = statusOf (Indexed 8) (Indexed 0)
classicStyle DangerRole = boldFg (Indexed 9)
classicStyle BorderRole = fgColor (Indexed 6) plain
classicStyle MinimapRole = fgColor (Indexed 6) plain
classicStyle RockRole = fgColor (Indexed 7) plain
classicStyle FloorRole = fgColor (Indexed 8) plain
classicStyle CorridorRole = fgColor (Indexed 6) plain
classicStyle DoorRole = fgColor (Indexed 3) plain
classicStyle StairsRole = boldFg (Indexed 11)
classicStyle MonsterRole = boldFg (Indexed 9)
classicStyle DetectedMonsterRole = dimFg (Indexed 9)
classicStyle ItemRole = fgColor (Indexed 11) plain
classicStyle DetectedItemRole = dimFg (Indexed 11)
classicStyle TrapRole = boldFg (Indexed 13)
classicStyle PlayerRole = boldFg (Indexed 15)
classicStyle SystemRole = fgColor (Indexed 6) plain

-- A dark slate background with cool accents.
modernStyle : StyleRole -> Style
modernStyle BackgroundRole =
  bgColor (RGB 16 18 26) (fgColor (RGB 208 212 224) plain)
modernStyle BodyRole = fgColor (RGB 208 212 224) plain
modernStyle TitleRole = boldFg (RGB 120 200 255)
modernStyle HeaderRole = boldFg (RGB 130 220 180)
modernStyle DimRole = fgColor (RGB 110 116 136) plain
modernStyle DimCellRole = dimFg (RGB 110 116 136)
modernStyle StatusRole = statusOf (RGB 36 42 58) (RGB 230 234 244)
modernStyle DangerRole = boldFg (RGB 255 110 110)
modernStyle BorderRole = fgColor (RGB 80 120 160) plain
modernStyle MinimapRole = fgColor (RGB 120 200 255) plain
modernStyle RockRole = fgColor (RGB 92 98 122) plain
modernStyle FloorRole = fgColor (RGB 108 114 138) plain
modernStyle CorridorRole = fgColor (RGB 100 150 190) plain
modernStyle DoorRole = fgColor (RGB 220 190 120) plain
modernStyle StairsRole = boldFg (RGB 250 220 120)
modernStyle MonsterRole = boldFg (RGB 255 130 130)
modernStyle DetectedMonsterRole = dimFg (RGB 255 130 130)
modernStyle ItemRole = fgColor (RGB 250 200 100) plain
modernStyle DetectedItemRole = dimFg (RGB 250 200 100)
modernStyle TrapRole = boldFg (RGB 230 130 220)
modernStyle PlayerRole = boldFg (RGB 255 255 255)
modernStyle SystemRole = fgColor (RGB 100 150 190) plain

-- Monochrome amber, like a phosphor terminal.
amberStyle : StyleRole -> Style
amberStyle BackgroundRole =
  bgColor (RGB 20 12 0) (fgColor (RGB 255 176 0) plain)
amberStyle BodyRole = fgColor (RGB 255 176 0) plain
amberStyle TitleRole = boldFg (RGB 255 214 90)
amberStyle HeaderRole = boldFg (RGB 255 190 40)
amberStyle DimRole = fgColor (RGB 140 92 0) plain
amberStyle DimCellRole = dimFg (RGB 140 92 0)
amberStyle StatusRole = statusOf (RGB 255 176 0) (RGB 20 12 0)
amberStyle DangerRole = boldFg (RGB 255 90 40)
amberStyle BorderRole = fgColor (RGB 180 120 0) plain
amberStyle MinimapRole = fgColor (RGB 255 190 40) plain
amberStyle RockRole = fgColor (RGB 190 125 0) plain
amberStyle FloorRole = fgColor (RGB 140 92 0) plain
amberStyle CorridorRole = fgColor (RGB 220 145 0) plain
amberStyle DoorRole = fgColor (RGB 255 210 70) plain
amberStyle StairsRole = boldFg (RGB 255 230 120)
amberStyle MonsterRole = boldFg (RGB 255 120 40)
amberStyle DetectedMonsterRole = dimFg (RGB 255 120 40)
amberStyle ItemRole = fgColor (RGB 255 210 80) plain
amberStyle DetectedItemRole = dimFg (RGB 255 210 80)
amberStyle TrapRole = boldFg (RGB 255 150 100)
amberStyle PlayerRole = boldFg (RGB 255 245 200)
amberStyle SystemRole = fgColor (RGB 220 145 0) plain

-- Green phosphor, with a warm warning colour so danger still stands out.
greenStyle : StyleRole -> Style
greenStyle BackgroundRole =
  bgColor (RGB 0 12 4) (fgColor (RGB 90 255 130) plain)
greenStyle BodyRole = fgColor (RGB 90 255 130) plain
greenStyle TitleRole = boldFg (RGB 170 255 180)
greenStyle HeaderRole = boldFg (RGB 90 240 130)
greenStyle DimRole = fgColor (RGB 30 120 55) plain
greenStyle DimCellRole = dimFg (RGB 30 120 55)
greenStyle StatusRole = statusOf (RGB 90 255 130) (RGB 0 12 4)
greenStyle DangerRole = boldFg (RGB 255 140 90)
greenStyle BorderRole = fgColor (RGB 50 180 85) plain
greenStyle MinimapRole = fgColor (RGB 90 240 130) plain
greenStyle RockRole = fgColor (RGB 55 160 85) plain
greenStyle FloorRole = fgColor (RGB 30 120 55) plain
greenStyle CorridorRole = fgColor (RGB 60 200 105) plain
greenStyle DoorRole = fgColor (RGB 160 255 150) plain
greenStyle StairsRole = boldFg (RGB 200 255 190)
greenStyle MonsterRole = boldFg (RGB 255 150 100)
greenStyle DetectedMonsterRole = dimFg (RGB 255 150 100)
greenStyle ItemRole = fgColor (RGB 200 255 160) plain
greenStyle DetectedItemRole = dimFg (RGB 200 255 160)
greenStyle TrapRole = boldFg (RGB 255 200 120)
greenStyle PlayerRole = boldFg (RGB 230 255 235)
greenStyle SystemRole = fgColor (RGB 60 200 105) plain

-- Maximum contrast: no dim text, bold labels, bright ANSI colours.
contrastStyle : StyleRole -> Style
contrastStyle BackgroundRole = bgColor (Indexed 0) (fgColor (Indexed 15) plain)
contrastStyle BodyRole = fgColor (Indexed 15) plain
contrastStyle TitleRole = boldFg (Indexed 15)
contrastStyle HeaderRole = boldFg (Indexed 14)
contrastStyle DimRole = fgColor (Indexed 7) plain
contrastStyle DimCellRole = withAttr Underline (fgColor (Indexed 7) plain)
contrastStyle StatusRole = statusOf (Indexed 15) (Indexed 0)
contrastStyle DangerRole = boldFg (Indexed 9)
contrastStyle BorderRole = fgColor (Indexed 15) plain
contrastStyle MinimapRole = boldFg (Indexed 14)
contrastStyle RockRole = fgColor (Indexed 7) plain
contrastStyle FloorRole = fgColor (Indexed 15) plain
contrastStyle CorridorRole = fgColor (Indexed 14) plain
contrastStyle DoorRole = boldFg (Indexed 11)
contrastStyle StairsRole = boldFg (Indexed 13)
contrastStyle MonsterRole = boldFg (Indexed 9)
contrastStyle DetectedMonsterRole = withAttr Underline (fgColor (Indexed 9) plain)
contrastStyle ItemRole = boldFg (Indexed 11)
contrastStyle DetectedItemRole = withAttr Underline (fgColor (Indexed 11) plain)
contrastStyle TrapRole = boldFg (Indexed 13)
contrastStyle PlayerRole = boldFg (Indexed 15)
contrastStyle SystemRole = fgColor (Indexed 14) plain

-- Okabe-Ito colours: blue, orange, yellow and purple instead of red/green.
colorblindStyle : StyleRole -> Style
colorblindStyle BackgroundRole =
  bgColor (RGB 16 16 20) (fgColor (RGB 230 230 230) plain)
colorblindStyle BodyRole = fgColor (RGB 230 230 230) plain
colorblindStyle TitleRole = boldFg (RGB 86 180 233)
colorblindStyle HeaderRole = boldFg (RGB 0 158 115)
colorblindStyle DimRole = fgColor (RGB 130 130 140) plain
colorblindStyle DimCellRole = dimFg (RGB 130 130 140)
colorblindStyle StatusRole = statusOf (RGB 0 114 178) (RGB 255 255 255)
colorblindStyle DangerRole = boldFg (RGB 213 94 0)
colorblindStyle BorderRole = fgColor (RGB 0 114 178) plain
colorblindStyle MinimapRole = fgColor (RGB 86 180 233) plain
colorblindStyle RockRole = fgColor (RGB 120 120 130) plain
colorblindStyle FloorRole = fgColor (RGB 180 180 190) plain
colorblindStyle CorridorRole = fgColor (RGB 86 180 233) plain
colorblindStyle DoorRole = fgColor (RGB 230 159 0) plain
colorblindStyle StairsRole = boldFg (RGB 240 228 66)
colorblindStyle MonsterRole = boldFg (RGB 204 121 167)
colorblindStyle DetectedMonsterRole = withAttr Underline (fgColor (RGB 204 121 167) plain)
colorblindStyle ItemRole = fgColor (RGB 240 228 66) plain
colorblindStyle DetectedItemRole = withAttr Underline (fgColor (RGB 240 228 66) plain)
colorblindStyle TrapRole = boldFg (RGB 230 159 0)
colorblindStyle PlayerRole = boldFg (RGB 255 255 255)
colorblindStyle SystemRole = fgColor (RGB 86 180 233) plain

-- No colour at all: shape and attributes carry the hierarchy.  This is the
-- fallback for `NO_COLOR` and the explicit accessibility theme.
monoStyle : StyleRole -> Style
monoStyle BackgroundRole = plain
monoStyle BodyRole = plain
monoStyle TitleRole = withAttr Bold plain
monoStyle HeaderRole = withAttr Bold plain
monoStyle DimRole = withAttr Dim plain
monoStyle DimCellRole = withAttr Dim plain
monoStyle StatusRole = withAttr Inverse plain
monoStyle DangerRole = withAttr Bold (withAttr Underline plain)
monoStyle BorderRole = plain
monoStyle MinimapRole = withAttr Bold plain
monoStyle RockRole = plain
monoStyle FloorRole = plain
monoStyle CorridorRole = withAttr Dim plain
monoStyle DoorRole = withAttr Bold plain
monoStyle StairsRole = withAttr Bold plain
monoStyle MonsterRole = withAttr Bold plain
monoStyle DetectedMonsterRole = withAttr Underline (withAttr Bold plain)
monoStyle ItemRole = withAttr Underline plain
monoStyle DetectedItemRole = withAttr Dim (withAttr Underline plain)
monoStyle TrapRole = withAttr Bold (withAttr Underline plain)
monoStyle PlayerRole = withAttr Inverse (withAttr Bold plain)
monoStyle SystemRole = withAttr Dim plain

public export
styleFor : Theme -> StyleRole -> Style
styleFor ClassicCga = classicStyle
styleFor ModernDark = modernStyle
styleFor Amber = amberStyle
styleFor GreenPhosphor = greenStyle
styleFor HighContrast = contrastStyle
styleFor ColorblindSafe = colorblindStyle
styleFor Monochrome = monoStyle

||| The style of a Core message under a theme.  This is presentation only;
||| the message text and order come from the Core unchanged.
public export
messageStyleFor : Theme -> MessageKind -> Style
messageStyleFor t CombatMsg = styleFor t BodyRole
messageStyleFor t ItemMsg = styleFor t ItemRole
messageStyleFor t SystemMsg = styleFor t SystemRole
messageStyleFor t WarningMsg = styleFor t DangerRole
messageStyleFor t StoryMsg = styleFor t DimRole
