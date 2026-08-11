extends Resource
class_name SaveGame

# A player save slot (#144): one mid-battle board snapshot plus the save-file facts that do not
# belong on the board itself. mission_path is the origin mission -- what Restart (and F2) return
# to after a resume. version stamps the build that wrote the slot, for triaging old saves.

@export var scenario: ScenarioData
@export var mission_path := ""
@export var saved_at := 0     # unix seconds, for the slot list's timestamp
@export var version := ""     # Build.version() at save time
