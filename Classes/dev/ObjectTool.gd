extends VBoxContainer
class_name ObjectTool

# The dev-tools TILES page (#272 slice 2 as the Objects tab, narrowed by #380, widened by #902):
# everything one TILE answers for, one tile at a time.
#
# THE PAGE IS A SCOPE GRADIENT, narrowest first, and that is the whole design -- three stores whose
# only shared property is that a tile is how you find them:
#
#   This tile            a TileSet custom-data column   Save tile fields
#   Every <Kind> tile    the ignition .tres             Save ground rules
#   Game-wide defaults   the @export declaration        Save game-wide defaults
#
# The middle one is #902's ask (a burnable tick and a turns dial) and the bottom one is the same
# ticket's other half: the dev asked for the look values for objects to be on their individual pages
# "so that they are easier to find", which moved seven rows off the Game tab. A row in either of the
# lower two sections moves a value for MORE than the tile you are looking at, so each section is
# headed with what it moves and each carries its own Save. The storage cannot say it; the page has to.
#
# And the page lists 36 tiles rather than 25 since #902: `object_tiles` is props, and half the grass
# in the game is FLAT, so `grass_basic` had no page at all while its ground's burn rules needed one.
#
# The host is PUSHED in by DevOverlay.attach_3d_host, never looked up -- the same rule that keeps
# the game subtree free of an upward path to Battle3D, and the reason a flat Main.tscn launch
# reports "no 3D host" instead of failing.

var _host: Node3D
var _rows: VBoxContainer
var _status: Label
var _object_picker: OptionButton
var _objects: Array[Dictionary] = []   # ObjectKnobs.authorable_tiles, in picker order
var _picked := 0                       # survives the rebuild every field write triggers
var _save_button: Button
var _globals_button: Button
var _rules_button: Button
# The authored terrain reactions, re-read per rebuild. TerrainReactionCatalog.get_all() caches
# nothing and Godot serves the loads out of its own cache, so this is a directory scan, not six
# reads -- and re-reading is what makes a tick's create or delete visible in the same breath.
var _reactions: Array[TerrainReaction] = []
# Every "inherits X" label now on the page, with the field it speaks for. A GLOBAL write cannot
# rebuild the page (see _write_global), so these are refreshed by hand instead of going stale.
var _inherit_labels: Array[Dictionary] = []
# Edited since the last save (#389). A pure FLAG, and it has to be: there is no baseline here --
# a field write goes straight into the live TileSet, so the honest question is "has the in-memory
# tileset diverged from disk", which any edit answers yes to. Switching the picked object does not
# clear it: edits to object A are still unsaved while you look at object B.
var _dirty := false
# The other two stores' flags, kept apart rather than folded into one: three Saves write three
# different files, so one flag would light a button that has nothing to write.
var _globals_dirty := false
var _rules_dirty := false
# What is on disk for the seven globals -- Reset's target, and what "moved" is measured against.
# Captured at attach and after every landed save, GameTool's own shape.
var _globals_baseline: Array = []
# The ignition reactions edited since the last save. By INSTANCE, because that is what gets written
# and what the running board already holds -- and because switching tiles mid-edit must not lose the
# ground you were tuning a moment ago.
var _staged_rules: Array[TerrainReaction] = []


func _ready() -> void:
	var buttons := HBoxContainer.new()
	_save_button = _button("Save tile fields",
		"Write every per-TILE field into the board's TILESET, where the tile itself carries it.\nThe board already shows them; this is what makes them permanent.",
		_on_save_fields_pressed)
	buttons.add_child(_save_button)
	_rules_button = _button("Save ground rules",
		"Write the burn clock and spread reach into the ground's own ignition reaction.\nThe burnable TICK is not staged -- it creates or deletes that file outright, and asks first.",
		_on_save_rules_pressed)
	buttons.add_child(_rules_button)
	_globals_button = _button("Save game-wide defaults",
		"Write the game-wide defaults you have moved into the declarations that author them.\nThese are one value for every board, not this tile's -- the section says which rows.",
		_on_save_globals_pressed)
	buttons.add_child(_globals_button)
	buttons.add_child(_button("Reset defaults",
		"Put the game-wide defaults back to what is currently saved on disk. The per-tile fields\nand the ground rules are not touched -- they are different files.",
		_on_reset_globals_pressed))
	add_child(buttons)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	_rows = DevWidgets.add_knob_scroll(self)
	_rebuild()


# Called by DevOverlay once battle3d hands it the 3D scene. The 2D game boots first (Godot readies
# children before parents), so this tab always builds its no-host state and then rebuilds here.
func attach_host(host: Node3D) -> void:
	_host = host
	_capture_globals_baseline()
	_rebuild()


func has_host() -> bool:
	return _host != null


func _rebuild() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_inherit_labels.clear()
	if _host == null:
		DevWidgets.add_label(_rows, "No 3D host attached - the flat 2D game has no tiles to tune.")
		return
	_reactions = TerrainReactionCatalog.get_all()
	_build_object_section()


# --- Per-tile fields -------------------------------------------------------------------------

# One tile at a time, picked from a dropdown rather than thirty-six expanded sections: you tune one
# thing and look at it, and a wall of collapsed headers would cost more scrolling than it saves.
# Icon + authored name, the same identity the tile brush's palette shows.
func _build_object_section() -> void:
	DevWidgets.add_heading(_rows, "Tiles")
	var tiles := _tile_set()
	_objects = ObjectKnobs.authorable_tiles(tiles)
	if _objects.is_empty():
		DevWidgets.add_label(_rows, "The board's tileset declares no props and names no tiles.")
		return
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Tile"
	row.add_child(label)
	_object_picker = OptionButton.new()
	for entry: Dictionary in _objects:
		_object_picker.add_icon_item(GridUtils.tile_sprite(entry["source"], entry["coords"]),
			_object_label(entry))
	_object_picker.selected = clampi(_picked, 0, _objects.size() - 1)
	_object_picker.item_selected.connect(_on_object_picked)
	row.add_child(_object_picker)
	_rows.add_child(row)
	var entry: Dictionary = _objects[_object_picker.selected]
	# Narrowest scope first. Each section heads itself with what it moves, so the widening reach is
	# read on the way down the page rather than discovered after a value has already moved.
	DevWidgets.add_heading(_rows, "This tile")
	var fields := ObjectKnobs.fields_for(entry["shape"], GridUtils.prop_lit_of(entry["data"]))
	if fields.is_empty():
		DevWidgets.add_label(_rows,
			"Flat ground - nothing stands on it, so it has no per-tile look fields.")
	_build_field_rows(entry)
	_build_ground_section(entry)
	_build_globals_section(entry)


# The authored name, falling back to the shape and sheet position — an unnamed prop is still a
# legitimate object, and it must not become unpickable just for being unnamed.
func _object_label(entry: Dictionary) -> String:
	var authored := GridUtils.authored_tile_display_name(entry["data"])
	if authored != "":
		return authored
	var shape_name: String = GridUtils.PropShape.keys()[entry["shape"]]
	var coords: Vector2i = entry["coords"]
	return "%s (%d:%d)" % [shape_name, coords.x, coords.y]


func _build_field_rows(entry: Dictionary) -> void:
	var data: TileData = entry["data"]
	var lit := GridUtils.prop_lit_of(data)
	for field: Dictionary in ObjectKnobs.fields_for(entry["shape"], lit):
		if field["type"] == TYPE_BOOL:
			_build_bool_field(data, field)
		else:
			_build_override_field(data, field)


# --- Every tile of this GROUND (#902) ----------------------------------------------------------

# The burnable tick and the burn-turns dial, scoped to the tile's KIND -- because that is where
# flammability is stored. The reaction is found by TerrainReactionCatalog and its FILE is named on
# the page, so there is never a question about which one a tick just wrote.
#
# THE TICK IS NOT STAGED and the other two are, which is a real split rather than an inconsistency.
# A tick creates or deletes a content file and there is nothing to stage: the live board's
# fuel_source is composed from a DIRECTORY SCAN, so a reaction that is not on disk cannot reach the
# game at all. It asks first, the way every dev act that can destroy content does (#380). The dial
# and the reach edit the LOADED resource, which the running board already holds by reference, so the
# fire changes under you and Save writes it down.
func _build_ground_section(entry: Dictionary) -> void:
	var kind := GridUtils.terrain_kind_of(entry["data"])
	if not ObjectKnobs.ground_rules_apply_to(kind):
		return
	var ground := _kind_label(kind)
	DevWidgets.add_heading(_rows, "Every %s tile" % ground)
	var fuel := TerrainReactionCatalog.fuel_for_kind(kind, _reactions)
	var first := _rows.get_child_count()
	DevWidgets.add_checkbox(_rows, "Burnable", fuel != null,
		func(on: bool) -> void: _set_burnable(kind, on))
	_tip_rows(first, "Whether fire spreads on this ground. It is the ground's KIND that answers, not this tile -- the sheet's four grass tiles cannot disagree about whether grass burns, because the rules ask for a kind and get one reaction back. Ticking this writes or DELETES that reaction file, so it asks first.")
	if fuel == null:
		DevWidgets.add_label(_rows,
			"    %s is not fuel. A fire lit on it consumes nothing, so it never goes out and never spreads." % ground)
		return
	var stored := ObjectKnobs.burn_turns_of(fuel)
	if stored < ObjectKnobs.MIN_BURN_TURNS:
		# Only reachable by hand-editing the .tres, and it is the exact state
		# test_fire_clock.gd refuses. Shown rather than silently corrected: writing a number the dev
		# never chose would hide a file CI is about to red.
		DevWidgets.add_label(_rows,
			"    NO BURN CLOCK authored - fire here would never go out. Move the dial to author one.")
	first = _rows.get_child_count()
	var turns := DevWidgets.add_spinbox(_rows, "Burn turns",
		float(clampi(stored, ObjectKnobs.MIN_BURN_TURNS, ObjectKnobs.MAX_BURN_TURNS)),
		func(value: float) -> void: _set_turns(fuel, int(value)))
	# Range AFTER the value, and the value clamped into it first: a SpinBox emits value_changed when
	# min_value drags it up, so an unclamped seed would write a number into the file on page open.
	turns.min_value = ObjectKnobs.MIN_BURN_TURNS
	turns.max_value = ObjectKnobs.MAX_BURN_TURNS
	_tip_rows(first, "How many round cycles fire lasts on this ground before its fuel is spent and the cell goes SCORCHED. THE FLOOR IS ONE: an absent clock means 'burns forever', which is real but is spelled by ground that is NOT FUEL at all -- untick Burnable above. A shipped fuel with no clock is a field that never goes out, and the suite refuses one.")
	first = _rows.get_child_count()
	DevWidgets.add_checkbox(_rows, "Spreads to corners", fuel.spread_and_a_half,
		func(on: bool) -> void: _set_reach(fuel, on))
	_tip_rows(first, "Whether fire in this ground throws to a cell's CORNERS as well as its sides -- the dev's 1.5 tiles a turn (#891). Read off the ground that is ALIGHT, never the ground catching: tall flames throw sparks further, so tall grass reaches diagonally into ordinary grass while ordinary grass takes no corner however flammable that corner is.")
	DevWidgets.add_label(_rows, "    authored in %s" % fuel.resource_path)


# --- The game-wide defaults (#902, off the Game tab's World group) ------------------------------

# The seven rows the per-tile fields above fall back to, drawn here because the dev asked for the
# look values for objects to be on their individual pages. Offered by the same shape-and-lit filter
# as the fields, so a crate is never shown a tuft density.
#
# A ROW HERE MOVES EVERY BOARD. The heading and the note say so, and each row's own tooltip carries
# GameKnobs' GAME-WIDE line -- the same sentence the Game tab appends, from the same one place, with
# only this page's Save named differently.
func _build_globals_section(entry: Dictionary) -> void:
	var globals := ObjectKnobs.globals_for(entry["shape"], GridUtils.prop_lit_of(entry["data"]))
	if globals.is_empty():
		return
	DevWidgets.add_heading(_rows, "Game-wide defaults")
	DevWidgets.add_label(_rows,
		"    One value for EVERY board and every tile, not this one's. The rows above inherit these.")
	for knob: Dictionary in globals:
		DevWidgets.add_knob_row(_rows, knob, LookKnobs.read(_host, knob),
			func(value: Variant) -> void: _write_global(knob, value),
			GameKnobs.declaration_tip(knob, "Save game-wide defaults"))


# NOT through _write_field, which rebuilds the whole page: that frees the slider under the mouse
# mid-drag, and these are drag rows. BoardMirror's own setters sweep the board, so the world follows
# with no rebuild at all. What does not follow is the "inherits X" text a few rows up -- that is
# refreshed by hand rather than left to say a number the board has stopped using.
func _write_global(knob: Dictionary, value: Variant) -> void:
	LookKnobs.write(_host, knob, value)
	_globals_dirty = true
	_refresh_globals_mark()
	_refresh_inherit_labels()


func _refresh_inherit_labels() -> void:
	for row: Dictionary in _inherit_labels:
		var label := row["label"] as Label
		if is_instance_valid(label):
			label.text = "    inherits %s" % _shown(_resolved_value(row["data"], row["field"]))


# --- Ticking a ground burnable, and un-ticking it -----------------------------------------------

func _set_burnable(kind: Terrain.Kind, on: bool) -> void:
	var path := ObjectKnobs.ignition_path_for(kind, _reactions)
	var dialog: ConfirmationDialog
	if on:
		dialog = DevWidgets.confirm(self,
			"Make every %s tile burnable? This writes %s." % [_kind_label(kind), path],
			func() -> void: _create_ignition(kind, path))
	else:
		dialog = DevWidgets.confirm_delete(self, path, func() -> void: _delete_ignition(path))
	# The box has already moved by the time the dialog is up, so a cancel has to put it back --
	# otherwise the page shows a state the disk does not have.
	dialog.canceled.connect(_rebuild)


func _create_ignition(kind: Terrain.Kind, path: String) -> void:
	if DevWidgets.refuse_existing_file(path, "terrain reaction", _status):
		return
	if not DevWidgets.save_over(ObjectKnobs.make_ignition(kind), path, _status):
		return
	_after_ground_change("%s burns now - %s" % [_kind_label(kind), path])


func _delete_ignition(path: String) -> void:
	if not DevWidgets.delete_saved_file(path, "terrain reaction", _status):
		return
	_after_ground_change("%s deleted - that ground is not fuel any more." % path)


# The live board's fuel_source is a Callable composed at boot (game.gd) over the reaction list AS IT
# WAS THEN, so a ground that has just become fuel -- or stopped being it -- is invisible to the
# running fire until the source is composed again. A born-dead control otherwise (#264's shape).
#
# ONLY on create and delete, deliberately. A dial or reach edit mutates the LOADED resource, and
# that closure holds the same instance (ContentRepair.load_tolerant is ResourceLoader.load, which
# serves Godot's cache), so the running board reads the new number with no re-wire at all. Doing it
# everywhere would work and would hide that the cache is load-bearing here.
func _rewire_fuel() -> void:
	if _host == null or _host.game == null or _host.game.grid == null:
		return
	if _host.game.terrain_states == null:
		return
	_host.game.terrain_states.fuel_source = TerrainReactionCatalog.fuel_source_for(_host.game.grid)


func _after_ground_change(message: String) -> void:
	_rewire_fuel()
	_rebuild()   # re-reads the directory, so the tick and the file agree again
	_status.text = message


func _set_turns(fuel: TerrainReaction, turns: int) -> void:
	fuel.add_state_turns[Terrain.TileState.BURNING] = turns
	_touch_rules(fuel)


func _set_reach(fuel: TerrainReaction, wide: bool) -> void:
	fuel.spread_and_a_half = wide
	_touch_rules(fuel)


func _kind_label(kind: Terrain.Kind) -> String:
	return String(Terrain.Kind.keys()[kind]).capitalize()


# The one field with no global behind it, so no Inherit row: off IS the answer for most tiles.
func _build_bool_field(data: TileData, field: Dictionary) -> void:
	var first := _rows.get_child_count()
	DevWidgets.add_checkbox(_rows, field["label"], data.get_custom_data(field["layer"]),
		func(on: bool) -> void: _write_field(data, field["layer"], on))
	_tip_rows(first, field["tip"])


# An override row is TWO controls and that is the design: the checkbox says whether this object has
# an opinion, the control says what it is. Inheriting SHOWS the value it inherits rather than an
# empty slot -- a row that cannot say what it falls back to sends you looking for the global.
func _build_override_field(data: TileData, field: Dictionary) -> void:
	var layer: String = field["layer"]
	var is_color: bool = field["type"] == TYPE_COLOR
	var is_int: bool = field["type"] == TYPE_INT
	var authored: Variant
	if is_color:
		authored = GridUtils.prop_color_override_of(data, layer)
	elif is_int:
		authored = GridUtils.prop_int_override_of(data, layer)
	else:
		authored = GridUtils.prop_override_of(data, layer)
	var inherited: bool = GridUtils.is_inherited_color(authored) if is_color \
		else GridUtils.is_inherited(authored)
	var resolved: Variant = _resolved_value(data, field)
	var first := _rows.get_child_count()
	DevWidgets.add_checkbox(_rows, "%s - inherit" % field["label"], inherited,
		func(on: bool) -> void:
			# Ticking gives the value back to the fallback; unticking adopts whatever it currently
			# RESOLVES to, so turning an override on never moves the board by itself -- except where it
			# cannot, which _adopted_value owns.
			_write_field(data, layer, _inherit_value(field) if on else _adopted_value(field, resolved)))
	if inherited:
		DevWidgets.add_label(_rows, "    inherits %s" % _shown(resolved))
		# Kept so a game-wide write can refresh it in place: that write cannot rebuild the page
		# (_write_global says why), and a row still naming the old default is a row that lies.
		_inherit_labels.append({"label": _rows.get_child(_rows.get_child_count() - 1),
			"data": data, "field": field})
	elif is_color:
		DevWidgets.add_color(_rows, field["label"], authored,
			func(picked: Color) -> void: _write_field(data, layer, picked))
	else:
		# An int column stores whole units, so its row is a step-1 slider and the write is ROUNDED:
		# a float landing in an int layer is a value the loader would have to guess about.
		DevWidgets.add_slider(_rows, field["label"], authored,
			field["min"], field["max"], field["step"],
			func(moved: float) -> void: _write_field(data, layer, int(moved) if is_int else moved))
	_tip_rows(first, field["tip"])


# The value that means "no opinion", per storage type. All three are the sentinels GridUtils
# declares; reading it off the FIELD is what keeps a float zero out of an int layer.
func _inherit_value(field: Dictionary) -> Variant:
	match field["type"]:
		TYPE_COLOR: return GridUtils.INHERIT_COLOR
		TYPE_INT: return 0
	return GridUtils.INHERIT


# What unticking "inherit" writes. Normally the value the field already RESOLVES to, so switching a
# field to authored does not move the board -- but that invariant is unreachable when the resolved
# value IS the sentinel, and then writing it back would re-tick the box the click just cleared. The
# row would be permanently stuck inheriting, which is precisely how #660 shipped: a BILLBOARD's
# rules height resolves to 0 by design (a lantern stops no shot), so a TREE could never be given a
# height at all -- the one thing the field was offered to billboards FOR.
#
# So a sentinel resolve adopts the smallest authorable value instead. Moving the board by one unit
# is a worse outcome than the invariant promises and a far better one than a control that cannot be
# operated. Reachable for the float rows too, not just the int one: any of them whose GLOBAL is
# tuned to 0 in the Game tab lands here the same way.
func _adopted_value(field: Dictionary, resolved: Variant) -> Variant:
	if field["type"] == TYPE_COLOR or not GridUtils.is_inherited(resolved):
		return resolved
	return int(field["min"]) if field["type"] == TYPE_INT else float(field["min"])


# What this field actually comes out as for this tile — asked of whoever OWNS its fallback. That is
# BoardMirror for the presentation rows, which own the global-then-override layering; the panel
# deliberately does not re-derive it.
func _resolved_value(data: TileData, field: Dictionary) -> Variant:
	# A RULES column falls back to its SHAPE, not to a global, and GridUtils answers that with no 3D
	# host at all -- so it resolves before the mirror is even looked up, and the row reads correctly
	# in the tab's no-host state instead of reporting 0.0.
	if field["layer"] == "prop_rule_height":
		return GridUtils.prop_rule_height_of(data)
	var mirror := _mirror()
	if mirror == null:
		return 0.0
	match field["layer"]:
		"prop_light_energy": return mirror.light_energy_for(data)
		"prop_light_range": return mirror.light_range_for(data)
		"prop_light_height": return mirror.light_height_for(data)
		"prop_light_color": return mirror.light_color_for(data)
		"prop_height_scale": return mirror.block_height_for(data)
		"prop_tuft_scale": return mirror.tuft_scale_for(data)
	push_error("ObjectTool: field '%s' has no resolver" % field["layer"])
	return 0.0


func _shown(value: Variant) -> String:
	if value is Color:
		return DevWidgets.literal_for(value)
	if value is int:
		return str(value)
	return String.num(value, 3)


# Written LIVE, then the board re-stands its props so you can see it. Saving is a separate act --
# the same split every dev tab makes between editing and committing.
func _write_field(data: TileData, layer: String, value: Variant) -> void:
	data.set_custom_data(layer, value)
	_touch()   # the one write funnel: every field row routes through here
	var host := _host
	if host != null:
		host.rebuild_props()
	_rebuild()


func _on_object_picked(index: int) -> void:
	_picked = index
	_rebuild()


func _tip_rows(first: int, tip: String) -> void:
	var wrapped := DevWidgets.wrap_tooltip(tip)
	for i in range(first, _rows.get_child_count()):
		DevWidgets.apply_tooltip(_rows.get_child(i), wrapped)


func _tile_set() -> TileSet:
	if _host == null or _host.game == null or _host.game.grid == null:
		return null
	return _host.game.grid.tile_set


func _mirror() -> BoardMirror:
	if _host == null:
		return null
	return _host.get_node_or_null(^"BoardMirror") as BoardMirror


# Asks first (#380's convention: anything that can overwrite settings does) -- this rewrites the
# shared tileset file, which every board draws from.
func _on_save_fields_pressed() -> void:
	var tiles := _tile_set()
	if tiles == null:
		_status.text = "No board tileset attached - nothing to save."
		return
	DevWidgets.confirm(self,
		"Save the per-tile fields into %s? The saved tileset is replaced." % tiles.resource_path,
		func() -> void: _save_fields_confirmed(tiles))


func _save_fields_confirmed(tiles: TileSet) -> void:
	if ObjectKnobs.save_fields(tiles, _status):
		_clear_dirty()   # on LANDED, never on intent -- the press only opens the confirmation
		_status.text = "Tile fields saved to %s" % tiles.resource_path


# --- Saving the ground rules --------------------------------------------------------------------

func _on_save_rules_pressed() -> void:
	if _staged_rules.is_empty():
		_status.text = "No ground rule has moved off what is saved."
		return
	var names: PackedStringArray = PackedStringArray()
	for fuel: TerrainReaction in _staged_rules:
		names.append(fuel.resource_path)
	DevWidgets.confirm(self,
		"Write %d ignition reaction(s)? The saved versions are replaced.\n\n%s"
			% [_staged_rules.size(), "\n".join(names)],
		_save_rules_confirmed)


func _save_rules_confirmed() -> void:
	var landed: Array[TerrainReaction] = []
	for fuel: TerrainReaction in _staged_rules:
		if DevWidgets.save_over(fuel, fuel.resource_path, _status):
			landed.append(fuel)
	# What LANDED, never what was asked for: a reaction whose write failed is still unsaved, and
	# adopting it would hide the failure behind a clean-looking panel (GameTool's rule).
	for fuel: TerrainReaction in landed:
		_staged_rules.erase(fuel)
	_rules_dirty = not _staged_rules.is_empty()
	_refresh_rules_mark()
	_status.text = "Saved %d of %d ground rule(s)." % [landed.size(), landed.size() + _staged_rules.size()]


# --- Saving the game-wide defaults ----------------------------------------------------------------

func _capture_globals_baseline() -> void:
	_globals_baseline = KnobSource.capture_baseline(_host, ObjectKnobs.GLOBALS)
	_refresh_globals_dirty()


func changed_globals() -> PackedInt32Array:
	return KnobSource.changed_indices(_host, ObjectKnobs.GLOBALS, _globals_baseline)


func _on_save_globals_pressed() -> void:
	if _host == null:
		_status.text = "No 3D host attached - nothing to save."
		return
	var moved := changed_globals()
	if moved.is_empty():
		_status.text = "No game-wide default has moved off what is saved."
		return
	var labels: PackedStringArray = PackedStringArray()
	for i: int in moved:
		labels.append(String(ObjectKnobs.GLOBALS[i]["label"]))
	DevWidgets.confirm(self,
		"Write %d GAME-WIDE value(s) into the scripts that declare them? Every board changes.\n\n%s"
			% [moved.size(), "\n".join(labels)],
		func() -> void: _save_globals_confirmed(moved))


func _save_globals_confirmed(moved: PackedInt32Array) -> void:
	var report := ObjectKnobs.save_globals_to_source(_host, moved)
	for landed: Dictionary in report["saved"]:
		var i: int = landed["index"]
		_globals_baseline[i] = LookKnobs.read(_host, ObjectKnobs.GLOBALS[i])
	var parts: PackedStringArray = PackedStringArray()
	var written: PackedStringArray = report["written"]
	var failed: PackedStringArray = report["failed"]
	if not written.is_empty():
		parts.append("Saved: %s" % ", ".join(written))
	if not failed.is_empty():
		parts.append("FAILED: %s" % ", ".join(failed))
	_refresh_globals_dirty()   # the truth after a partial save, not a blind clear
	_status.text = " | ".join(parts)


func _on_reset_globals_pressed() -> void:
	if _host == null:
		return
	for i in ObjectKnobs.GLOBALS.size():
		var saved: Variant = _globals_baseline[i] if i < _globals_baseline.size() else null
		if typeof(saved) != TYPE_NIL:
			LookKnobs.write(_host, ObjectKnobs.GLOBALS[i], saved)
	_rebuild()   # redraw every widget off the restored values -- one path, every widget kind
	_refresh_globals_dirty()
	_status.text = "Game-wide defaults back to what is saved on disk."


# --- The unsaved marker (#389) --------------------------------------------------------------
#
# THREE flags, because the page has three Saves aimed at three files. One flag would light a button
# that has nothing to write, which is the same lie as no marker at all.

func has_unsaved_changes() -> bool:
	return _dirty or _globals_dirty or _rules_dirty


func _touch() -> void:
	_dirty = true
	_refresh_save_mark()


func _touch_rules(fuel: TerrainReaction) -> void:
	if not _staged_rules.has(fuel):
		_staged_rules.append(fuel)
	_rules_dirty = true
	_refresh_rules_mark()


func _clear_dirty() -> void:
	_dirty = false
	_refresh_save_mark()


func _refresh_save_mark() -> void:
	if is_instance_valid(_save_button):
		DevWidgets.mark_unsaved(_save_button, "Save tile fields", _dirty)


func _refresh_rules_mark() -> void:
	if is_instance_valid(_rules_button):
		DevWidgets.mark_unsaved(_rules_button, "Save ground rules", _rules_dirty)


# RE-DERIVED off the baseline rather than latched: a partial save leaves real edits behind, and a
# blind clear would hide the failure. GameTool's rule, and cheap here for its reason -- once per
# save, never per drag tick (a drag latches the flag instead, in _write_global).
func _refresh_globals_dirty() -> void:
	_globals_dirty = _host != null and not changed_globals().is_empty()
	_refresh_globals_mark()


func _refresh_globals_mark() -> void:
	if is_instance_valid(_globals_button):
		DevWidgets.mark_unsaved(_globals_button, "Save game-wide defaults", _globals_dirty)

func _button(text: String, tooltip: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.pressed.connect(on_pressed)
	return button
