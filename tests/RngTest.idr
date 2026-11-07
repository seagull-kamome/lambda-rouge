||| Smoke tests for the pure RNG wrapper.  These are deliberately small:
||| the point of M0 is to prove that the API and the rc2 build work.
module RngTest

import Data.List
import Data.String
import LambdaRogue.Core.Rng
import System
import System.Random.Xoroshiro128PlusPlus

check : String -> Bool -> IO ()
check name ok =
  if ok
     then putStrLn ("ok   " ++ name)
     else do
       putStrLn ("FAIL " ++ name)
       exitFailure

sameState : Rng -> Rng -> Bool
sameState a b = stateHex a == stateHex b

isNothing : Maybe a -> Bool
isNothing Nothing = True
isNothing (Just _) = False

checkUniform : Nat -> Bits64 -> Rng -> IO ()
checkUniform n bound g =
  check ("uniform " ++ show bound ++ " in 0 .. bound-1") (go n bound g)
  where
    go : Nat -> Bits64 -> Rng -> Bool
    go Z bound g = True
    go (S k) bound g =
      let (v, g') = uniform bound g
      in v < bound && go k bound g'

sameSequence : Nat -> Rng -> Gen -> Bool
sameSequence Z g gg = True
sameSequence (S k) g gg =
  let (a, g') = next64 g
      (b, gg') = genNext gg
  in a == b && sameSequence k g' gg'

chanceCount : Nat -> Int32 -> Rng -> (Nat, Rng)
chanceCount Z percent g = (0, g)
chanceCount (S k) percent g =
  let (b, g') = chance percent g
      (n, g'') = chanceCount k percent g'
  in (if b then S n else n, g'')

public export
run : IO ()
run = do
  let g0 = fromSeed 0

  check "matches rc2base Gen (seed 0)"
    (sameSequence 100 (fromSeed 0) (mkGen 0))
  check "matches rc2base Gen (seed 1)"
    (sameSequence 100 (fromSeed 1) (mkGen 1))
  check "matches rc2base Gen (seed 0x0123456789abcdef)"
    (sameSequence 100 (fromSeed 0x0123456789abcdef) (mkGen 0x0123456789abcdef))
  check "matches rc2base Gen (seed max)"
    (sameSequence 100 (fromSeed 0xffffffffffffffff) (mkGen 0xffffffffffffffff))

  check "golden vector: seed 0 initial state"
    (stateHex g0 == "e220a8397b1dcdaf6e789e6aa1b965f4")
  check "golden vector: seed 0 first two outputs and states"
    (let (v0, g1) = next64 g0
         (v1, g2) = next64 g1
     in v0 == 8027914721839836897
        && stateHex g1 == "dd7ca68781b65e603daa4a85b8c58365"
        && v1 == 13805533416164201645
        && stateHex g2 == "dc507880d4dcde6923973dd05e0d6ec0")

  check "state hex is 32 chars" (length (stateHex g0) == 32)
  check "state round-trip"
    (case stateFromHex (stateHex g0) of
       Just g => sameState g g0
       Nothing => False)
  check "state rejects short input" (isNothing (stateFromHex (replicate 31 '0')))
  check "state rejects long input" (isNothing (stateFromHex (stateHex g0 ++ "0")))
  check "state rejects uppercase" (isNothing (stateFromHex (replicate 32 'A')))
  check "state rejects non-hex" (isNothing (stateFromHex (replicate 32 'g')))

  let (v64, g64) = next64 g0
      (v32, g32) = next32 g0
  check "next32 is the low half of next64" (v32 == cast v64 && sameState g64 g32)

  check "uniform 0 does not consume" (sameState (snd (uniform 0 g0)) g0)
  check "uniform 1 does not consume" (sameState (snd (uniform 1 g0)) g0)
  checkUniform 1000 2 g0
  checkUniform 1000 3 g0
  checkUniform 1000 100 g0
  checkUniform 1000 1000 g0

  check "roll 0d6 does not consume" (fst (roll 0 6 g0) == 0 && sameState (snd (roll 0 6 g0)) g0)
  check "roll 2d6 is in 2 .. 12"
    (let (r, _) = roll 2 6 g0 in r >= 2 && r <= 12)
  check "roll with no faces does not consume" (sameState (snd (roll 1 0 g0)) g0)

  check "chance 0 does not consume" (fst (chance 0 g0) == False && sameState (snd (chance 0 g0)) g0)
  check "chance 100 does not consume" (fst (chance 100 g0) == True && sameState (snd (chance 100 g0)) g0)
  let (hits, _) = chanceCount 10000 50 g0
  check "chance 50 is near half" (hits > 4500 && hits < 5500)

  check "pick [] does not consume" (isNothing (fst (pick {a=Int} [] g0)) && sameState (snd (pick {a=Int} [] g0)) g0)
  let (picked, _) = pick [1, 2, 3] g0
  check "pick returns a member"
    (case picked of
       Just x => elem x [1, 2, 3]
       Nothing => False)

  let xs = the (List Int) [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
      (ys, _) = shuffle xs g0
      (ys2, _) = shuffle xs g0
  check "shuffle keeps the length" (length ys == length xs)
  check "shuffle keeps the elements" (sort ys == sort xs)
  check "shuffle is deterministic" (ys == ys2)
  check "shuffle [] does not consume" (sameState (snd (shuffle {a=Int} [] g0)) g0)
  check "shuffle [x] does not consume" (sameState (snd (shuffle [1] g0)) g0)

  putStrLn "rng tests passed"
