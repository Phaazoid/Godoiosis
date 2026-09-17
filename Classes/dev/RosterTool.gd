extends VBoxContainer
class_name RosterTool

# WHAT A MISSION OFFERS, edited (#812): the units it fields, the loose gear its stash starts with,
# the weapon mods its fitting card lists, and since #964 the jobs its picker lists. A `Roster` file,
# on the pool chrome every other Project-scope editor wears -- Load / Update / Delete / New / name /
# Save As.
#
# It exists because #735 shipped the whole model and left the authoring in Godot's own inspector:
# "rosters are hand-authored in the inspector until #731's deferred dev tab". This is that tab, and
# it is RosterLint's first caller outside CI.
#
# FOUR COLUMNS, EACH THE WHOLE CATALOGUE (dev, 2026-09-07: "I kind of want to see both what's
# available and what's already there at the same time"; three until #964 added jobs). Chosen rows
# float above a rule, the rest below, and ticking an unchosen row IS the add -- so there is no picker,
# no Add button, and no second pane listing what you could have. Each column scrolls on its own, so
# the page never does.
#
# ENTRIES ARE DIRECT REFS, never copies -- the Attack Editor's `_populate_extras` rule, and here it
# is load-bearing twice: a copy would serialize INLINE as a sub_resource instead of an ext_resource
# (the #177 trap, which Company.tres shows the right form of), and it would break
# WeaponModData.copy_for_grant()'s answer-with-itself, which is what keeps a mod's granted attacks
# identity-stable (#732).
#
# IT ONLY EVER AUTHORS A REFERENCE ENTRY (dev's ruling, 2026-09-07: "if I want different versions of
# the same character, I will author them specifically for different missions"). A roster already
# holding a snapshot entry loads, lists it, and wears its lint mark; nothing here makes one.

@onready var load_dropdown: OptionButton = %RosterLoadDropdown
@onready var name_input: LineEdit = %RosterNameInput
@onready var update_button: Button = %UpdateRosterButton
@onready var delete_button: Button = %DeleteRosterButton
@onready var save_as_button: Button = %SaveAsRosterButton
@onready var status_label: Label = %RosterStatusLabel
@onready var pools_row: HBoxContainer = %RosterPools

const NOUN := "roster"

# The roster being edited -- always a COPY with no resource_path, so nothing here can mutate the
# cached file behind a Load (`load()` serves the cache). `_loaded_name` is what Update aims at.
var current: Roster = Roster.new()
var _loaded_name := ""
var _dirty := false


func _ready() -> void:
	_refresh_dropdown()
	_rebuild()


# --- the pool chrome ---

func _refresh_dropdown() -> void:
	var keep := DevWidgets.selected_name(load_dropdown)
	load_dropdown.clear()
	# select(-1) BEFORE the match loop: add_item auto-selects index 0, so a name that no longer
	# exists would leave Update silently aimed at whatever sorts first (CLAUDE.md).
	for name: String in RosterCatalog.saved_rosters():
		load_dropdown.add_item(name)
	load_dropdown.select(-1)
	for i in load_dropdown.item_count:
		if load_dropdown.get_item_text(i) == keep:
			load_dropdown.select(i)
	_refresh_buttons()


func _refresh_buttons() -> void:
	var target := DevWidgets.selected_name(load_dropdown)
	DevWidgets.refresh_update_button(update_button, target, NOUN, _update_block_reason(target))
	DevWidgets.refresh_delete_button(delete_button, target, NOUN)
	# A LITERAL, never the button's own text: mark_unsaved DECORATES its base, and
	# refresh_update_button above writes only the tooltip and the disabled flag -- so feeding the
	# live caption back in re-decorates what it already decorated, and the marker grows by one star
	# per refresh. Every other caller of it passes a literal for this reason.
	DevWidgets.mark_unsaved(update_button, "Update", _dirty)


# "" = allowed. Update overwrites only the roster actually LOADED (#166's shape, the Character
# editor's verbatim): the dropdown is a picker, and a picker is not a claim about what is on screen.
func _update_block_reason(target: String) -> String:
	if target == "":
		return "Pick a roster to overwrite"
	if target == _loaded_name:
		return ""
	return "Load '%s' first -- Update overwrites it with whatever is in the editor" % target


func _on_load_pressed() -> void:
	var picked := DevWidgets.selected_name(load_dropdown)
	if picked == "":
		return
	var loaded := RosterCatalog.resolve(picked)
	if loaded == null:
		status_label.text = "Could not load '%s'." % picked
		return
	# A COPY, and its resource_path is dropped with it -- save_over is what claims a path back, and
	# editing the cached object would edit the file every other reader is holding (#589).
	current = loaded.duplicate(true)
	current.resource_path = ""
	_loaded_name = picked
	_dirty = false
	name_input.text = picked
	_rebuild()


func _on_new_pressed() -> void:
	current = Roster.new()
	_loaded_name = ""
	_dirty = false
	name_input.text = ""
	_rebuild()


func _on_save_as_pressed() -> void:
	var new_name := name_input.text.strip_edges()
	if DevWidgets.refuse_illegal_name(new_name, NOUN, status_label):
		return
	var path := RosterCatalog.roster_path(new_name)
	if DevWidgets.refuse_existing_file(path, NOUN, status_label):
		return
	_write(path, new_name)


func _on_update_pressed() -> void:
	var target := DevWidgets.selected_name(load_dropdown)
	if _update_block_reason(target) != "":
		return
	DevWidgets.confirm_overwrite(self, target, "the roster on screen",
		func(): _write(RosterCatalog.roster_path(target), target))


func _on_delete_pressed() -> void:
	var target := DevWidgets.selected_name(load_dropdown)
	if target == "":
		return
	DevWidgets.confirm_delete(self, target, func():
		if DevWidgets.delete_saved_file(RosterCatalog.roster_path(target), NOUN, status_label):
			if target == _loaded_name:
				_loaded_name = ""
			_refresh_dropdown()
	)


# Through DevWidgets.save_over and nowhere else: it is the one writer that adopts onto the object
# already owning the path (#589), claims the path (#99) and preserves the file's uids (#481).
func _write(path: String, saved_name: String) -> void:
	if not DevWidgets.save_over(current, path, status_label):
		return
	_loaded_name = saved_name
	_dirty = false
	name_input.text = saved_name
	_refresh_dropdown()
	for i in load_dropdown.item_count:
		if load_dropdown.get_item_text(i) == saved_name:
			load_dropdown.select(i)
	_refresh_buttons()
	status_label.text = "Saved '%s'." % saved_name


func _mark_dirty() -> void:
	_dirty = true
	_refresh_buttons()


# --- the three pools ---

# Deferred, for the reason every self-rebuilding surface in this project defers (#741): a row's own
# toggle is what asks for the rebuild, and freeing the emitting node inside its signal is
# "Attempted to free a locked object".
func _rebuild_deferred() -> void:
	_rebuild.call_deferred()


func _rebuild() -> void:
	for child in pools_row.get_children():
		pools_row.remove_child(child)
		child.queue_free()
	_build_units()
	_build_stash()
	_build_mods()
	_build_jobs()
	_refresh_buttons()


# One column: a heading with its count, the "offer everything" toggle, the scrolling list, and a
# footnote. The list itself is filled by the caller, since what a row LOOKS like is the one thing
# the three columns genuinely disagree about.
func _column(title: String, count_text: String, toggle_text: String, toggled: bool,
		on_toggle: Callable, footnote: String) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pools_row.add_child(column)

	var head := HBoxContainer.new()
	var label := Label.new()
	label.text = title
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(label)
	var count := Label.new()
	count.text = count_text
	count.add_theme_font_size_override("font_size", 10)
	head.add_child(count)
	column.add_child(head)

	var toggle := CheckBox.new()
	toggle.text = toggle_text
	toggle.button_pressed = toggled
	toggle.toggled.connect(func(on: bool):
		on_toggle.call(on)
		_mark_dirty()
		_rebuild_deferred()
	)
	DevWidgets.apply_tooltip(toggle, DevWidgets.wrap_tooltip(
		"Offer everything authored, including anything added later. The picks below are KEPT while "
		+ "this is on -- turn it off and they come back."))
	column.add_child(toggle)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "List"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var foot := Label.new()
	foot.text = footnote
	foot.add_theme_font_size_override("font_size", 9)
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(foot)
	return list


func _rule(into: VBoxContainer) -> void:
	into.add_child(HSeparator.new())


# WHO this mission offers. Chosen first, in ENTRY order -- which is DRAW order, since
# PreMission.deployment_plan stands the first N under the cap -- then everyone else.
func _build_units() -> void:
	var characters := UnitCatalog.get_characters_by_file()
	var chosen_files := _entry_files()
	var list := _column("Units", "%d of %d" % [chosen_files.size(), characters.size()],
			"Offer every character", current.offers_every_character,
			func(on: bool): current.offers_every_character = on,
			"order above the line is DRAW order")

	var findings := RosterLint.check(current)
	for i in current.entries.size():
		var entry: ScenarioUnitEntry = current.entries[i]
		var file := _file_of(entry.unit_data if entry != null else null)
		list.add_child(_unit_row(i, file, characters, findings))
	if not current.entries.is_empty():
		_rule(list)
	for file: String in characters:
		if chosen_files.has(file):
			continue
		list.add_child(_offer_row(file, characters[file],
				func(): _add_character(characters[file])))


func _unit_row(index: int, file: String, characters: Dictionary, findings: Array[Dictionary]) -> HBoxContainer:
	var row := HBoxContainer.new()
	var ordinal := Label.new()
	ordinal.text = str(index + 1)
	ordinal.add_theme_font_size_override("font_size", 9)
	ordinal.custom_minimum_size = Vector2(16, 0)
	row.add_child(ordinal)
	var tick := CheckBox.new()
	tick.button_pressed = true
	tick.text = _label_for(file, characters.get(file))
	tick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tick.toggled.connect(func(_on: bool):
		current.entries.remove_at(index)
		_mark_dirty()
		_rebuild_deferred()
	)
	row.add_child(tick)
	# The mark names the FINDING, the Attack Editor's rule: a fixed phrase would describe the wrong
	# problem the moment the lint learns a second one.
	var text := _finding_for(index, findings)
	if text != "":
		var mark := Label.new()
		mark.text = text
		mark.add_theme_font_size_override("font_size", 9)
		mark.add_theme_color_override("font_color", ScenarioTool.DEGRADES_COLOR)
		row.add_child(mark)
	return row


# The loose gear. A COUNT rather than a tick, because a stash is a MULTISET: two Fire Vials is a
# real stash, and a tick could not say it -- so loading such a roster and pressing Update would
# silently drop one.
func _build_stash() -> void:
	var items := ItemCatalog.by_file()
	var counts := _stash_counts()
	var list := _column("Stash", "%d of %d" % [current.stash.size(), items.size()],
			"Offer every item", current.offers_every_item,
			func(on: bool): current.offers_every_item = on,
			"a count, because two of one thing is a real stash")

	for file: String in items:
		if counts.get(file, 0) > 0:
			list.add_child(_count_row(file, items[file], counts[file]))
	if not current.stash.is_empty():
		_rule(list)
	for file: String in items:
		if counts.get(file, 0) == 0:
			list.add_child(_count_row(file, items[file], 0))


func _count_row(file: String, item: Item, count: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = 99
	spin.value = count
	spin.custom_minimum_size = Vector2(58, 0)
	spin.value_changed.connect(func(value: float):
		_set_stash_count(item, int(value))
		_mark_dirty()
		_rebuild_deferred()
	)
	row.add_child(spin)
	var label := Label.new()
	label.text = _label_for(file, item)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	row.add_child(label)
	return row


# What the fitting card lists, before the family filter -- which is a fact about the weapon and
# stays where it is (WeaponModCatalog.offerable_for).
func _build_mods() -> void:
	var mods := ResourceCatalog.by_file(WeaponModCatalog.MOD_DIR, WeaponModData)
	var chosen := _mod_files()
	var list := _column("Weapon mods", "%d of %d" % [chosen.size(), mods.size()],
			"Offer every mod", current.offers_every_mod,
			func(on: bool): current.offers_every_mod = on,
			"the family filter still applies per weapon")

	for file: String in mods:
		if chosen.has(file):
			list.add_child(_mod_row(file, mods[file], true))
	if not current.available_mods.is_empty():
		_rule(list)
	for file: String in mods:
		if not chosen.has(file):
			list.add_child(_mod_row(file, mods[file], false))


func _mod_row(file: String, mod: WeaponModData, chosen: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	var tick := CheckBox.new()
	tick.button_pressed = chosen
	tick.text = _label_for(file, mod)
	tick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tick.toggled.connect(func(on: bool):
		if on:
			current.available_mods.append(mod)   # the REF, never a copy -- see the header
		else:
			current.available_mods.erase(mod)
		_mark_dirty()
		_rebuild_deferred()
	)
	row.add_child(tick)
	return row


# What the pre-mission card's job picker offers (#964). The narrowest column: a roster stores job IDS,
# which is what UnitData.starting_jobs stores and what the Character Editor's own tick list writes, so
# there is no ref-to-file map to keep -- the tick state is the list itself.
func _build_jobs() -> void:
	var jobs := JobCatalog.get_jobs()
	var ids: Array[String] = []
	for id: String in jobs:
		ids.append(id)
	# Sorted by display name, the order the picker itself sorts in -- get_jobs() is a filesystem scan.
	ids.sort_custom(func(a: String, b: String) -> bool:
		return _job_label(jobs, a).naturalnocasecmp_to(_job_label(jobs, b)) < 0)

	var list := _column("Jobs", "%d of %d" % [current.available_jobs.size(), ids.size()],
			"Offer every job", current.offers_every_job,
			func(on: bool): current.offers_every_job = on,
			"a unit's own job is always offered to it")

	for id: String in ids:
		if current.available_jobs.has(id):
			list.add_child(_job_row(jobs, id, true))
	if not current.available_jobs.is_empty():
		_rule(list)
	for id: String in ids:
		if not current.available_jobs.has(id):
			list.add_child(_job_row(jobs, id, false))


func _job_row(jobs: Dictionary, id: String, chosen: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	var tick := CheckBox.new()
	tick.button_pressed = chosen
	tick.text = _label_for(id, jobs[id])
	tick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tick.toggled.connect(func(on: bool):
		if on:
			current.available_jobs.append(id)
		else:
			current.available_jobs.erase(id)
		_mark_dirty()
		_rebuild_deferred()
	)
	row.add_child(tick)
	return row


func _job_label(jobs: Dictionary, id: String) -> String:
	var job: JobData = jobs[id]
	return job.display_name if job != null and job.display_name != "" else id


# An unchosen row in the units column: the same shape as a chosen one minus the ordinal, since
# nothing below the rule has a draw position yet.
func _offer_row(file: String, character: UnitData, on_add: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(16, 0)
	row.add_child(spacer)
	var tick := CheckBox.new()
	tick.button_pressed = false
	tick.text = _label_for(file, character)
	tick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tick.toggled.connect(func(_on: bool):
		on_add.call()
		_mark_dirty()
		_rebuild_deferred()
	)
	row.add_child(tick)
	return row


# --- the model edits ---

# A REFERENCE entry, always (the dev's ruling): unit_data is the character FILE and state_saved is
# false, so the spawn's own initialize + starting kit are the whole answer and apply_unit_state is
# never called on it.
func _add_character(character: UnitData) -> void:
	var entry := ScenarioUnitEntry.new()
	entry.unit_data = character
	entry.state_saved = false
	current.entries.append(entry)


# The stash is a flat array with one slot per copy, so a count is applied by trimming or appending
# -- never by storing the number, which would be a second way to say what the array already says.
func _set_stash_count(item: Item, count: int) -> void:
	var kept: Array[Item] = []
	for held: Item in current.stash:
		if held != item:
			kept.append(held)
	for _i in count:
		kept.append(item)   # the REF; Loadout.from_roster is what copies, at phase build
	current.stash = kept


# --- reading the model ---

func _entry_files() -> Dictionary:
	var files := {}
	for entry: ScenarioUnitEntry in current.entries:
		if entry != null:
			files[_file_of(entry.unit_data)] = true
	return files


func _mod_files() -> Dictionary:
	var files := {}
	for mod: WeaponModData in current.available_mods:
		if mod != null:
			files[_file_of(mod)] = true
	return files


func _stash_counts() -> Dictionary:
	var counts := {}
	for item: Item in current.stash:
		if item == null:
			continue
		var file := _file_of(item)
		counts[file] = int(counts.get(file, 0)) + 1
	return counts


static func _file_of(res: Resource) -> String:
	if res == null or res.resource_path == "":
		return ""
	return res.resource_path.get_file().get_basename()


# The display name where one is authored, the filename where it is not, and BOTH where they differ
# -- the filename is the identity a stored pick survives a rename on, so it has to be readable.
static func _label_for(file: String, res: Variant) -> String:
	var authored := ""
	if res != null and res is Resource and "display_name" in res:
		authored = str(res.display_name)
	if authored == "" or authored == file:
		return file
	return "%s  (%s)" % [authored, file]


static func _finding_for(index: int, findings: Array[Dictionary]) -> String:
	for finding: Dictionary in findings:
		if int(finding.get("entry", -1)) == index:
			return str(finding["text"])
	return ""
