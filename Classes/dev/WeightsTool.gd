extends VBoxContainer
class_name WeightsTool

# THE WEIGHTS PAGE (#120 PR 3): every body's BLD and every item's weight on one page, because weight
# is a SCALE. Whether Torv in Bulwark Plate shrugs off Gust is a fact about three files at once, and
# no per-file editor can show it. Armour, runes, vials and the weapon families had no weight field in
# any dev tool before this; the dev asked for one (2026-10-01: weights "editable in the dev tools").
#
# IT EDITS THE LIVE CATALOG RESOURCE, never a copy. A character's kit references its gear files, and
# the catalogs serve the same cached object, so a weight dialled here moves the readout of every
# character carrying that file at once. What reaches the BOARD is the grant rule's business
# (Item.copy_for_grant): armour, runes and vials are duplicated when a unit receives them and a body's
# stats are copied at spawn, so those reach the next unit spawned; weapon families and mods are
# shared, so a weapon already on the board follows at once.
#
# A copy EMBEDDED in a mission file is out of its reach -- the #596 staleness class. It keeps the
# weight it was saved with; the page says so rather than pretending otherwise.
#
# Save writes only the files TOUCHED since the last save or reset (#389), and asks first (#380). A
# saved weapon variant is read-only here: its weight is COMPOSED (WeaponInstance.get_effective_weight
# -- family, its own, fitted mods), so the family row is where it moves.

const CONFIRM_LIST_MAX := 12   # GameTool's: a confirm listing sixty files is one nobody reads
const NOTICE_COLOR := Color(0.62, 0.82, 1.0, 1)   # GameTool's note blue, against the headings' gold
const MAX_MASS := 99

# The item folders, titled. ItemCatalog.SOURCES is the one list of where items live and sets the
# order; this only names each folder. A folder missing here still draws, under its path, so a kind
# added to SOURCES can never be silently left off the page.
const SECTION_TITLES := {
	WeaponCatalog.MAIN_VARIETIES_DIR: "Weapon families",
	WeaponCatalog.PROTOTYPE_DIR: "Prototypes",
	WeaponCatalog.SAVED_DIR: "Saved weapons (composed: edit the family)",
	ArmorCatalog.VARIANT_DIR: "Armour",
	RuneCatalog.VARIANT_DIR: "Runes",
	VialCatalog.VARIANT_DIR: "Vials",
}
const MOD_TITLE := "Weapon mods"
const CHARACTER_TITLE := "Characters (BLD)"

var _save_button: Button
var _status: Label
var _bands: Label
var _body: VBoxContainer
# Every editable row's resource -> its SpinBox, so a test (and Reset) can find a row by what it edits.
var _spins: Dictionary[Resource, SpinBox] = {}
var _readouts: Dictionary[UnitData, Label] = {}
# Touched since the last save/reset: resource -> what it held BEFORE the first edit (a UnitData's
# entry is null when BLD was unauthored, so Reset can put the sparse key back exactly).
var _touched: Dictionary[Resource, Variant] = {}


func _ready() -> void:
	var buttons := HBoxContainer.new()
	add_child(buttons)
	_save_button = Button.new()
	_save_button.text = "Save"
	_save_button.tooltip_text = "Write every file changed on this page since the last save. Asks first."
	_save_button.pressed.connect(_on_save_pressed)
	buttons.add_child(_save_button)
	var reset := Button.new()
	reset.text = "Reset"
	reset.tooltip_text = "Put every unsaved change on this page back to what is saved on disk."
	reset.pressed.connect(_on_reset_pressed)
	buttons.add_child(reset)
	_status = _note("")
	_bands = _note("")
	_note("A change reaches the next unit spawned. Weapon families and mods are shared, so a weapon "
		+ "already on the board follows at once. An item copy saved inside a mission file keeps its own weight.")
	_body = DevWidgets.add_knob_scroll(self)
	_rebuild()


func _note(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", NOTICE_COLOR)
	add_child(label)
	return label


# The Character and Item pages save over the same files, and a new file can appear; both are read
# fresh on every show. Touched edits survive it: they live on the resources, not on the rows.
func refresh_on_show() -> void:
	_rebuild()


func _rebuild() -> void:
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_spins.clear()
	_readouts.clear()
	_bands.text = ("Weight = BLD + everything carried. Band 1 from %d, band 2 from %d: each band takes "
		+ "a tile off a shove and adds 1 fall damage per level.") % [Stats.WEIGHT_BAND_1, Stats.WEIGHT_BAND_2]
	_add_character_section()
	for dir: String in ItemCatalog.SOURCES:
		_add_item_section(String(SECTION_TITLES.get(dir, dir)), ResourceCatalog.by_file(dir, Item))
	_add_item_section(MOD_TITLE, ResourceCatalog.by_file(WeaponModCatalog.MOD_DIR, WeaponModData))
	_refresh_readouts()
	_refresh_dirty()


func _add_character_section() -> void:
	DevWidgets.add_heading(_body, CHARACTER_TITLE)
	var grid := _grid()
	var by_file := UnitCatalog.get_characters_by_file()
	var labels := _labels_for(by_file)
	for file: String in _sorted_by_label(labels):
		var data: UnitData = by_file[file]
		_add_name(grid, labels[file], data)
		var spin := _add_spin(grid, data, "This character's body weight (BLD).")
		_spins[data] = spin
		var readout := Label.new()
		grid.add_child(readout)
		_readouts[data] = readout


func _add_item_section(title: String, by_file: Dictionary) -> void:
	if by_file.is_empty():
		return
	DevWidgets.add_heading(_body, title)
	var grid := _grid()
	var labels := _labels_for(by_file)
	for file: String in _sorted_by_label(labels):
		var item: Item = by_file[file]
		_add_name(grid, labels[file], item)
		if item is WeaponInstance:
			_add_composed(grid, item as WeaponInstance)
			continue
		_spins[item] = _add_spin(grid, item, "This item's weight.")
		grid.add_child(Control.new())   # the readout column is the characters' alone


func _grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	_body.add_child(grid)
	return grid


func _add_name(grid: GridContainer, text: String, res: Resource) -> void:
	var label := Label.new()
	label.text = text
	label.tooltip_text = res.resource_path
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.add_child(label)


func _add_spin(grid: GridContainer, res: Resource, tip: String) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = MAX_MASS
	spin.value = value_of(res)
	spin.value_changed.connect(func(v: float) -> void: edit(res, int(v)))
	grid.add_child(spin)
	DevWidgets.apply_tooltip(spin, tip)
	return spin


func _add_composed(grid: GridContainer, weapon: WeaponInstance) -> void:
	var total := Label.new()
	total.text = str(weapon.get_effective_weight())
	grid.add_child(total)
	var family: int = weapon.template.weight if weapon.template != null else 0
	var mods := weapon.get_effective_weight() - family - weapon.weight
	var parts := "family %d + mods %d" % [family, mods]
	if weapon.weight != 0:
		parts += " + its own %d" % weapon.weight
	var breakdown := Label.new()
	breakdown.text = parts
	grid.add_child(breakdown)


# What each row is called: the display name, with the file added only where two rows in one section
# would otherwise read the same (three runes are authored as "Gust").
func _labels_for(by_file: Dictionary) -> Dictionary:
	var names := {}
	for file: String in by_file:
		var res: Resource = by_file[file]
		var shown: String = res.get("display_name")
		names[file] = shown if shown != "" else file
	var counts := {}
	for file: String in names:
		counts[names[file]] = int(counts.get(names[file], 0)) + 1
	for file: String in names:
		if int(counts[names[file]]) > 1:
			names[file] = "%s (%s)" % [names[file], file]
	return names


func _sorted_by_label(labels: Dictionary) -> Array:
	var files := labels.keys()
	files.sort_custom(func(a: String, b: String) -> bool:
		return String(labels[a]).naturalnocasecmp_to(String(labels[b])) < 0)
	return files


# --- the values -----------------------------------------------------------------------------

# The one number a row shows: a body's BLD (its default where the character leaves it unauthored,
# which is what a spawned unit reads), or an item's own authored weight.
static func value_of(res: Resource) -> int:
	if res is UnitData:
		return int((res as UnitData).base_stats.get(Stats.Stat.BLD, Stats.STAT_DEFAULTS[Stats.Stat.BLD]))
	return (res as Item).weight


# What a row's SpinBox calls. Public so a caller can drive a row without a widget in hand.
func edit(res: Resource, value: int) -> void:
	if not _touched.has(res):
		_touched[res] = _snapshot(res)
	_write(res, value)
	if _spins.has(res):
		_spins[res].set_value_no_signal(value)
	_refresh_readouts()
	_refresh_dirty()


static func _snapshot(res: Resource) -> Variant:
	if res is UnitData:
		return (res as UnitData).base_stats.get(Stats.Stat.BLD)   # null when unauthored
	return (res as Item).weight


static func _write(res: Resource, value: Variant) -> void:
	if res is UnitData:
		var stats := (res as UnitData).base_stats
		if value == null:
			stats.erase(Stats.Stat.BLD)
		else:
			stats[Stats.Stat.BLD] = int(value)
	else:
		(res as Item).weight = int(value)


# Each character's starting kit weighed the way a spawned unit will weigh it (Item.total_weight is
# Unit.get_carried_weight's own sum), so the band shown is the band the board will use.
func _refresh_readouts() -> void:
	for data: UnitData in _readouts:
		var body := value_of(data)
		var carried := Item.total_weight(data.starting_inventory)
		var total := body + carried
		_readouts[data].text = "carries %d, WT %d, band %d" % [carried, total, Stats.weight_band(total)]


func is_dirty() -> bool:
	return not _touched.is_empty()


func _refresh_dirty() -> void:
	DevWidgets.mark_unsaved(_save_button, "Save", is_dirty())


func touched_files() -> PackedStringArray:
	var files := PackedStringArray()
	for res: Resource in _touched:
		files.append(res.resource_path)
	files.sort()
	return files


# --- save / reset ---------------------------------------------------------------------------

func _on_save_pressed() -> void:
	var files := touched_files()
	if files.is_empty():
		_status.text = "Nothing has moved off what is saved."
		return
	var shown := PackedStringArray()
	for path: String in files:
		shown.append(path.trim_prefix("res://"))
	if shown.size() > CONFIRM_LIST_MAX:
		var more := shown.size() - CONFIRM_LIST_MAX
		shown = shown.slice(0, CONFIRM_LIST_MAX)
		shown.append("...and %d more" % more)
	DevWidgets.confirm(self,
		"Write %d changed file(s)? Their saved weights are replaced.\n\n%s" % [files.size(), "\n".join(shown)],
		save_touched)


# A file whose write FAILED stays touched, so the marker keeps saying so and the next Save retries it.
func save_touched() -> void:
	var saved := PackedStringArray()
	var failed := PackedStringArray()
	for res: Resource in _touched.keys():
		if DevWidgets.save_over(res, res.resource_path):
			saved.append(res.resource_path.get_file())
			_touched.erase(res)
		else:
			failed.append(res.resource_path.get_file())
	var parts := PackedStringArray()
	if not saved.is_empty():
		parts.append("Saved: %s" % ", ".join(saved))
	if not failed.is_empty():
		parts.append("FAILED: %s" % ", ".join(failed))
	_status.text = " | ".join(parts)
	_refresh_dirty()


func _on_reset_pressed() -> void:
	for res: Resource in _touched:
		_write(res, _touched[res])
	_touched.clear()
	_rebuild()
	_status.text = "Back to what is saved on disk."
