||| Persistence tests for scores, replays, shared codecs and file IO.
|||
||| These tests use explicit temporary paths for the file cases; the
||| production helpers choose the XDG data directory themselves and are
||| exercised only through `Paths.joinPath` here.
module PersistTest

import Data.Bits
import Data.List
import Data.Maybe
import Data.String
import Data.Vect
import LambdaRogue.App.Model
import LambdaRogue.Core.Bitset
import LambdaRogue.Core.Dungeon
import LambdaRogue.Core.Game
import LambdaRogue.Core.Replay
import LambdaRogue.Core.Rng
import LambdaRogue.Core.Types
import LambdaRogue.Persist.Codec
import LambdaRogue.Persist.Json
import LambdaRogue.Persist.Paths
import LambdaRogue.Persist.Replay
import LambdaRogue.Persist.Save
import LambdaRogue.Persist.Score
import LambdaRogue.Version
import Language.JSON
import System
import System.File

%default covering

check : String -> Bool -> IO ()
check name ok =
  if ok
     then putStrLn ("ok   " ++ name)
     else do
       putStrLn ("FAIL " ++ name)
       exitFailure

removeIfPresent : String -> IO ()
removeIfPresent path = do
  _ <- removeFile path
  pure ()

sameScore : Score -> Score -> Bool
sameScore a b =
  a.seed == b.seed && a.depth == b.depth && a.level == b.level
  && a.exp == b.exp && a.gold == b.gold && a.turns == b.turns
  && a.result == b.result

scoreWon : Score
scoreWon = MkScore 0x0123456789abcdef 7 5 123 87 1240 Won

scoreDead : Score
scoreDead = MkScore 0xdeadbeefcafebabe 3 2 10 5 99 (Dead (KilledBy Dragon))

allStatusKinds : List StatusKind
allStatusKinds =
  [ Confused, Blinded, Hasted, SeeInvisible, DetectMonsters, DetectFood
  , DetectMagic, Invisible, Poisoned, Held, Slowed, Paralyzed, Scared
  , Sleeping, Hallucinating, Levitated, ConfuseNext
  ]

allMonsterStates : List MonsterState
allMonsterStates = [Asleep, Awake, Chasing, Fleeing]

allMonsterKinds : List MonsterKind
allMonsterKinds =
  [ Aquator, Bat, Centaur, Dragon, Emu, VenusFlytrap, Griffin
  , Hobgoblin, IceMonster, Jabberwock, Kestrel, Leprechaun, Medusa
  , Nymph, Orc, Phantom, Quagga, Rattlesnake, Snake, Troll
  , BlackUnicorn, Vampire, Wraith, Xeroc, Yeti, Zombie
  ]

allTrapKinds : List TrapKind
allTrapKinds =
  [ TrapDoor, ArrowTrap, Sleep, Bear, Teleport, DartTrap, Rust, Mysterious ]

allMessageKinds : List MessageKind
allMessageKinds = [CombatMsg, ItemMsg, SystemMsg, WarningMsg, StoryMsg]

allTiles : List Tile
allTiles =
  [ Rock, Floor, Corridor
  , Door Open, Door Closed, Door Secret, Door Locked
  , Stairs Up, Stairs Down
  ]

allDirs : List Dir
allDirs = [N, NE, E, SE, S, SW, W, NW]

replaySeed : Bits64
replaySeed = 0x0123456789abcdef

replayCommandsList : List Command
replayCommandsList =
  [ Move N, Move NE, Move E, Move SE, Move S, Move SW, Move W, Move NW
  , Wait, Search, PickUp
  , Quaff 1, Read 2, Eat 3, Wield 4, Wear 5, PutOnRing 6, TakeOff 7, Drop 8
  , Throw 9 SE, Zap 10 NW, Descend, Ascend
  ]

replayRecord : Replay
replayRecord = MkReplay replaySeed (reverse replayCommandsList)

public export
run : IO ()
run = do
  check "joinPath adds a slash"
    (joinPath "/data" "settings.json" == "/data/settings.json")
  check "joinPath keeps an existing slash"
    (joinPath "/data/" "settings.json" == "/data/settings.json")

  check "seedFromHex parses a 16-digit seed"
    (seedFromHex "0123456789abcdef" == Just 0x0123456789abcdef)
  check "seedFromHex round-trips seedHex"
    (seedFromHex (seedHex 0xdeadbeefcafebabe) == Just 0xdeadbeefcafebabe)
  check "seedFromHex rejects short input"
    (isNothing (seedFromHex "0123456789abcde"))
  check "seedFromHex rejects long input"
    (isNothing (seedFromHex "0123456789abcdef0"))
  check "seedFromHex rejects uppercase digits"
    (isNothing (seedFromHex "0123456789ABCDEF"))
  check "seedFromHex rejects non-hex digits"
    (isNothing (seedFromHex "g123456789abcdef"))

  check "asInt32 accepts an integral JSON number"
    (asInt32 (JNumber 42) == Just 42)
  check "asInt32 rejects a fractional JSON number"
    (isNothing (asInt32 (JNumber 1.5)))
  check "asBool rejects a JSON string"
    (isNothing (asBool (JString "true")))
  check "field finds a named member"
    (field "x" (JObject [("x", JNumber 1)]) == Just (JNumber 1))
  check "arrayOf rejects a non-array"
    (isNothing (arrayOf asInt32 (JNumber 1)))
  check "arrayOf validates every element"
    (arrayOf asInt32 (JArray [JNumber 1, JNumber 2]) == Just [1, 2])

  check "coordinates round-trip through JSON"
    (coordFromJSON (coordToJSON (MkCoord 7 9)) == Just (MkCoord 7 9))
  check "a coordinate without y is rejected"
    (isNothing (coordFromJSON (JObject [("x", JNumber 1)])))
  check "all directions round-trip"
    (all (\d => dirFromText (dirText d) == Just d) allDirs)
  check "all status kinds round-trip"
    (all (\k => statusKindFromText (statusKindText k) == Just k)
         allStatusKinds)
  check "a status round-trips through JSON"
    (statusFromJSON (statusToJSON (MkStatus Confused 3))
       == Just (MkStatus Confused 3))
  check "an unknown status is rejected"
    (isNothing (statusKindFromText "dancing"))
  check "all monster states round-trip"
    (all (\s => monsterStateFromText (monsterStateText s) == Just s)
         allMonsterStates)
  check "all monster kinds round-trip"
    (all (\k => monsterKindFromText (monsterKindText k) == Just k)
         allMonsterKinds)
  check "an unknown monster is rejected"
    (isNothing (monsterKindFromText "goblin"))
  check "all item kinds round-trip"
    (not (null allItemKinds)
     && all (\k => itemKindFromText (itemKindText k) == Just k) allItemKinds)
  check "an unknown item is rejected"
    (isNothing (itemKindFromText "wand of fireworks"))
  check "all trap kinds round-trip"
    (all (\k => trapKindFromText (trapKindText k) == Just k) allTrapKinds)
  check "an unknown trap is rejected"
    (isNothing (trapKindFromText "pit"))
  check "all message kinds round-trip"
    (all (\k => messageKindFromText (messageKindText k) == Just k)
         allMessageKinds)
  check "an unknown message kind is rejected"
    (isNothing (messageKindFromText "chat"))
  check "all tiles round-trip"
    (all (\t => tileFromText (tileText t) == Just t) allTiles)
  check "an unknown tile is rejected"
    (isNothing (tileFromText '?'))
  check "all death causes round-trip"
    (all (\c => deathCauseFromJSON (deathCauseToJSON c) == Just c)
         (the (List DeathCause)
              [ KilledBy Dragon, KilledByTrap Bear, Starved, Drained
              , OtherDeath "fell into a pit"
              ]))
  check "a won result round-trips"
    (gameOverFromJSON (gameOverToJSON Won) == Just Won)
  check "a dead result round-trips"
    (gameOverFromJSON (gameOverToJSON (Dead Starved))
       == Just (Dead Starved))
  check "an unknown result is rejected"
    (isNothing (gameOverFromJSON (JObject [("result", JString "draw")])))

  let zeroBitsetHex : String
      zeroBitsetHex = concat (the (List String)
                                   (replicate 28 "0000000000000000"))
      oneBitsetHex : String
      oneBitsetHex = "0000000000000001"
                     ++ concat (the (List String)
                                     (replicate 27 "0000000000000000"))
  check "fromHex parses 28 zero words"
    (fromHex zeroBitsetHex == Just (the Bitset (replicate 28 0)))
  check "fromHex parses the low bit of the first word"
    (fromHex oneBitsetHex == Just (the Bitset (1 :: replicate 27 0)))
  check "fromHex rejects a short string"
    (isNothing (fromHex "00"))
  check "fromHex rejects a long string"
    (isNothing (fromHex (zeroBitsetHex ++ "0")))
  check "fromHex rejects uppercase digits"
    (isNothing (fromHex ("000000000000000A"
                         ++ concat (the (List String)
                                         (replicate 27 "0000000000000000")))))

  check "a score round-trips through JSON"
    (case scoreFromJSON (scoreToJSON scoreWon) of
       Just s => sameScore s scoreWon
       Nothing => False)
  check "a dead score keeps its cause"
    (case scoreFromJSON (scoreToJSON scoreDead) of
       Just s => sameScore s scoreDead
       Nothing => False)
  check "a score line round-trips"
    (case scoreFromLine (scoreToLine scoreWon) of
       Just s => sameScore s scoreWon
       Nothing => False)
  check "a score line names its schema"
    (isInfixOf (unpack scoreSchema) (unpack (scoreToLine scoreWon)))
  check "a score line without fields is rejected"
    (isNothing (scoreFromLine "{\"schema\":\"lambda-rogue.score.v1\"}"))
  check "a non-JSON score line is rejected"
    (isNothing (scoreFromLine "not json"))
  let wrongScoreSchema : JSON
      wrongScoreSchema =
        JObject
          [ ("schema", JString "lambda-rogue.score.v2")
          , ("seed", JString "0000000000000000")
          , ("depth", JNumber 1)
          , ("level", JNumber 1)
          , ("exp", JNumber 0)
          , ("gold", JNumber 0)
          , ("turns", JNumber 0)
          , ("result", gameOverToJSON Won)
          ]
  check "an unknown score schema is rejected"
    (isNothing (scoreFromJSON wrongScoreSchema))
  check "scoresFromText skips blank and damaged lines"
    (map (\s => s.seed)
         (scoresFromText (scoreToLine scoreWon ++ "\nnot-json\n\n"
                          ++ scoreToLine scoreDead ++ "\n"))
       == [scoreWon.seed, scoreDead.seed])

  let scorePath : String
      scorePath = "/tmp/opencode/lambda-rogue-persist-scores.jsonl"
  removeIfPresent scorePath
  wroteWon <- appendScoreAt scorePath scoreWon
  wroteDead <- appendScoreAt scorePath scoreDead
  loadedScores <- loadScoresAt scorePath
  check "score append writes and loads newest first"
    (wroteWon && wroteDead
     && map (\s => s.seed) loadedScores == [scoreDead.seed, scoreWon.seed])
  _ <- writeFile scorePath
         (scoreToLine scoreWon ++ "\n{broken}\n" ++ scoreToLine scoreDead
          ++ "\n")
  loadedMixed <- loadScoresAt scorePath
  check "a damaged line in a score file is skipped"
    (map (\s => s.seed) loadedMixed == [scoreDead.seed, scoreWon.seed])
  removeIfPresent scorePath
  removeIfPresent "/tmp/opencode/lambda-rogue-persist-missing-scores.jsonl"
  missingScores <- loadScoresAt
                     "/tmp/opencode/lambda-rogue-persist-missing-scores.jsonl"
  check "a missing score file loads as an empty history"
    (null missingScores)

  check "a replay round-trips through JSON"
    (case replayFromJSON (replayToJSON replayRecord) of
       Just r => r.seed == replaySeed
                 && replayCommands r == replayCommandsList
       Nothing => False)
  check "a replay round-trips through text"
    (case replayFromText (replayToText replayRecord) of
       Just r => replayCommands r == replayCommandsList
       Nothing => False)
  check "replay output names its schema"
    (isInfixOf (unpack replayFileSchema) (unpack (replayToText replayRecord)))
  check "replay output names the game version"
    (isInfixOf (unpack version) (unpack (replayToText replayRecord)))
  let wrongReplaySchema : JSON
      wrongReplaySchema =
        JObject [("schema", JString "lambda-rogue.replay.v2")]
  check "an unknown replay schema is rejected"
    (isNothing (replayFromJSON wrongReplaySchema))
  let wrongReplayVersion : JSON
      wrongReplayVersion =
        JObject
          [ ("schema", JString replayFileSchema)
          , ("gameVersion", JString "9.9.9")
          , ("seed", JString "0123456789abcdef")
          , ("commands", JArray [])
          ]
  check "a replay from another game version is rejected"
    (isNothing (replayFromJSON wrongReplayVersion))
  let unknownReplayCommand : JSON
      unknownReplayCommand =
        JObject
          [ ("schema", JString replayFileSchema)
          , ("gameVersion", JString version)
          , ("seed", JString "0123456789abcdef")
          , ("commands", JArray [JObject [("type", JString "Teleport")]])
          ]
  check "an unknown replay command is rejected"
    (isNothing (replayFromJSON unknownReplayCommand))
  let badReplayDirection : JSON
      badReplayDirection =
        JObject
          [ ("schema", JString replayFileSchema)
          , ("gameVersion", JString version)
          , ("seed", JString "0123456789abcdef")
          , ("commands", JArray
              [JObject [("type", JString "Move"), ("dir", JString "X")]])
          ]
  check "an invalid replay direction is rejected"
    (isNothing (replayFromJSON badReplayDirection))
  check "replay file names include the seed and timestamp"
    (replayFileName replayRecord 1700000000
       == "0123456789abcdef-1700000000.replay.json")

  let replayPath : String
      replayPath = "/tmp/opencode/lambda-rogue-persist-test.replay.json"
  removeIfPresent replayPath
  savedReplay <- saveReplayAt replayPath replayRecord
  loadedReplay <- loadReplayAt replayPath
  check "replay save and load round-trip"
    (savedReplay
     && (case loadedReplay of
           Just r => r.seed == replaySeed
                     && replayCommands r == replayCommandsList
           Nothing => False))
  _ <- writeFile replayPath "{not a replay"
  brokenReplay <- loadReplayAt replayPath
  check "a malformed replay file loads as Nothing"
    (isNothing brokenReplay)
  removeIfPresent replayPath
  removeIfPresent "/tmp/opencode/lambda-rogue-persist-missing.replay.json"
  missingReplay <- loadReplayAt
                     "/tmp/opencode/lambda-rogue-persist-missing.replay.json"
  check "a missing replay file loads as Nothing"
    (isNothing missingReplay)

  let g0 = newGame 42
      g0Digest = gameDigest g0
      stamp = "2026-11-04T12:00:00Z"
  check "a save names its schema, kind and version"
    (case saveToJSON Manual stamp g0 of
       JObject fields =>
         field "schema" (JObject fields) == Just (JString saveFileSchema)
         && field "kind" (JObject fields) == Just (JString "manual")
         && field "gameVersion" (JObject fields) == Just (JString version)
         && field "savedAt" (JObject fields) == Just (JString stamp)
       _ => False)
  check "a manual save round-trips through JSON"
    (case saveFromJSON (saveToJSON Manual stamp g0) of
       Just saved => saved.kind == Manual && saved.savedAt == stamp
                     && gameDigest saved.game == g0Digest
       Nothing => False)
  check "an autosave round-trips through text"
    (case saveFromText (saveToText Autosave stamp g0) of
       Just saved => saved.kind == Autosave
                     && gameDigest saved.game == g0Digest
       Nothing => False)
  let wrongSaveSchema : JSON
      wrongSaveSchema =
        JObject [ ("schema", JString "lambda-rogue.save.v2")
                , ("kind", JString "manual")
                , ("gameVersion", JString version)
                , ("savedAt", JString stamp)
                , ("game", gameToJSON g0)
                ]
  check "an unknown save schema is rejected"
    (isNothing (saveFromJSON wrongSaveSchema))
  let wrongSaveVersion : JSON
      wrongSaveVersion =
        JObject [ ("schema", JString saveFileSchema)
                , ("kind", JString "manual")
                , ("gameVersion", JString "9.9.9")
                , ("savedAt", JString stamp)
                , ("game", gameToJSON g0)
                ]
  check "a save from another game version is rejected"
    (isNothing (saveFromJSON wrongSaveVersion))
  let badNextId : JSON
      badNextId =
        case gameToJSON g0 of
          JObject gs =>
            JObject (("nextItemId", JNumber 0)
                     :: filter (\p => fst p /= "nextItemId") gs)
          _ => JNull
      badCounterSave : JSON
      badCounterSave =
        JObject [ ("schema", JString saveFileSchema)
                , ("kind", JString "manual")
                , ("gameVersion", JString version)
                , ("savedAt", JString stamp)
                , ("game", badNextId)
                ]
  check "a save with an invalid item counter is rejected"
    (isNothing (saveFromJSON badCounterSave))
  let badInventory : JSON
      badInventory =
        case gameToJSON g0 of
          JObject gs =>
            JObject (map (\p => if fst p == "player"
                                   then (fst p, case snd p of
                                                  JObject ps =>
                                                    JObject
                                                      (("inventory",
                                                         JArray [JNumber 999])
                                                       :: filter
                                                            (\q => fst q /= "inventory")
                                                            ps)
                                                  _ => snd p)
                                   else p) gs)
          _ => JNull
      badInventorySave : JSON
      badInventorySave =
        JObject [ ("schema", JString saveFileSchema)
                , ("kind", JString "manual")
                , ("gameVersion", JString version)
                , ("savedAt", JString stamp)
                , ("game", badInventory)
                ]
  check "a save with a missing inventory item is rejected"
    (isNothing (saveFromJSON badInventorySave))
  check "a save without a savedAt value is rejected"
    (isNothing (saveFromJSON
      (JObject [ ("schema", JString saveFileSchema)
               , ("kind", JString "manual")
               , ("gameVersion", JString version)
               , ("savedAt", JString "")
               , ("game", gameToJSON g0)
               ])))

  let savePath : String
      savePath = "/tmp/opencode/lambda-rogue-persist-save.json"
  removeIfPresent savePath
  savedManual <- saveGameAt savePath Manual g0
  loadedManual <- loadSaveAt savePath
  check "a save file round-trips through the atomic writer"
    (savedManual
     && (case loadedManual of
           Just saved => saved.kind == Manual
                         && gameDigest saved.game == g0Digest
           Nothing => False))
  savedAuto <- saveGameAt savePath Autosave g0
  loadedAuto <- loadSaveAt savePath
  backup <- readFile (savePath ++ ".bak")
  check "a replaced save keeps the previous file as .bak"
    (savedAuto && (case backup of
                     Left _ => False
                     Right _ => True)
     && (case loadedAuto of
           Just saved => saved.kind == Autosave
           Nothing => False))
  let unicodePath : String
      unicodePath = "/tmp/opencode/lambda-rogue-persist-unicode.json"
      unicodeGame : Game
      unicodeGame =
        { messages := [MkMessage 0 SystemMsg "回復しました"] } g0
  removeIfPresent unicodePath
  unicodeSaved <- saveGameAt unicodePath Manual unicodeGame
  unicodeLoaded <- loadSaveAt unicodePath
  check "a save preserves non-ASCII messages"
    (unicodeSaved
     && (case unicodeLoaded of
           Just saved => map (\m => m.text) saved.game.messages
                           == ["回復しました"]
           Nothing => False))
  removeIfPresent unicodePath
  removeIfPresent (unicodePath ++ ".bak")
  _ <- writeFile savePath "{broken save"
  brokenSave <- loadSaveAt savePath
  check "a malformed save file loads as Nothing"
    (isNothing brokenSave)
  removeIfPresent savePath
  removeIfPresent (savePath ++ ".bak")
  removeIfPresent "/tmp/opencode/lambda-rogue-persist-missing-save.json"
  missingSave <- loadSaveAt
                   "/tmp/opencode/lambda-rogue-persist-missing-save.json"
  check "a missing save file loads as Nothing"
    (isNothing missingSave)

  let lockPath : String
      lockPath = "/tmp/opencode/lambda-rogue-persist-session.lock"
  removeIfPresent lockPath
  firstLock <- acquireLockAt lockPath
  lockText <- readFile lockPath
  check "a session lock records the owning pid"
    (firstLock
     && (case lockText of
           Left _ => False
           Right text =>
             case parse text >>= field "pid" >>= asInt32 of
               Just _ => True
               Nothing => False))
  secondLock <- acquireLockAt lockPath
  check "a live session lock is not stolen"
    (not secondLock)
  releaseLockAt lockPath
  releasedLock <- readFile lockPath
  check "releasing a session lock removes it"
    (case releasedLock of
       Left _ => True
       Right _ => False)
  _ <- writeFile lockPath
         "{\"pid\":999999,\"startedAt\":\"2026-11-04T12:00:00Z\"}\n"
  staleLock <- acquireLockAt lockPath
  check "a lock held by a dead process is reclaimed"
    staleLock
  releaseLockAt lockPath
  _ <- writeFile lockPath "not a lock\n"
  damagedLock <- acquireLockAt lockPath
  check "an unreadable session lock is reclaimed"
    damagedLock
  releaseLockAt lockPath

  putStrLn "persistence tests passed"
