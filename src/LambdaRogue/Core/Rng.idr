||| The pure random-number API of the game core.
|||
||| The state is a 128-bit xoroshiro128++ state held as two `Bits64`
||| words.  It is deliberately our own value rather than
||| `System.Random.Xoroshiro128PlusPlus.Gen`: `Gen` is exported
||| abstractly (`export data Gen`), so its state cannot be read back for
||| a save file or a replay.  `tests/RngTest.idr` checks that this
||| implementation produces exactly the same sequence as rc2base's
||| `mkGen` / `genNext`, which is the reference for the algorithm.
|||
||| The algorithm is xoroshiro128++ 1.0 (Blackman & Vigna, public
||| domain); seeding is splitmix64, as in the reference implementation.
||| Nothing here uses `IO`.
module LambdaRogue.Core.Rng

import Data.Bits
import Data.Fin
import Data.List
import Data.Maybe
import Data.String
import Data.Vect
import Text.NumberFormat

%default covering

||| A 128-bit xoroshiro128++ state.
public export
record Rng where
  constructor MkRng
  s0, s1 : Bits64

public export
Eq Rng where
  MkRng a b == MkRng c d = a == c && b == d

splitmix64 : Bits64 -> (Bits64, Bits64)
splitmix64 state =
  let state' = state + 0x9e3779b97f4a7c15
      z1 = (state' `xor` (state' `shiftR` 30)) * 0xbf58476d1ce4e5b9
      z2 = (z1 `xor` (z1 `shiftR` 27)) * 0x94d049bb133111eb
  in (z2 `xor` (z2 `shiftR` 31), state')

||| The generator for a 64-bit seed: two splitmix64 steps fill the two
||| state words, exactly as `mkGen` does.
public export
fromSeed : Bits64 -> Rng
fromSeed seed =
  let (a, seed') = splitmix64 seed
      (b, _) = splitmix64 seed'
  in MkRng a b

rotl17, rotl49, rotl28 : Bits64 -> Bits64
rotl17 x = (x `shiftL` 17) .|. (x `shiftR` 47)
rotl49 x = (x `shiftL` 49) .|. (x `shiftR` 15)
rotl28 x = (x `shiftL` 28) .|. (x `shiftR` 36)

||| The next 64-bit output and the generator after that step.
public export
next64 : Rng -> (Bits64, Rng)
next64 (MkRng s0 s1) =
  let result = rotl17 (s0 + s1) + s0
      s1' = s1 `xor` s0
      s0' = rotl49 s0 `xor` s1' `xor` (s1' `shiftL` 21)
      s1'' = rotl28 s1'
  in (result, MkRng s0' s1'')

||| The low 32 bits of the next 64-bit output.
public export
next32 : Rng -> (Bits32, Rng)
next32 g = let (v, g') = next64 g in (cast v, g')

isPow2 : Bits64 -> Bool
isPow2 x = x /= 0 && (x .&. (x - 1)) == 0

||| A uniform value in `0 .. bound - 1`.
|||
||| `bound = 0` and `bound = 1` return 0 without consuming the generator.
||| A power-of-two bound is masked; any other bound uses rejection
||| sampling, so every result has exactly the same probability.
public export
uniform : (bound : Bits64) -> Rng -> (Bits64, Rng)
uniform 0 g = (0, g)
uniform 1 g = (0, g)
uniform bound g =
  if isPow2 bound
     then let (v, g') = next64 g in (v .&. (bound - 1), g')
     else reject g
  where
    threshold : Bits64
    threshold = (0 - bound) `mod` bound

    reject : Rng -> (Bits64, Rng)
    reject g =
      let (v, g') = next64 g
      in if v < threshold then reject g' else (v `mod` bound, g')

||| `n` dice with `sides` faces, returning their sum in `n .. n * sides`.
||| A non-positive count or number of faces returns 0 without consuming
||| the generator.
public export
roll : (n, sides : Int32) -> Rng -> (Int32, Rng)
roll n sides g =
  if n <= 0 || sides <= 0
     then (0, g)
     else go (cast n) 0 g
  where
    go : Nat -> Int32 -> Rng -> (Int32, Rng)
    go Z acc g = (acc, g)
    go (S k) acc g =
      let (v, g') = uniform (cast sides) g
      in go k (acc + cast v + 1) g'

||| True with probability `percent / 100`.  0 and 100 are decided
||| without consuming the generator.
public export
chance : (percent : Int32) -> Rng -> (Bool, Rng)
chance percent g =
  if percent <= 0
     then (False, g)
     else if percent >= 100
             then (True, g)
             else let (v, g') = uniform 100 g in (v < cast percent, g')

||| One element of a non-empty list.  The empty list returns `Nothing`
||| without consuming the generator.
public export
pick : List a -> Rng -> (Maybe a, Rng)
pick [] g = (Nothing, g)
pick xs g =
  let (i, g') = uniform (cast (length xs)) g
  in case natToFin (cast i) (length xs) of
       Just k => (Just (index' xs k), g')
       Nothing => (Nothing, g')

finLast : (n : Nat) -> Fin (S n)
finLast Z = FZ
finLast (S k) = FS (finLast k)

||| A `Fin (S n)` from `uniform`, which is in range by construction.
uniformFin : (n : Nat) -> Rng -> (Fin (S n), Rng)
uniformFin n g =
  let (x, g') = uniform (cast (S n)) g
  in case natToFin (cast x) (S n) of
       Just i => (i, g')
       Nothing => uniformFin n g'

||| Fisher-Yates: walk from the end, swap each position with a uniformly
||| chosen earlier position.  Every permutation has the same probability.
||| The empty and singleton lists do not consume the generator.
public export
shuffle : List a -> Rng -> (List a, Rng)
shuffle xs g =
  let v = fromList xs
      (v', g') = go (length xs) v g
  in (toList v', g')
  where
    go : (n : Nat) -> Vect n a -> Rng -> (Vect n a, Rng)
    go Z v g = (v, g)
    go (S k) v g =
      let (j, g1) = uniformFin k g
          lastIx = finLast k
          x = index j v
          y = index lastIx v
          v1 = replaceAt j y (replaceAt lastIx x v)
          (v2, g2) = go k (init v1) g1
      in (snoc v2 (index lastIx v1), g2)

||| The 128-bit state as 32 lowercase hexadecimal characters: `s0` then
||| `s1`, most significant nibble first.
public export
stateHex : Rng -> String
stateHex (MkRng s0 s1) = toHex s0 ++ toHex s1

||| A 64-bit run seed as 16 lowercase hexadecimal characters.  This is the
||| form used by save files, replays and seed sharing.
public export
seedHex : Bits64 -> String
seedHex = toHex

hexDigit : Char -> Maybe Bits32
hexDigit c =
  if c >= '0' && c <= '9'
     then Just (cast (ord c - ord '0'))
     else if c >= 'a' && c <= 'f'
             then Just (cast (ord c - ord 'a' + 10))
             else Nothing

parseWord : List Char -> Maybe (Bits32, List Char)
parseWord cs = go 8 0 cs
  where
    go : Nat -> Bits32 -> List Char -> Maybe (Bits32, List Char)
    go Z acc rest = Just (acc, rest)
    go (S k) acc [] = Nothing
    go (S k) acc (c :: cs) =
      case hexDigit c of
        Nothing => Nothing
        Just v => go k (acc * 16 + v) cs

||| Parse a 16-character lowercase hex seed produced by `seedHex`.
public export
seedFromHex : String -> Maybe Bits64
seedFromHex s =
  case parseWord (unpack s) of
    Nothing => Nothing
    Just (hi, cs1) =>
      case parseWord cs1 of
        Nothing => Nothing
        Just (lo, cs2) =>
          case cs2 of
            [] => Just ((cast hi `shiftL` 32) .|. cast lo)
            _ => Nothing

||| Parse a state produced by `stateHex`.  Exactly 32 lowercase hex
||| digits are required; anything else is `Nothing`.
public export
stateFromHex : String -> Maybe Rng
stateFromHex s =
  case parseWord (unpack s) of
    Nothing => Nothing
    Just (a, cs1) =>
      case parseWord cs1 of
        Nothing => Nothing
        Just (b, cs2) =>
          case parseWord cs2 of
            Nothing => Nothing
            Just (c, cs3) =>
              case parseWord cs3 of
                Nothing => Nothing
                Just (d, cs4) =>
                  case cs4 of
                    [] => Just (MkRng ((cast a `shiftL` 32) .|. cast b)
                                      ((cast c `shiftL` 32) .|. cast d))
                    _ => Nothing
