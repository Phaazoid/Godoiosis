extends Object
class_name PlayerSettings

## The player's own preferences (#350) — the settings a PERSON chooses and keeps, as opposed to a
## mission's authored look (LookPreset), a dev experiment (Experiments) or a tuning value.
##
## Declare a setting in `Setting`, describe it in `DEFS`, read it anywhere with
## `PlayerSettings.is_on(...)` or `PlayerSettings.choice_of(...)`. SettingsScreen builds its rows
## straight off DEFS, so a new setting is one enum member plus one table entry and no UI work —
## which is the point: #217's photosensitivity switch is the second tenant, shipped, and
## `docs/design/presentation-effects.md` ruled that a settings surface DRIVES that switch rather
## than a second one growing beside it.
##
## TWO KINDS OF ROW (#418). A row is a TOGGLE unless it declares `options`, in which case it is a
## CHOICE the player picks a value from. The kind is derived from the table rather than stated in a
## second field, so there is nothing to keep in step. The generic three — value_of / set_value /
## default_value — are what a caller walking DEFS uses; is_on and choice_of are typed façades over
## them for the callers that know which kind they are reading.
##
## A static class, not an autoload: this project has none, and Stats / Elemental / Experiments are
## all class-level statics for the same reason. Callers poll it; there is no changed signal, because
## the one reader that matters (UnitMirror) is a per-frame reconcile by design.
##
## Unlike Experiments.Flag, these are NOT meant to be culled — a setting is a promise to the player.
## Persistence is keyed by the enum member's NAME, so reordering is safe and a deleted member just
## leaves a dead cfg key behind.

enum Setting {
	HEALTH_BARS,
	ALWAYS_SHOW_SQUAD_RINGS,
	SHOW_DIALOG,
	PHOTOSENSITIVITY,
	BATTLE_ZOOM,
}

## When a unit wears its readout (#418). A DECLARED duplicate: these values ARE the indices into the
## HEALTH_BARS row's `options`, and test_player_settings pins the two in step. THE ENUM IS
## AUTHORITATIVE — the list is labels for it, never a second vocabulary.
enum HealthBars {
	HOVERED,   # #229's behaviour, and still what a player who never opens the menu gets
	DAMAGED,   # every unit below full HP; a body clings at 1 HP, so it qualifies
	EVERY,     # #350's behaviour
}

# Per-setting metadata. Literal-only, so it can be a compile-time const (the Experiments.DEFS shape).
#   title   — the row label
#   desc    — one line under it, in the player's terms rather than the code's
#   default — the value before anyone has ever touched it
#   options — CHOICE ROWS ONLY: the labels, in the value order of the row's own enum. Its PRESENCE
#             is what makes the row a choice.
const DEFS := {
	Setting.HEALTH_BARS: {
		"title": "Health bars",
		"desc": "When a unit wears its health bar. The numbers still appear on hover, and a unit your orders are about to change keeps its bar whichever you pick.",
		"options": ["Under the cursor", "Damaged units", "Every unit"],
		"default": HealthBars.HOVERED,
	},
	Setting.ALWAYS_SHOW_SQUAD_RINGS: {
		"title": "Always show squad rings",
		"desc": "Keep every squad's coloured rings under its members -- and its leader's crown -- at all times, not just the squad you're looking at.",
		"default": false,
	},
	Setting.SHOW_DIALOG: {
		"title": "Show mission dialog",
		"desc": "Characters speak during missions. Turn off to skip all dialog -- replays, restarts, or preference. Tutorial instructions stay on either way.",
		"default": true,
	},
	Setting.PHOTOSENSITIVITY: {
		"title": "Photosensitivity toggle",
		"desc": "Hold flickering and strobing effects (like fire) at a steady brightness instead of animating them. For players sensitive to flashing lights.",
		"default": false,
	},
	Setting.BATTLE_ZOOM: {
		"title": "Battle zoom",
		"desc": "Play out each clash with dramatic timing -- a killing blow, a Crisis or a last-gasp survival get held on. Turn off for a plainer, quicker pass.",
		"default": true,
	},
}

const CONFIG_SECTION := "settings"

# Where preferences persist. A static var (not const) so tests can redirect it to a temp file.
static var config_path := "user://settings.cfg"
# Tests flip this false to stay fully in-memory (no disk I/O); _static_init clears it headlessly.
static var persistence_enabled := true

# Variant-valued because a row is a bool or an int depending on its kind (#418).
static var _state: Dictionary[Setting, Variant] = {}
static var _loaded := false

# A headless process has no PLAYER at the keyboard, so it has nobody's preferences to honour: the
# suite and the Play API read the DEFAULTS, never whatever cfg this machine happens to hold. The
# project's existing spelling for "nobody is watching" (Pacing.beat, CameraController.pan_to).
# A suite that wants the real disk path sets persistence_enabled back to true itself (#449).
static func _static_init() -> void:
	if DisplayServer.get_name() == "headless":
		persistence_enabled = false

# --- read / write API, kind-agnostic ---

static func value_of(setting: Setting) -> Variant:
	if not _loaded:
		load_state()
	if _state.has(setting):
		return _state[setting]
	return default_value(setting)

static func set_value(setting: Setting, value: Variant) -> void:
	_state[setting] = value
	save_state()

static func default_value(setting: Setting) -> Variant:
	return DEFS[setting]["default"]

# --- typed façades, for callers that know their row's kind ---

static func is_on(setting: Setting) -> bool:
	return bool(value_of(setting))

static func set_on(setting: Setting, value: bool) -> void:
	set_value(setting, value)

static func choice_of(setting: Setting) -> int:
	return int(value_of(setting))

static func set_choice(setting: Setting, value: int) -> void:
	set_value(setting, value)

# --- registry introspection (used by SettingsScreen) ---

static func title_of(setting: Setting) -> String:
	return str(DEFS[setting]["title"])

static func desc_of(setting: Setting) -> String:
	return str(DEFS[setting]["desc"])

## Which widget this row wants. Asked of the table itself rather than a second `kind` field.
static func is_choice(setting: Setting) -> bool:
	return DEFS[setting].has("options")

## The labels, in the row's own enum order. Read-only — it is the const's own array, and that is
## deliberate: these are canon, not a caller's scratch list.
static func options_of(setting: Setting) -> Array:
	return DEFS[setting]["options"]

# --- persistence (keyed by enum NAME, so the cfg is human-readable and reorder-proof) ---

static func load_state() -> void:
	_loaded = true
	_state.clear()
	if not persistence_enabled:
		return
	var cfg := ConfigFile.new()
	if cfg.load(config_path) != OK:
		return
	for setting: Setting in DEFS:
		var key: String = Setting.keys()[setting]
		if not cfg.has_section_key(CONFIG_SECTION, key):
			continue
		var raw: Variant = cfg.get_value(CONFIG_SECTION, key)
		if not is_choice(setting):
			_state[setting] = bool(raw)
			continue
		# The cfg is a text file the player can open, so an index out of the options list is
		# reachable input rather than a bug. Fall back to the default instead of trusting it.
		var picked := int(raw)
		if picked >= 0 and picked < options_of(setting).size():
			_state[setting] = picked

static func save_state() -> void:
	if not persistence_enabled:
		return
	var cfg := ConfigFile.new()
	for setting: Setting in _state:
		cfg.set_value(CONFIG_SECTION, Setting.keys()[setting], _state[setting])
	cfg.save(config_path)

# --- test seam ---

## Wipe runtime state and skip disk I/O so suites stay hermetic. Call in before_test().
static func reset_for_test() -> void:
	persistence_enabled = false
	config_path = "user://settings_test.cfg"
	_state.clear()
	_loaded = true
