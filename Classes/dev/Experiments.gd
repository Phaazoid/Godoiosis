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
##
## A flag is a TOGGLE unless its DEFS entry declares `options`, which makes it a CHOICE between
## several treatments (#508) -- PlayerSettings' row kinds, same shape and the same refusal: each typed
## façade turns the other kind away, because the coercions underneath are silent (#647).

enum Flag {
	EXAMPLE_FLAG,
	DIORAMA_BYSTANDERS,
	DIORAMA_CAMERA_CUTS_AHEAD,
	GAS_STYLE,
	GAS_OVER_UNITS,
	WATER_BASIN,
	WATER_BANK,
}

# Per-flag metadata. Literal-only, so it can be a compile-time const (like STAT_DEFAULTS).
#   title   — label shown on the row
#   desc    — one-line explanation under it
#   default — value when the flag has never been set (no cfg entry): a bool, or an option INDEX
#   options — (choice rows only) the labels, in index order
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
	Flag.GAS_STYLE: {
		"title": "Gas style",
		"desc": "Which mix of the realistic volume and the pixel puffs draws gas (#508, round 6). Puff field: the pixel puffs' full layout over the volume. Drifting puffs: the same, every puff wandering round its spot. Haze + puffs: the volume thinned to a low haze so the puffs carry the shapes. Puffs in the cloud: fewer puffs, floating through the volume's height. Hold Alt to see the edged floor under every cloud. Paint gas with the Tile Brush's Gas mode. Pick one and the losers get deleted.",
		"default": 0,
		"options": ["Puff field", "Drifting puffs", "Haze + puffs", "Puffs in the cloud"],
	},
	Flag.GAS_OVER_UNITS: {
		"title": "Gas draws over units",
		"desc": "On: a gas volume veils whatever is behind it -- units, move tiles, flames and health bars too. Off: all of those draw crisp on top of the gas. #508's layering test.",
		"default": true,
	},
	Flag.WATER_BASIN: {
		"title": "Water basin",
		"desc": "On: water sits below the ground around it, so its banks show in dirt, and units standing in it wade with their legs under the surface. Off: today's flush water. #654 -- tune the depth on Game > Water > Water basin. If the look stays this becomes the default; if not, it is deleted with everything it gates.",
		"default": false,
	},
	Flag.WATER_BANK: {
		"title": "Water submerged bank",
		"desc": "On: the water surface draws the bank you would see a short way down through it, traced from the camera so it shows on the far side of a pond, and the shoreline foam is off. Off: today's water. #654 -- tune Bank depth and Bank wobble on Game > Water. Works with or without Water basin. If the look stays this becomes the default; if not, it is deleted with everything it gates.",
		"default": false,
	},
}

const CONFIG_SECTION := "experiments"

# Where toggles persist. A static var (not const) so tests can redirect it to a temp file.
static var config_path := "user://experiments.cfg"
# Tests flip this false to stay fully in-memory (no disk I/O); _static_init clears it headlessly.
static var persistence_enabled := true

# Runtime state, keyed by Flag: a bool for a toggle, an option index for a choice. `static var` =>
# one instance for the whole run, no autoload needed (mirrors how Stats / Elemental are statics).
static var _state: Dictionary[Flag, Variant] = {}
static var _loaded := false

# Nobody is at the keyboard in a headless run, so there is no dev whose flags these are -- the
# suite reads the DEFAULTS rather than this machine's cfg. PlayerSettings' rule, same shape (#449).
static func _static_init() -> void:
	if DisplayServer.get_name() == "headless":
		persistence_enabled = false

# --- read / write API ---

static func is_on(flag: Flag) -> bool:
	if is_choice(flag):
		push_error("Experiments: %s is a choice, not a toggle -- read it with choice_of" % Flag.keys()[flag])
		return false
	return bool(value_of(flag))

static func set_on(flag: Flag, value: bool) -> void:
	if is_choice(flag):
		push_error("Experiments: %s is a choice, not a toggle -- write it with set_choice" % Flag.keys()[flag])
		return
	_set_value(flag, value)

static func toggle(flag: Flag) -> bool:
	var value := not is_on(flag)
	set_on(flag, value)
	return value

static func choice_of(flag: Flag) -> int:
	if not is_choice(flag):
		push_error("Experiments: %s is a toggle, not a choice -- read it with is_on" % Flag.keys()[flag])
		return 0
	return int(value_of(flag))

static func set_choice(flag: Flag, index: int) -> void:
	if not is_choice(flag):
		push_error("Experiments: %s is a toggle, not a choice -- write it with set_on" % Flag.keys()[flag])
		return
	_set_value(flag, clampi(index, 0, options_of(flag).size() - 1))

# The kind-blind read: what a caller walking every flag (a fingerprint, a reset) asks.
static func value_of(flag: Flag) -> Variant:
	if not _loaded:
		load_state()
	if _state.has(flag):
		return _state[flag]
	return default_value(flag)

static func reset_all() -> void:
	_state.clear()
	save_state()

static func _set_value(flag: Flag, value: Variant) -> void:
	_state[flag] = value
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

static func default_value(flag: Flag) -> Variant:
	return int(DEFS[flag]["default"]) if is_choice(flag) else bool(DEFS[flag]["default"])

static func default_of(flag: Flag) -> bool:
	if is_choice(flag):
		push_error("Experiments: %s is a choice -- its default is an index, read default_value" % Flag.keys()[flag])
		return false
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
		var raw: Variant = cfg.get_value(CONFIG_SECTION, key)
		# A choice is answered BEFORE the toggle's bool(): bool(2) is true, so the toggle branch would
		# read every saved option back as true -- consistently, on every relaunch (#647's trap).
		if is_choice(flag):
			var index := int(raw)
			if index >= 0 and index < options_of(flag).size():
				_state[flag] = index
		else:
			_state[flag] = bool(raw)

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
