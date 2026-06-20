extends Object
class_name Experiments

## Experiment / feature-flag harness — see docs/design/experiments.md.
##
## Declare a flag in `Flag`, give it metadata in `DEFS`, read it anywhere with
## `Experiments.is_on(Experiments.Flag.X)`, and toggle it from the Experiments dev tab.
## State persists to user://experiments.cfg, keyed by the flag's NAME.
##
## Unlike Stats.Stat / Elemental.Element, this enum is intentionally NOT append-only:
## experiment flags are meant to be CULLED. When you promote a feature (keep it) or kill
## it (drop it), delete the flag here and remove its reads. Nothing in saved game content
## (.tres) ever references a Flag value — only the dev-only cfg does, and that's keyed by
## name, so deleting/reordering flags can't corrupt saved resources.

enum Flag {
	EXAMPLE_FLAG,
}

# Per-flag metadata. Literal-only, so it can be a compile-time const (like STAT_DEFAULTS).
#   title   — label shown on the toggle
#   desc    — one-line explanation under it
#   default — value when the flag has never been toggled (no cfg entry)
const DEFS := {
	Flag.EXAMPLE_FLAG: {
		"title": "Example flag",
		"desc": "Throwaway sample proving the harness end-to-end. Safe to delete.",
		"default": false,
	},
}

const CONFIG_SECTION := "experiments"

# Where toggles persist. A static var (not const) so tests can redirect it to a temp file.
static var config_path := "user://experiments.cfg"
# Tests flip this false to stay fully in-memory (no disk I/O).
static var persistence_enabled := true

# Runtime on/off state, keyed by Flag. `static var` => one instance for the whole run,
# no autoload needed (mirrors how Stats / Elemental are class-level statics).
static var _state: Dictionary[Flag, bool] = {}
static var _loaded := false

# --- read / write API ---

static func is_on(flag: Flag) -> bool:
	if not _loaded:
		load_state()
	if _state.has(flag):
		return _state[flag]
	return default_of(flag)

static func set_on(flag: Flag, value: bool) -> void:
	_state[flag] = value
	save_state()

static func toggle(flag: Flag) -> bool:
	var value := not is_on(flag)
	set_on(flag, value)
	return value

static func reset_all() -> void:
	_state.clear()
	save_state()

# --- registry introspection (used by the dev tab) ---

static func all_flags() -> Array:
	return DEFS.keys()

static func title_of(flag: Flag) -> String:
	return str(DEFS[flag]["title"])

static func desc_of(flag: Flag) -> String:
	return str(DEFS[flag]["desc"])

static func default_of(flag: Flag) -> bool:
	return bool(DEFS[flag]["default"])

# --- persistence (keyed by enum NAME for resilience + a human-readable cfg) ---

static func load_state() -> void:
	_loaded = true
	_state.clear()
	if not persistence_enabled:
		return
	var cfg := ConfigFile.new()
	if cfg.load(config_path) != OK:
		return
	for flag in DEFS:
		var key: String = Flag.keys()[flag]
		if cfg.has_section_key(CONFIG_SECTION, key):
			_state[flag] = bool(cfg.get_value(CONFIG_SECTION, key))

static func save_state() -> void:
	if not persistence_enabled:
		return
	var cfg := ConfigFile.new()
	for flag in _state:
		cfg.set_value(CONFIG_SECTION, Flag.keys()[flag], _state[flag])
	cfg.save(config_path)

# --- test seam ---

## Wipe runtime state and skip disk I/O so suites stay hermetic. Call in before_test().
static func reset_for_test() -> void:
	persistence_enabled = false
	config_path = "user://experiments_test.cfg"
	_state.clear()
	_loaded = true
