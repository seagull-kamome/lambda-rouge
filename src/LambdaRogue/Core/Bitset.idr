||| A fixed-size bitset for the 80x22 map.
|||
||| Bit `y * 80 + x` belongs to cell `(x, y)`.  The module deliberately
||| does not import `Core.Types`: `Types` imports this module, and keeping
||| the dependency one-way avoids a cycle.  Coordinates are therefore plain
||| `Int32` arguments.
module LambdaRogue.Core.Bitset

import Data.Bits
import Data.Fin
import Data.Vect

%default covering

public export
Bitset : Type
Bitset = Vect 28 Bits64

public export
empty : Bitset
empty = replicate 28 (the Bits64 0)

wordOf : Int32 -> Int32 -> Maybe (Fin 28, Fin 64)
wordOf x y =
  let idx = cast y * 80 + cast x
      w = idx `div` 64
      b = idx `mod` 64
  in case natToFin (integerToNat (cast w)) 28 of
       Just wi => case natToFin (integerToNat (cast b)) 64 of
                    Just bi => Just (wi, bi)
                    Nothing => Nothing
       Nothing => Nothing

||| Set the bit of `(x, y)`.  Out-of-map coordinates are ignored.
public export
setBit : (x, y : Int32) -> Bitset -> Bitset
setBit x y bs =
  if x < 0 || x >= 80 || y < 0 || y >= 22
     then bs
     else case wordOf x y of
            Nothing => bs
            Just (wi, b) =>
              replaceAt wi (index wi bs .|. (the Bits64 1 `shiftL` b)) bs

||| Is the bit of `(x, y)` set?  Out-of-map coordinates are `False`.
public export
getBit : (x, y : Int32) -> Bitset -> Bool
getBit x y bs =
  if x < 0 || x >= 80 || y < 0 || y >= 22
     then False
     else case wordOf x y of
            Nothing => False
            Just (wi, b) => (index wi bs .&. (the Bits64 1 `shiftL` b)) /= 0

public export
union : Bitset -> Bitset -> Bitset
union = zipWith (.|.)

public export
count : Bitset -> Nat
count = foldl (\acc, w => acc + popCount w) 0

hexDigit : Char -> Maybe Bits64
hexDigit c =
  if c >= '0' && c <= '9'
     then Just (cast (ord c - ord '0'))
     else if c >= 'a' && c <= 'f'
             then Just (cast (ord c - ord 'a' + 10))
             else Nothing

parseWord : List Char -> Maybe (Bits64, List Char)
parseWord cs = go 16 0 cs
  where
    go : Nat -> Bits64 -> List Char -> Maybe (Bits64, List Char)
    go Z acc rest = Just (acc, rest)
    go (S k) acc [] = Nothing
    go (S k) acc (c :: cs) =
      case hexDigit c of
        Nothing => Nothing
        Just v => go k (acc * 16 + v) cs

||| Parse the 448-character form produced by `gameDigest`'s `bitsetCode`.
public export
fromHex : String -> Maybe Bitset
fromHex s = do
  words <- parseWords 28 (unpack s) []
  toVect 28 words
  where
    parseWords : Nat -> List Char -> List Bits64 -> Maybe (List Bits64)
    parseWords Z [] acc = Just (reverse acc)
    parseWords Z (_ :: _) _ = Nothing
    parseWords (S k) cs acc =
      case parseWord cs of
        Nothing => Nothing
        Just (w, rest) => parseWords k rest (w :: acc)

