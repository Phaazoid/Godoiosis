extends Object
class_name Experiments

## Experiment / feature-flag harness — see docs/design/experiments.md.
##
## Declare a flag in `Flag`, give it metadata in `DEFS`, read it anywhere with
## `Experiments.is_on(Experiments.Flag.X)`, and toggle it from the Experiments dev tab.
## A flag whose DEFS entry carries `options` is a CHOICE instead: an index into that list, read
## with `choice_of` -- for comparing more than two versions of one thing side by side.
## State persists to user://experiments.cfg, keyed by the flag's NAME.
##
## Unlike Stats.Stat / Elemental.Element, this enum is intentionally NOT append-only:
## experiment flags are meant to be CULLED. When you promote a feature (keep it) or kill
## it (drop it), delete the flag here and remove its reads. Nothing in saved game content
## (.tres) ever references a Flag value — only the dev-only cfg does, and that's keyed by
## name, so deleting/reordering flags can't corrupt saved resources.

enum Flag {
	EXAMPLE_FLAG,
	DIORAMA_BYSTANDERS,
	DIORAMA_CAMERA_CUTS_AHEAD,
	ZONE_LOOK,
}

# Per-flag metadata. Literal-only, so it can be a compile-time const (like STAT_DEFAULTS).
#   title   — label shown on the toggle
#   desc    — one-line explanation under it
#   default — value when the flag has never been toggled (no cfg entry); an index for a choice
#   options — present only on a CHOICE: the labels, in index order
const DEFS := {
	Flag.EXAMPLE_FLAG: {
		"title": "Example flag",
		"desc": "Throwaway sample proving the harness end-to-end. Safe to delete.",
		"default": false,
	},
	Flag.DIORAMA_CAMERA_CUTS_AHEAD: {
		"title": "The camera cuts ahead to the diorama",
		"desc": "On: behind the white-out the camera CUTS to the empty sky and waits there, so you watch the fight assemble tile by tile out of nothing. Off: it travels up with the tear-out, so you watch the board come apart instead. #521's feels test -- pick one and the loser gets deleted.",
		"default": true,
	},
	Flag.DIORAMA_BYSTANDERS: {
		"title": "Diorama keeps its bystanders",
		"desc": "Tear out the ground under every unit, not just the fight's, so the battle diorama keeps its spatial context. #521's feels test -- pick one and the loser gets deleted.",
		"default": false,
	},
	Flag.ZONE_LOOK: {
		"title": "Zone look",
		"desc": "How an objective zone is drawn on the board (#955). Tint: today's flat wash. A: a solid, dark-outlined band on the zone's inside edge. B: a glow fading inward from the edge. C: B's glow with a low wall of light standing just inside the edge. The emblems draw under every look. Pick one and the rest get deleted.",
		"default": 0,
		"options": ["Tint (today)", "A: painted edge", "B: soft rim", "C: soft rim + light wall"],
	},
}

const CONFIG_SECTION := "experiments"

# Where toggles persist. A static var (not const) so tests can redirect it to a temp file.
static var config_path := "user://experiments.cfg"
# Tests flip this false to stay fully in-memory (no disk I/O); _static_init clears it headlessly.
static var persistence_enabled := true

# Runtime state, keyed by Flag: a bool, or an int index for a choice. `static var` => one
# instance for the whole run, no autoload needed (mirrors how Stats / Elemental are class-level
# statics).
static var _state: Dictionary[Flag, Variant] = {}
static var _loaded := false

# Nobody is at the keyboard in a headless run, so there is no dev whose flags these are -- the
# suite reads the DEFAULTS rather than this machine's cfg. PlayerSettings' rule, same shape (#449).
static func _static_init() -> void:
	if DisplayServer.get_name() == "headless":
		persistence_enabled = false

# --- read / write API ---

# The generic read, for a caller walking DEFS: a bool, or a choice's index.
static func value_of(flag: Flag) -> Variant:
	if not _loaded:
		load_state()
	if _state.has(flag):
		return _state[flag]
	return DEFS[flag]["default"]

# The on/off facades REFUSE a choice (PlayerSettings' #647 rule): bool(1) and bool(2) are both
# true, so a choice read as on/off is silently wrong, and one written as on/off persists wrong.
static func is_on(flag: Flag) -> bool:
	if is_choice(flag):
		push_error("Experiments.is_on: %s is a choice -- read it with choice_of" % Flag.keys()[flag])
		return false
	return bool(value_of(flag))

static func set_on(flag: Flag, value: bool) -> void:
	if is_choice(flag):
		push_error("Experiments.set_on: %s is a choice -- write it with set_choice" % Flag.keys()[flag])
		return
	_state[flag] = value
	save_state()

static func toggle(flag: Flag) -> bool:
	var value := not is_on(flag)
	set_on(flag, value)
	return value

static func choice_of(flag: Flag) -> int:
	if not is_choice(flag):
		push_error("Experiments.choice_of: %s is on/off -- read it with is_on" % Flag.keys()[flag])
		return 0
	return int(value_of(flag))

static func set_choice(flag: Flag, index: int) -> void:
	if not is_choice(flag):
		push_error("Experiments.set_choice: %s is on/off -- write it with set_on" % Flag.keys()[flag])
		return
	_state[flag] = clampi(index, 0, options_of(flag).size() - 1)
	save_state()

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

static func is_choice(flag: Flag) -> bool:
	return DEFS[flag].has("options")

static func options_of(flag: Flag) -> Array:
	return DEFS[flag].get("options", [])

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
		if not cfg.has_section_key(CONFIG_SECTION, key):
			continue
		# A choice reads back as its INDEX before the on/off fallback, whose bool() would turn
		# every saved choice into true (#136's level-row trap).
		if is_choice(flag):
			_state[flag] = clampi(int(cfg.get_value(CONFIG_SECTION, key)), 0, options_of(flag).size() - 1)
		else:
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
