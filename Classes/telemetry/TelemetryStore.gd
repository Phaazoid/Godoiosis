extends Object
class_name TelemetryStore

# WHERE PLAYTEST DATA LIVES ON DISK (#53): the folder, the anonymous install id, and the file a
# mission run appends to. The RECORDER is MissionLog and the SUMMARY is MissionSummary; this is
# the only file that knows a path.
#
# A static class on PlayerSettings' shape, for its reason: a headless process has no player and
# writes nothing, so the suite drives the recorder fully in memory. persistence_enabled is the one
# switch and _static_init clears it headless; a case that wants real disk sets it back and points
# `root` at a scratch folder.
#
# ITS OWN cfg, deliberately NOT settings.cfg: PlayerSettings.save_state() writes a fresh ConfigFile,
# so a second section in that file would be dropped on the next settings write.
#
# The install id is the ONLY identity in the data -- random, generated once, never tied to a name,
# a path or an account. #53's privacy rule: no PII, ever.

const CONFIG_SECTION := "telemetry"
const INSTALL_ID_KEY := "install_id"

# Redirectable, so a suite can point the whole store at a scratch folder.
static var root := "user://telemetry/"
static var persistence_enabled := true
static var _install_id := ""


static func _static_init() -> void:
	if DisplayServer.get_name() == "headless":
		persistence_enabled = false


static func pending_dir() -> String:
	return root + "pending/"


# A run is a FOLDER, not a lone file (#53 slice 2) -- `user://reports/<stamp>/`'s exact shape, and
# for its reason: a run now carries a board snapshot beside its events, and the uploader already
# ships a folder through one ATTACHMENTS table.
static func run_dir(run_id: String) -> String:
	return pending_dir() + run_id + "/"


static func config_path() -> String:
	return root + "telemetry.cfg"


# Generated on first ask and kept for the life of the install. In memory only while persistence is
# off, so a headless run mints a fresh one per process rather than reading this machine's.
static func install_id() -> String:
	if _install_id != "":
		return _install_id
	if persistence_enabled:
		var cfg := ConfigFile.new()
		if cfg.load(config_path()) == OK and cfg.has_section_key(CONFIG_SECTION, INSTALL_ID_KEY):
			_install_id = str(cfg.get_value(CONFIG_SECTION, INSTALL_ID_KEY))
	if _install_id == "":
		_install_id = new_id()
		_write_key(INSTALL_ID_KEY, _install_id)
	return _install_id


# 16 hex characters off the CSPRNG. Not randi(): #53's standing rule is that randomness never
# enters combat unseeded, and an id drawn from the rules' own generator would blur that line.
static func new_id() -> String:
	return Crypto.new().generate_random_bytes(8).hex_encode()


# The file one run appends to, or null when nothing is written. WRITE truncates, and that is
# fine: a run id is unique.
static func open_run_file(run_id: String) -> FileAccess:
	if not persistence_enabled:
		return null
	DirAccess.make_dir_recursive_absolute(run_dir(run_id))
	return FileAccess.open(run_dir(run_id) + "events.jsonl", FileAccess.WRITE)


# THE REPLAY SEED (#53 slice 2): the board exactly as the battle started, beside its events.
#
# The name-based roster in `mission_start` cannot answer this and is not meant to -- a
# scenario-embedded weapon's template is inline and scenario-local, two attacks may share a
# display_name, and effective stats are a composed chain that cannot be inverted. A ScenarioData
# snapshot IS the state, through the #87 machinery a save slot already round-trips.
#
# BugReporter.report()'s three steps verbatim, and `take_over_path` is not optional: whoever writes
# a path claims it (#99), or every later load of that path serves the stale cache entry.
#
# DECLARED GAP: capture_scenario walks units_root, so the RESERVE is not in here. Harmless for
# replay (a reserve unit cannot act); what was OFFERED lives in the JSON roster.
static func save_board(run_id: String, scenario: ScenarioData) -> bool:
	if not persistence_enabled or scenario == null:
		return false
	DirAccess.make_dir_recursive_absolute(run_dir(run_id))
	var path := run_dir(run_id) + "board.tres"
	scenario.take_over_path(path)
	var err := ResourceSaver.save(scenario, path)
	if err != OK:
		push_error("Telemetry: could not write board.tres (error %s)" % err)
		return false
	return true


# Read-modify-write, so a later key (the notice flag, #53 slice 2) shares the file.
static func _write_key(key: String, value: Variant) -> void:
	if not persistence_enabled:
		return
	DirAccess.make_dir_recursive_absolute(root)
	var cfg := ConfigFile.new()
	cfg.load(config_path())   # a missing file is the first-run case, not an error
	cfg.set_value(CONFIG_SECTION, key, value)
	cfg.save(config_path())


# --- test seam ---

## Wipe runtime state and skip disk I/O so suites stay hermetic. Call in before_test().
static func reset_for_test() -> void:
	persistence_enabled = false
	root = "user://__telemetry_test/"
	_install_id = ""
