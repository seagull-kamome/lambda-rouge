||| The single test executable for the whole suite.
|||
||| Building one executable avoids the per-test link failures this rc2
||| backend produces when several executables reuse the same TTC tree.
module TestRunner

import AnimationTest
import CombatTest
import CoreTest
import DungeonTest
import FuzzTest
import M3Test
import M4Test
import MapViewTest
import MouseTest
import PerfTest
import PersistTest
import PlaybackTest
import ReplayTest
import SettingsTest
import RngTest
import SubsTest
import ThemeTest
import ViewTest

%default covering

main : IO ()
main = do
  RngTest.run
  CoreTest.run
  DungeonTest.run
  AnimationTest.run
  CombatTest.run
  FuzzTest.run
  M3Test.run
  M4Test.run
  MapViewTest.run
  MouseTest.run
  ReplayTest.run
  SettingsTest.run
  PersistTest.run
  SubsTest.run
  ViewTest.run
  ThemeTest.run
  PerfTest.run
  PlaybackTest.run
  putStrLn "all tests passed"
