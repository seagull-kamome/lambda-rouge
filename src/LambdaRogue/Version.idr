||| Version strings shared by the executable, the save schema and the
||| replay schema.  Keep this module free of `IO` and `termui`.
module LambdaRogue.Version

%default total

public export
version : String
version = "0.1.0"

public export
saveSchema : String
saveSchema = "lambda-rogue.save.v1"

public export
replaySchema : String
replaySchema = "lambda-rogue.replay.v1"
