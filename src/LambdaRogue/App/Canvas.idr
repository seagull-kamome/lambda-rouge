||| The only module that writes the game map into a `TermUI.Canvas`.
|||
||| `Canvas` is an IO-mutable resource owned by the app model.  Keeping
||| every `putCell` call here lets `UI/MapView.idr` stay pure and lets the
||| view function return a `canvas` node without doing IO.
module LambdaRogue.App.Canvas

import Data.List
import LambdaRogue.Core.Types
import LambdaRogue.UI.Animation
import LambdaRogue.UI.MapView
import LambdaRogue.UI.Theme
import TermUI.Canvas
import TermUI.Len
import TermUI.Style

%default covering

||| Draw the map, then the short-lived effects on top of it.  Effects are
||| already clipped to the 80x22 map by `UI.Animation.effectCells`.
public export
drawMapAnimated : Theme -> Maybe Coord -> List Effect -> Canvas -> Game -> IO ()
drawMapAnimated theme hovered effects c g = do
  clear c (styleFor theme BackgroundRole)
  traverse_ draw (mapCellsWith theme hovered g)
  traverse_ drawEffectCell (effectCells effects)
  where
    draw : (Int32, Int32, Cell) -> IO ()
    draw (x, y, cell) = putCell c x y cell.glyph cell.style

    drawEffectCell : (Int32, Int32, Char, StyleRole) -> IO ()
    drawEffectCell (x, y, glyph, role) =
      putCell c x y glyph (styleFor theme role)

public export
drawMapWith : Theme -> Maybe Coord -> Canvas -> Game -> IO ()
drawMapWith theme hovered = drawMapAnimated theme hovered []

public export
drawMapIn : Theme -> Canvas -> Game -> IO ()
drawMapIn theme = drawMapWith theme Nothing

||| Draw with the default classic theme.  Tests and the initial startup path
||| use this; the update loop calls `drawMapAnimated` when animation ticks
||| change the overlay.
public export
drawMap : Canvas -> Game -> IO ()
drawMap = drawMapWith ClassicCga Nothing
