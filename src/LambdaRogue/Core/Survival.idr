||| Hunger, starvation and status timers.
|||
||| Rogue 5.4.4 starts a character with 1300 nutrition, becomes hungry at
||| 300, weak at 150, and starts fainting at 0.  Hunger reaches the fatal
||| -850 after roughly 850 further turns.  One point is consumed per turn
||| (slow-digestion rings reduce that rate).
module LambdaRogue.Core.Survival

import Data.List
import LambdaRogue.Core.Message
import LambdaRogue.Core.Types

%default covering

public export
hungerMax : Int32
hungerMax = startingHunger

public export
hungryAt : Int32
hungryAt = 300

public export
weakAt : Int32
weakAt = 150

public export
starvingAt : Int32
starvingAt = 0

||| Hunger value at which the character dies of starvation.
public export
starvingDeathAt : Int32
starvingDeathAt = -850

public export
data HungerState = Satiated | Normal | Hungry | Weak | Fainting

public export
Eq HungerState where
  Satiated == Satiated = True
  Normal == Normal = True
  Hungry == Hungry = True
  Weak == Weak = True
  Fainting == Fainting = True
  _ == _ = False

public export
Show HungerState where
  show Satiated = "Satiated"
  show Normal = "Normal"
  show Hungry = "Hungry"
  show Weak = "Weak"
  show Fainting = "Fainting"

public export
hungerState : Int32 -> HungerState
hungerState h =
  if h > 1000 then Satiated
  else if h > hungryAt then Normal
  else if h > weakAt then Hungry
  else if h > starvingAt then Weak
  else Fainting

expiryMessage : StatusKind -> Msg
expiryMessage = StatusExpires

statusDamage : List Status -> Int32
statusDamage ss =
  foldl (\acc, s => if s.statusKind == Poisoned then acc + 1 else acc) 0 ss

tickStatuses : Player -> (Player, List Msg)
tickStatuses p =
  let stepped = map (\s => { remaining := s.remaining - 1 } s) p.statuses
      expired = filter (\s => s.remaining <= 0) stepped
      kept = filter (\s => s.remaining > 0) stepped
      msgs = map (\s => expiryMessage s.statusKind) expired
      dmg = statusDamage p.statuses
      hp' = max 0 (p.hp - dmg)
      p' : Player
      p' = { statuses := kept, hp := hp' } p
  in (p', msgs)

||| Advance one consumed turn of status timers and hunger.  The caller
||| applies the returned player and messages, then checks `died`.
public export
record SurvivalResult where
  constructor MkSurvivalResult
  player : Player
  messages : List Msg
  died : Maybe DeathCause

public export
tickSurvival : Player -> SurvivalResult
tickSurvival p0 =
  let (p1, statusMsgs) = tickStatuses p0
      h0 : Int32
      h0 = p0.hunger
      h1 : Int32
      h1 = h0 - 1
      hungerMsgs : List Msg
      hungerMsgs =
        (if h0 > hungryAt && h1 <= hungryAt then [Hungry] else [])
        ++ (if h0 > weakAt && h1 <= weakAt then [WeakFromHunger] else [])
        ++ (if h0 > starvingAt && h1 <= starvingAt
               then [FaintFromHunger]
               else [])
      hp' : Int32
      hp' = p1.hp
      p2 : Player
      p2 = { hunger := h1, hp := hp' } p1
      died =
        if h1 <= starvingDeathAt
           then Just Starved
           else if hp' <= 0 && statusDamage p0.statuses > 0
                   then Just (OtherDeath "poison")
                   else Nothing
  in MkSurvivalResult p2 (statusMsgs ++ hungerMsgs) died
