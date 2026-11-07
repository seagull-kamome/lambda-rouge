||| Hunger, starvation and status timers.
|||
||| Rogue 5.4.4 starts a character with 1300 nutrition, becomes hungry at
||| 300, weak at 150, and starts fainting/starving at 0.  One point is
||| consumed per turn (slow-digestion rings reduce that rate).
module LambdaRogue.Core.Survival

import Data.List
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

expiryMessage : StatusKind -> String
expiryMessage Confused = "You are no longer confused."
expiryMessage Blinded = "You can see again."
expiryMessage Hasted = "You feel yourself slow down."
expiryMessage SeeInvisible = "Your eyes feel normal again."
expiryMessage DetectMonsters = "Your senses return to normal."
expiryMessage DetectFood = "Your food sense fades."
expiryMessage DetectMagic = "Your magic sense fades."
expiryMessage Invisible = "You are no longer invisible."
expiryMessage Poisoned = "The poison wears off."
expiryMessage Held = "You can move again."
expiryMessage Slowed = "You feel normal again."
expiryMessage Paralyzed = "You can move again."
expiryMessage Scared = "You feel brave again."
expiryMessage Sleeping = "You wake up."
expiryMessage Hallucinating = "Everything looks normal again."
expiryMessage Levitated = "You float gently back to the floor."
expiryMessage ConfuseNext = "Your hands stop glowing."

statusDamage : List Status -> Int32
statusDamage ss =
  foldl (\acc, s => if s.statusKind == Poisoned then acc + 1 else acc) 0 ss

tickStatuses : Player -> (Player, List String)
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
  messages : List String
  died : Maybe DeathCause

public export
tickSurvival : Player -> SurvivalResult
tickSurvival p0 =
  let (p1, statusMsgs) = tickStatuses p0
      h0 : Int32
      h0 = p0.hunger
      h1 : Int32
      h1 = h0 - 1
      hungerMsgs : List String
      hungerMsgs =
        (if h0 > hungryAt && h1 <= hungryAt then ["You are hungry."] else [])
        ++ (if h0 > weakAt && h1 <= weakAt then ["You are weak."] else [])
        ++ (if h0 > starvingAt && h1 <= starvingAt
               then ["You faint from lack of food."]
               else [])
      starving = h1 <= starvingAt
      hp' : Int32
      hp' = max 0 (if starving then p1.hp - 1 else p1.hp)
      p2 : Player
      p2 = { hunger := h1, hp := hp' } p1
      died =
        if hp' <= 0
           then if starving then Just Starved
                else if statusDamage p0.statuses > 0 then Just (OtherDeath "poison")
                else Nothing
           else Nothing
  in MkSurvivalResult p2 (statusMsgs ++ hungerMsgs) died
