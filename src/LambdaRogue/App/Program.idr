||| Wiring for `TermUI.Program`.
module LambdaRogue.App.Program

import LambdaRogue.App.Model
import LambdaRogue.App.Subs
import LambdaRogue.App.Update
import LambdaRogue.App.View
import LambdaRogue.Core.Types
import TermUI.Canvas
import TermUI.Program

%default covering

public export
programWith : Model -> Program Model Msg
programWith model = MkProgram (model, NoCmd) update view subs

public export
program : Canvas -> Game -> Program Model Msg
program c g = programWith (initModel c g)
