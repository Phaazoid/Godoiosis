extends Object
class_name PlayerSettings

## The player's own preferences (#350) — the settings a PERSON chooses and keeps, as opposed to a
## mission's authored look (LookPreset), a dev experiment (Experiments) or a tuning value.
##
## Declare a setting in `Setting`, describe it in `DEFS`, read it anywhere with
## `PlayerSettings.is_on(...)`. SettingsScreen builds its rows straight off DEFS, so a new setting
## is one enum member plus one table entry and no UI work — which is the point: #217's
## photosensitivity switch is the second tenant, shipped, and `docs/design/presentation-effects.md`
## ruled that a settings surface DRIVES that switch rather than a second one growing beside it.
##
## A static class, not an autoload: this project has none, and Stats / Elemental / Experiments are
## all class-level statics for the same reason. Callers poll it; there is no changed signal, because
## the one reader that matters (UnitMirror) is a per-frame reconcile by design.
##
## Unlike Experiments.Flag, these are NOT meant to be culled — a setting is a promise to the player.
## Persistence is keyed by the enum member's NAME, so reordering is safe and a deleted member just
## leaves a dead cfg key behind.

enum Setting {
	ALWAYS_SHOW_HEALTH,
	SHOW_DIALOG,
	PHOTOSENSITIVITY,
}

# Per-setting metadata. Literal-only, so it can be a compile-time const (the Experiments.DEFS shape).
#   title   — the checkbox label
#   desc    — one line under it, in the player's terms rather than the code's
#   default — the value before anyone has ever touched it
const DEFS := {
	Setting.ALWAYS_SHOW_HEALTH: {
		"title": "Always show health bars",
		"desc": "Keep every unit's health bar up, not just the one under your cursor. The numbers still appear on hover.",
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
}

const CONFIG_SECTION := "settings"

# Where preferences persist. A static var (not const) so tests can redirect it to a temp file.
static var config_path := "user://settings.cfg"
# Tests flip this false to stay fully in-memory (no disk I/O).
static var persistence_enabled := true

static var _state: Dictionary[Setting, bool] = {}
static var _loaded := false

# --- read / write API ---

static func is_on(setting: Setting) -> bool:
	if not _loaded:
		load_state()
	if _state.has(setting):
		return _state[setting]
	return default_of(setting)

static func set_on(setting: Setting, value: bool) -> void:
	_state[setting] = value
	save_state()

# --- registry introspection (used by SettingsScreen) ---

static func title_of(setting: Setting) -> String:
	return str(DEFS[setting]["title"])

static func desc_of(setting: Setting) -> String:
	return str(DEFS[setting]["desc"])

static func default_of(setting: Setting) -> bool:
	return bool(DEFS[setting]["default"])

# --- persistence (keyed by enum NAME, so the cfg is human-readable and reorder-proof) ---

static func load_state() -> void:
	_loaded = true
	_state.clear()
	if not persistence_enabled:
		return
	var cfg := ConfigFile.new()
	if cfg.load(config_path) != OK:
		return
	for setting in DEFS:
		var key: String = Setting.keys()[setting]
		if cfg.has_section_key(CONFIG_SECTION, key):
			_state[setting] = bool(cfg.get_value(CONFIG_SECTION, key))

static func save_state() -> void:
	if not persistence_enabled:
		return
	var cfg := ConfigFile.new()
	for setting in _state:
		cfg.set_value(CONFIG_SECTION, Setting.keys()[setting], _state[setting])
	cfg.save(config_path)

# --- test seam ---

## Wipe runtime state and skip disk I/O so suites stay hermetic. Call in before_test().
static func reset_for_test() -> void:
	persistence_enabled = false
	config_path = "user://settings_test.cfg"
	_state.clear()
	_loaded = true
