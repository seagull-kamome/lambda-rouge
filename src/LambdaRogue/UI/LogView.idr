||| Pure presentation of the message log.
module LambdaRogue.UI.LogView

import Data.List
import LambdaRogue.Core.Types
import TermUI.Style

%default covering

public export
messageStyle : MessageKind -> Style
messageStyle CombatMsg = fgColor (Indexed 7) plain
messageStyle ItemMsg = fgColor (Indexed 11) plain
messageStyle SystemMsg = fgColor (Indexed 6) plain
messageStyle WarningMsg = withAttr Bold (fgColor (Indexed 9) plain)
messageStyle StoryMsg = fgColor (Indexed 8) plain

||| The newest message, if any.
public export
latestMessage : Game -> Maybe Message
latestMessage g = head' g.messages

||| Up to `n` messages in chronological order (oldest first).
public export
recentMessages : Nat -> Game -> List Message
recentMessages n g = reverse (take n g.messages)
