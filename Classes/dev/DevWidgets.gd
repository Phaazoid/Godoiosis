extends Object
class_name DevWidgets

# The dev panels' shared widget kit: the builders every tool draws its rows with (knobs, reflective
# resource forms, pickers) and the guards every tool saves through (name refusal, overwrite confirm,
# the single ResourceSaver door below). Never shown to a player.

# One knob row, whichever panel is drawing it (#212's Moods tab, #272's Object tab). The widget is
# picked from the LIVE VALUE's type rather than from a column on the table, which is why one builder
# serves both -- and why a knob whose property does not resolve draws a labelled failure instead of
# a row that edits nothing. The value and the writer are PASSED, so this stays ignorant of which
# host either panel is bound to.
# Returns EVERY control it appended, so a panel that filters rows can hide one without knowing what
# shape it is -- a slider is a row, a colour is several, an unresolved knob is a bare label (#520
# 2b slice 2, for the Playback page's profile and action filters). Existing callers ignore it.
static func add_knob_row(rows: VBoxContainer, knob: Dictionary, value: Variant,
		on_write: Callable, tip: String) -> Array[Node]:
	var label: String = knob["label"]
	var first := rows.get_child_count()
	if typeof(value) == TYPE_NIL:
		var where := "%s:%s" % [knob.get("node", "?"), knob.get("prop", "?")]
		add_label(rows, "%s - UNRESOLVED (%s)" % [label, where])
		push_error("knob does not resolve: %s" % where)
		return _added_since(rows, first)
	if knob.has("options"):
		var options: Array = knob["options"]
		var current: int = int(value)
		var current_label: String = options[current] if current >= 0 and current < options.size() else ""
		add_option(rows, label, options, current_label,
			func(picked: String) -> void: on_write.call(options.find(picked)))
	else:
		match typeof(value):
			TYPE_BOOL:
				add_checkbox(rows, label, value, func(on: bool) -> void: on_write.call(on))
			TYPE_COLOR:
				add_color(rows, label, value, func(picked: Color) -> void: on_write.call(picked))
			_:
				add_slider(rows, label, value, knob["min"], knob["max"], knob["step"],
					func(moved: float) -> void: on_write.call(moved))
	# Every control the row added, so hovering the slider handle answers as well as the label.
	var added := _added_since(rows, first)
	for control in added:
		apply_tooltip(control, tip)
	return added


# What a row put into `rows` -- the same span apply_tooltip walks, returned so a caller can keep it.
static func _added_since(rows: VBoxContainer, first: int) -> Array[Node]:
	var added: Array[Node] = []
	for i in range(first, rows.get_child_count()):
		added.append(rows.get_child(i))
	return added


# The GDScript spelling of a tuned value. Every reader writes it into a source declaration --
# GameKnobs and ObjectKnobs into an @export default, KnobSource into a static var -- so it belongs
# to none of their panels.
static func literal_for(value: Variant) -> String:
	match typeof(value):
		TYPE_BOOL:
			return "true" if value else "false"
		TYPE_FLOAT:
			return String.num(value, 4)
		TYPE_COLOR:
			var color: Color = value
			return "Color(%s, %s, %s, %s)" % [String.num(color.r, 4), String.num(color.g, 4),
				String.num(color.b, 4), String.num(color.a, 4)]
		TYPE_VECTOR2:
			var vec2: Vector2 = value
			return "Vector2(%s, %s)" % [String.num(vec2.x, 4), String.num(vec2.y, 4)]
		TYPE_VECTOR3:
			var vec3: Vector3 = value
			return "Vector3(%s, %s, %s)" % [String.num(vec3.x, 4), String.num(vec3.y, 4),
				String.num(vec3.z, 4)]
	return str(value)


# The scrolling half of a knob page -- the ScrollContainer plus the row VBox that goes in it,
# which Moods, Game and Objects each built identically before #403. Returns the row container, so
# a caller keeps the only thing it ever used.
#
# SCROLL_MODE_AUTO on the horizontal axis is the load-bearing bit, and it is the fix rather than
# the tidy-up. A ScrollContainer with an axis DISABLED declares its content's full width as its own
# MINIMUM, so a knob page pushed its widest row all the way up to the window: an add_color row is
# 841px (label 190 + swatch + four 0-255 slider/SpinBox pairs, whose SpinBoxes measure 87 each
# however small a minimum they are asked for), and the dev window could not be narrowed below it
# without the panel running off the right edge with no scrollbar to say so. Scrolling instead
# costs nothing at the default size -- the rows still EXPAND to fill a window with room -- and
# degrades to a scrollbar rather than to clipping when there is not.
#
# The page NOT dictating the window's width is why tests/dev/test_dev_window_fit.gd measures the
# rows rather than this container: the container's minimum is now near zero by design.
static func add_knob_scroll(parent: Node, page_name := "") -> VBoxContainer:
	var scroll := ScrollContainer.new()
	if page_name != "":
		scroll.name = page_name   # a TabContainer titles its tab from the child's name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	return rows


static func add_label(container: Node, text: String) -> void:
	var label := Label.new()
	label.text = text
	container.add_child(label)

# Returns the SpinBox (add_slider/add_option/add_lineedit's convention), so a caller can narrow its
# range or write a value back into the widget on a refresh.
static func add_spinbox(container: Node, label_text: String, initial_value: float, on_change: Callable) -> SpinBox:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	var spinbox := SpinBox.new()
	spinbox.min_value = -999
	spinbox.max_value = 999
	spinbox.value = initial_value
	spinbox.value_changed.connect(on_change)
	row.add_child(label)
	row.add_child(spinbox)
	container.add_child(row)
	return spinbox

# Feel work is DRAG work: a value you sweep while watching the board, with the number beside it
# so a landed setting can be read off. add_spinbox is the typing form; this is the hunting form.
# Returns the slider so a caller can write a value back into the widget (the Moods panel's Reset).
static func add_slider(container: Node, label_text: String, initial_value: float,
		min_value: float, max_value: float, step: float, on_change: Callable) -> HSlider:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(190, 0)
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = initial_value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(120, 0)
	var readout := Label.new()
	readout.custom_minimum_size = Vector2(64, 0)
	readout.text = format_decimals(initial_value, step)
	slider.value_changed.connect(func(v: float) -> void:
		readout.text = format_decimals(v, step)
		on_change.call(v))
	row.add_child(label)
	row.add_child(slider)
	row.add_child(readout)
	container.add_child(row)
	return slider


const COLOR_CHANNELS := ["R", "G", "B", "A"]   # index == Color's own component order

# NO ColorPicker, deliberately. ColorPickerButton froze the dev window solid the first time one
# was opened (dev, 2026-08-14) -- this window is a real OS window that embeds its own subwindows
# while the project does not, and CLAUDE.md's sharp edge #4 says prefer Control-based. A plain
# inline ColorPicker is not the escape either: it carries its own menus for colour mode and picker
# shape, i.e. the same family one layer down. Four component sliders plus a live swatch are
# Control-only by construction, and they match the drag idiom the rest of the panel already uses.
# (OptionButton popups are fine here -- every other dev tab uses them -- so this is a ban on the
# ColorPicker family, not on popups.)
static func add_color(container: Node, label_text: String, initial_value: Color,
		on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(190, 0)
	row.add_child(label)
	var swatch := ColorRect.new()
	swatch.color = initial_value
	swatch.custom_minimum_size = Vector2(30, 0)
	row.add_child(swatch)
	# The LIVE colour, boxed in a Dictionary because a GDScript lambda captures a local by VALUE --
	# a plain Color local could not carry an edit from one channel's callback to the next. Editing
	# one channel replaces only that component, so the untouched three keep their authored float
	# precision instead of being re-derived through 8-bit and reading as changed.
	var state := {"color": initial_value}
	for i in COLOR_CHANNELS.size():
		var tag := Label.new()
		tag.text = COLOR_CHANNELS[i]
		row.add_child(tag)
		# Slider AND field both work in 0-255, the scale you read off a hex code. One scale, so
		# typing a number and dragging the handle can never disagree about what the value is.
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 255.0
		slider.step = 1.0
		slider.value = roundi(initial_value[i] * 255.0)
		slider.custom_minimum_size = Vector2(44, 0)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(slider)
		var field := SpinBox.new()
		field.min_value = 0
		field.max_value = 255
		field.step = 1
		field.value = slider.value
		field.custom_minimum_size = Vector2(58, 0)
		row.add_child(field)
		# Each drives the other with set_value_no_signal, or the two would bounce a change back
		# and forth forever.
		slider.value_changed.connect(func(v: float) -> void:
			field.set_value_no_signal(v)
			_write_channel(state, i, v, swatch, on_change))
		field.value_changed.connect(func(v: float) -> void:
			slider.set_value_no_signal(v)
			_write_channel(state, i, v, swatch, on_change))
	container.add_child(row)
	return row


static func _write_channel(state: Dictionary, index: int, value_255: float,
		swatch: ColorRect, on_change: Callable) -> void:
	var color: Color = state["color"]
	color[index] = value_255 / 255.0
	state["color"] = color
	swatch.color = color
	on_change.call(color)


# Godot's tooltip does NOT reliably walk up to a parent -- a slider or SpinBox under the cursor
# has mouse_filter STOP and answers for itself -- so a row's tooltip has to be set on every
# control in it, or hovering the handle (the thing you are actually dragging) shows nothing.
static func apply_tooltip(node: Node, text: String) -> void:
	var control := node as Control
	if control != null:
		control.tooltip_text = text
	for child in node.get_children():
		apply_tooltip(child, text)


# A tooltip is a plain Label with no autowrap, so a long one renders as one very wide line off
# the edge of the screen. Wrapping is done HERE rather than by hand-typed newlines in the text so
# the width holds no matter how the wording is later edited. Existing newlines are kept as
# paragraph breaks.
static func wrap_tooltip(text: String, width := 74) -> String:
	var out: PackedStringArray = PackedStringArray()
	for paragraph: String in text.split("\n"):
		var line := ""
		for word: String in paragraph.split(" ", false):
			if line == "":
				line = word
			elif line.length() + 1 + word.length() <= width:
				line += " " + word
			else:
				out.append(line)
				line = word
		out.append(line)
	return "\n".join(out)


# How many decimals a step implies -- 0.005 prints 3, 1.0 prints 0. Derived rather than declared
# so a knob's precision cannot disagree with the step it moves in.
static func format_decimals(value: float, step: float) -> String:
	var decimals := 0
	var remaining := absf(step)
	while remaining > 0.0 and remaining < 1.0 and decimals < 5:
		remaining *= 10.0
		decimals += 1
	return String.num(value, decimals)


static func add_checkbox(container: Node, label_text: String, initial_value: bool, on_change: Callable, tooltip := "") -> void:
	var checkbox := CheckBox.new()
	checkbox.text = label_text
	checkbox.button_pressed = initial_value
	checkbox.toggled.connect(on_change)
	checkbox.tooltip_text = tooltip
	container.add_child(checkbox)

# Returns the row (like add_lineedit) so callers can show/hide it with a mode (#174).
static func add_option(container: Node, label_text: String, options: Array, current: String, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	var option := OptionButton.new()
	for i in options.size():
		option.add_item(options[i])
		if options[i] == current:
			option.select(i)
	option.item_selected.connect(func(idx): on_change.call(options[idx]))
	row.add_child(label)
	row.add_child(option)
	container.add_child(row)
	return row

static func add_lineedit(container: Node, label_text: String, initial_value: String, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	var edit := LineEdit.new()
	edit.text = initial_value
	edit.custom_minimum_size = Vector2(100, 0)
	edit.text_changed.connect(on_change)
	row.add_child(label)
	row.add_child(edit)
	container.add_child(row)
	return row

# Parse an enum @export hint_string into ordered {name, value} entries. Godot emits
# "Name0,Name1,..." for contiguous 0-based enums, or "Name:Val,..." when the values are
# explicit / non-sequential. Handle both so the dropdown maps labels -> real enum ints.
static func parse_enum_hint(hint_string: String) -> Array:
	var entries := []
	var parts := hint_string.split(",", false)
	for i in parts.size():
		var part: String = parts[i]
		var colon := part.find(":")
		if colon != -1:
			entries.append({"name": part.substr(0, colon), "value": int(part.substr(colon + 1))})
		else:
			entries.append({"name": part, "value": i})
	return entries

# Dropdown for an int-backed enum property: shows the names, reports back the enum int.
static func add_enum_option(container: Node, label_text: String, hint_string: String, current: int, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	var option := OptionButton.new()
	var entries := parse_enum_hint(hint_string)
	for i in entries.size():
		option.add_item(entries[i]["name"])
		if entries[i]["value"] == current:
			option.select(i)
	option.item_selected.connect(func(idx): on_change.call(entries[idx]["value"]))
	row.add_child(label)
	row.add_child(option)
	container.add_child(row)

# A scaling blend as four STEAL-TO-BALANCE sliders (#485, dev call 2026-08-25). Drag one up and the
# others give up the difference in proportion; the total is ALWAYS Stats.BLEND_TOTAL, so an invalid
# blend is unrepresentable rather than refused after the fact. That is what makes the dev's rule
# literal -- "STR is at 55? That means STR scaling is 55%" -- instead of a claim the panel has to
# police.
#
# LOWERING a stat that holds everything is REFUSED (the slider snaps back), because the points have
# nowhere to go: the other three are at zero and handing them an even split would author a mix
# nobody asked for. The gesture is always "drag the stat you WANT up", which is also what removes
# the deadlock a total-is-100 guard would otherwise create -- every weapon starts at exactly 100, so
# a rule that refuses to add while the total is full refuses the very first edit.
static func add_blend_sliders(container: Node, blend: Dictionary, on_change: Callable, tooltip := "") -> void:
	var first := container.get_child_count()
	var sliders: Dictionary[Stats.Stat, HSlider] = {}
	var labels: Dictionary[Stats.Stat, Label] = {}
	var guard := [false]   # array so the lambdas share one cell; a bare bool captures by value
	for stat: Stats.Stat in Stats.SCALING_STATS:
		var key := stat
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = Stats.Stat.keys()[key]
		name_label.custom_minimum_size = Vector2(48, 0)
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = Stats.BLEND_TOTAL
		slider.step = Stats.BLEND_STEP
		slider.custom_minimum_size = Vector2(180, 0)
		slider.value = blend.get(key, 0)
		var pct := Label.new()
		# The READOUT comes off the dictionary, never off the slider. Godot snaps a Range to its
		# step on assignment (measured: 33 with step 5 reads back 35), so a hand-edited .tres
		# holding an off-grain weight would otherwise be reported as a value its file does not
		# hold -- the "only the FILE shows it" divergence, one widget along. The handle sits at
		# the nearest legal notch; the number tells the truth until the first drag reconciles them.
		pct.text = "%d%%" % int(blend.get(key, 0))
		pct.custom_minimum_size = Vector2(44, 0)
		row.add_child(name_label)
		row.add_child(slider)
		row.add_child(pct)
		container.add_child(row)
		sliders[key] = slider
		labels[key] = pct
		slider.value_changed.connect(func(v: float):
			if guard[0]:
				return
			guard[0] = true
			_rebalance_blend(blend, key, int(v), sliders, labels)
			guard[0] = false
			on_change.call()
		)
	_tip_rows_from(container, first, tooltip)


# Give `moved` the value it was dragged to and spread the remainder across the other three in
# proportion to what they already hold, so the total lands exactly on BLEND_TOTAL. Integer split
# with the leftover handed to the largest fractional parts -- a plain floor loses up to three
# points, which would show as a total of 97 on screen.
static func _rebalance_blend(blend: Dictionary, moved: Stats.Stat, value: int,
		sliders: Dictionary[Stats.Stat, HSlider], labels: Dictionary[Stats.Stat, Label]) -> void:
	var others: Array[Stats.Stat] = []
	var others_total := 0
	for stat: Stats.Stat in Stats.SCALING_STATS:
		if stat == moved:
			continue
		others.append(stat)
		others_total += blend.get(stat, 0)

	var remainder := Stats.BLEND_TOTAL - value
	if others_total == 0 and remainder > 0:
		# Nowhere to put the points -- refuse, and put the slider back where it was.
		sliders[moved].set_value_no_signal(blend.get(moved, 0))
		return

	blend[moved] = value
	# Split in STEPS rather than points, so every share lands on a notch a slider can actually
	# show. BLEND_STEP divides BLEND_TOTAL and Godot snaps `value` to the step before this is
	# called, so the remainder is a whole number of steps by construction.
	var steps := remainder / Stats.BLEND_STEP
	var shares: Array[int] = []
	var fractions: Array[float] = []
	var handed := 0
	for stat: Stats.Stat in others:
		var exact := 0.0 if others_total == 0 else float(blend.get(stat, 0)) * steps / others_total
		var whole := int(floor(exact))
		shares.append(whole)
		fractions.append(exact - whole)
		handed += whole
	# Hand the rounding leftover to the largest fractional parts, biggest first.
	while handed < steps:
		var best := 0
		for i in range(1, fractions.size()):
			if fractions[i] > fractions[best]:
				best = i
		shares[best] += 1
		fractions[best] = -1.0
		handed += 1

	for i in range(others.size()):
		blend[others[i]] = shares[i] * Stats.BLEND_STEP
	# ZERO MEANS ABSENT, add_stat_dict's rule one widget along: a stat contributing nothing is not
	# an entry worth storing, and writing it grows every saved attack four keys wide with stats
	# nobody set. The math cannot tell the difference (a 0 weight adds 0 to the total either way),
	# so only the FILE shows it -- which is how this shipped and was caught by reading a save diff.
	for stat: Stats.Stat in Stats.SCALING_STATS:
		var held: int = blend.get(stat, 0)
		if held == 0:
			blend.erase(stat)
		sliders[stat].set_value_no_signal(held)
		labels[stat].text = "%d%%" % held


# A SPARSE Dictionary[Stats.Stat, int] -- one spinbox per stat, and ZERO MEANS ABSENT: the key is
# erased rather than stored as 0. That is what makes it different from the dense base-stat grids
# the character and unit editors draw; those author what a stat IS, so every key belongs in the
# file. This authors a DELTA, where "no entry" and "+0" are the same fact, and storing both would
# grow a saved .tres a key for every stat nobody touched.
#
# It exists because build_resource_editor draws no dictionary at all -- its match has arms for
# int/float/bool/string/object and nothing else -- so every Dictionary field in the project has
# been silently undrawn (WeaponModData.scaling_change, ArmorData.stat_modifiers).
static func add_stat_dict(container: Node, label_text: String, values: Dictionary, tooltip := "") -> void:
	var first := container.get_child_count()
	add_label(container, label_text)
	var grid := GridContainer.new()
	grid.columns = 4
	for stat: Stats.Stat in Stats.STAT_DEFAULTS:
		var key := stat
		var name_label := Label.new()
		name_label.text = Stats.Stat.keys()[key]
		name_label.custom_minimum_size = Vector2(48, 0)
		var spin := SpinBox.new()
		spin.min_value = -99
		spin.max_value = 99
		spin.value = values.get(key, 0)
		spin.value_changed.connect(func(v: float):
			if int(v) == 0:
				values.erase(key)
			else:
				values[key] = int(v)
		)
		grid.add_child(name_label)
		grid.add_child(spin)
	container.add_child(grid)
	_tip_rows_from(container, first, tooltip)   # pre-wrapped, as property_tip already returns

static func build_resource_editor(container: Node, resource: Resource, rebuild: Callable, skip: Array = []) -> void:
	for prop in resource.get_property_list():
		if prop.name in skip:
			continue
		var is_exported_var = (prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0 and (prop.usage & PROPERTY_USAGE_EDITOR) != 0
		if not is_exported_var:
			continue
		_add_property_control(container, resource, prop, rebuild)
		
# The text for one reflectively-drawn field, from the resource's own property_tips() -- which each
# class overrides and merges into its parent's, so WeaponAttackData answers for AttackData's fields
# without restating them. The text lives beside the @export it describes rather than in a table
# here (#473): a tip in this file and the field in another is the pair that drifts, and nothing
# would say so. "" = a resource with no table, or a field with no entry, which draws an untipped
# row exactly as before.
static func property_tip(resource: Resource, prop_name: String) -> String:
	if not resource.has_method("property_tips"):
		return ""
	var tips: Dictionary = resource.call("property_tips")
	if not tips.has(prop_name):
		return ""
	var text: String = tips[prop_name]
	return wrap_tooltip(text)


# Tooltip every control a row just added, add_knob_row's shape -- these builders return void or a
# single row, and Godot's tooltip does not walk up to a parent, so the row is identified by the
# children that appeared rather than by a handle.
static func _tip_rows_from(container: Node, first: int, tip: String) -> void:
	if tip == "":
		return
	for i in range(first, container.get_child_count()):
		apply_tooltip(container.get_child(i), tip)


static func _add_property_control(container: Node, resource: Resource, prop: Dictionary, rebuild: Callable) -> void:
	var value = resource.get(prop.name)
	var label: String = prop.name.capitalize()
	var tip := property_tip(resource, prop.name)
	var first := container.get_child_count()

	# Split out because a nested resource's OWN rows must not inherit this field's tip: apply_tooltip
	# recurses, so tipping the object row after the nested block was built would overwrite every tip
	# inside it with the parent's.
	if prop.type == TYPE_OBJECT:
		if prop.hint == PROPERTY_HINT_RESOURCE_TYPE:
			_add_resource_swapper(container, resource, prop, value, rebuild)
		_tip_rows_from(container, first, tip)
		if value is Resource and value.get_script() != null:
			var indent := MarginContainer.new()
			indent.add_theme_constant_override("margin_left", 16)
			container.add_child(indent)
			var inner := VBoxContainer.new()
			indent.add_child(inner)
			build_resource_editor(inner, value, rebuild)
		return

	match prop.type:
		TYPE_INT:
			if prop.hint == PROPERTY_HINT_ENUM:
				add_enum_option(container, label, prop.hint_string, value, func(v): _write(resource, prop.name, v))
			else:
				add_spinbox(container, label, value, func(v): _write(resource, prop.name, int(v)))
		TYPE_FLOAT:
			add_spinbox(container, label, value, func(v): _write(resource, prop.name, v))
		TYPE_BOOL:
			add_checkbox(container, label, value, func(v): _write(resource, prop.name, v))
		TYPE_STRING:
			if prop.hint == PROPERTY_HINT_ENUM:
				add_option(container, label, prop.hint_string.split(","), value, func(s): _write(resource, prop.name, s))
			else:
				add_lineedit(container, label, value, func(s): _write(resource, prop.name, s))
		TYPE_ARRAY:
			# A centred cell STAMP gets a clickable grid (#804); any other Array[Vector2i] keeps the
			# coordinate row #803 shipped. The RESOURCE says which of its fields is which -- see
			# _is_grid_field. Any other array is still not drawn.
			if _is_cell_array(prop):
				if _is_grid_field(resource, prop.name):
					add_cell_grid(container, label, resource, prop.name)
				else:
					add_lineedit(container, label, cells_to_text(value), func(s): _write(resource, prop.name, cells_from_text(s)))
	_tip_rows_from(container, first, tip)


# The one write every reflectively-drawn row goes through (#804), so a panel that must react to a
# field it does not own has ONE signal to listen to. `_adopt` has emitted `changed` since #589 and
# its own comment called it "the hook a panel can redraw off; nothing listens yet" -- the stamp
# grid's anchor caption is the first listener, and it reads `max_range`, three rows above its own.
# A rebuild driven off a row's signal was the alternative and is refused: it frees the SpinBox
# mid-edit, which is #741's trap.
static func _write(resource: Resource, prop_name: String, value: Variant) -> void:
	resource.set(prop_name, value)
	resource.emit_changed()


# Is this exported Array an Array[Vector2i]?
#
# **get_property_list reports a typed array's ELEMENT as "<TYPE_ id>:", never as a class name** --
# an Array[Vector2i] comes back "6:", 6 being TYPE_VECTOR2I, with the trailing half carrying the
# element's own hint. #803 compared that against the literal "Vector2i" and therefore matched
# NOTHING: the stamp's coordinate row never drew in the running Attack Editor at all, and the
# stamp was authorable only through Godot's own inspector. Nothing caught it because the tips law
# checks the property TABLE and the live-sync suite drives a scalar -- no case asked whether the
# row existed. That is the "test the wire" law, and #804's grid cases are what now ask it.
static func _is_cell_array(prop: Dictionary) -> bool:
	var hint: String = prop.hint_string
	return hint.get_slice(":", 0) == str(TYPE_VECTOR2I)

# "x,y x,y ...": one pair per cell, whitespace or ';' between pairs, parens tolerated.
static func cells_to_text(cells: Array) -> String:
	var parts: PackedStringArray = []
	for c in cells:
		parts.append("%d,%d" % [c.x, c.y])
	return " ".join(parts)

# A half-typed pair is skipped rather than refused: the row applies on every keystroke, and the
# cell arrives once its second number does.
static func cells_from_text(text: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for token in text.replace(";", " ").replace("(", " ").replace(")", " ").split(" ", false):
		var xy := token.split(",")
		if xy.size() != 2 or not xy[0].is_valid_int() or not xy[1].is_valid_int():
			continue
		out.append(Vector2i(int(xy[0]), int(xy[1])))
	return out


# ==============================================================================
#  The cell-stamp grid (#804)
# ==============================================================================

const GRID_CELL_PX := 26
const GRID_MIN_SPAN := 5     # odd, and always leaves one clickable ring around the centre
const GRID_MAX_SPAN := 15
const GRID_STEP := 2         # odd sizes only: a stamp grid must have a centre

const CELL_EMPTY := Color("1b1d22")
const CELL_EMPTY_HOVER := Color("2a2d34")
const CELL_FILLED := Color("4a7fbd")
const CELL_FILLED_HOVER := Color("5b90ce")
const CELL_EDGE := Color("3a3d45")
const CELL_FILLED_EDGE := Color("649ada")
const CELL_CENTRE_EDGE := Color("8b909c")


# Does this resource call this field a CENTRED stamp -- offsets around 0,0 (#804)? Asked of the
# resource rather than inferred from Array[Vector2i], because ScenarioUnitEntry.watch_cells is that
# type too and holds ABSOLUTE board cells: a grid centred on 0,0 would be a lie about it. Nothing
# draws that entry reflectively today, and this is what keeps it that way by construction.
# property_tips()'s exact shape -- a static the class declares beside its own @export.
static func _is_grid_field(resource: Resource, prop_name: String) -> bool:
	if not resource.has_method("grid_fields"):
		return false
	var fields: PackedStringArray = resource.call("grid_fields")
	return fields.has(prop_name)


# The sentence under the grid, answered by a RESOURCE: the widget knows how to draw a centred grid,
# and only the content knows what its own centre means. "" if it does not say.
#
# Not necessarily the resource holding the FIELD, which is why add_cell_grid takes a caption source
# (#808): what a stamp's centre means is the ANCHOR rule, and the anchor is derived from the RANGE.
# Since the range moved onto AttackData and the stamp into a shared AttackShape, the shape cannot
# answer for its own grid -- the attack firing it can, and does.
static func _grid_caption(resource: Resource, prop_name: String) -> String:
	if resource == null or not resource.has_method("grid_caption"):
		return ""
	return str(resource.call("grid_caption", prop_name))


static func _cells_of(resource: Resource, prop_name: String) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	cells.assign(resource.get(prop_name))
	return cells


# The smallest odd span that shows every authored cell, floored so there is always a ring to click
# into and capped so no stamp can demand a grid wider than the panel.
static func _stamp_span(cells: Array[Vector2i]) -> int:
	var reach := 0
	for c in cells:
		reach = maxi(reach, maxi(absi(c.x), absi(c.y)))
	return clampi(reach * 2 + 1, GRID_MIN_SPAN, GRID_MAX_SPAN)


# The clickable stamp grid: an odd-sized board of toggle cells around a marked centre, UP forward.
#
# The grid SIZE is the widget's own view and is never stored (dev ruling, 2026-09-06: "the size of
# the widget I'm authoring in, nothing else") -- derived from the stamp's own extent, grown by the
# stepper, re-derived whenever the form is rebuilt. It rides a Dictionary rather than a captured
# int because **a GDScript lambda captures by VALUE**: assigning to a captured local would move a
# copy the next press cannot see.
#
# The coordinate line #803 shipped SURVIVES underneath, so a shape can still be copied between
# attacks -- two RENDERS of one store, both writing through _write, never two stores. Setting
# `text` in code does not emit `text_changed`, which is what keeps the two from looping.
#
# NOTHING here rebuilds the form. A cell restyles itself in place; the stepper and the line rebuild
# only the cells, and neither is a cell. That is #741's rule -- a redraw run inside a row's own
# signal tries to free the node that emitted it -- and it is why no path needs a deferral.
static func add_cell_grid(container: Node, label_text: String, resource: Resource, prop_name: String,
		caption_source: Resource = null) -> void:
	add_label(container, label_text)
	var captioner: Resource = caption_source if caption_source != null else resource
	var state := {"span": _stamp_span(_cells_of(resource, prop_name))}

	var stepper := HBoxContainer.new()
	var minus := Button.new()
	minus.text = "-"
	var size_label := Label.new()
	var plus := Button.new()
	plus.text = "+"
	stepper.add_child(minus)
	stepper.add_child(size_label)
	stepper.add_child(plus)
	container.add_child(stepper)

	# ASCII on purpose: the dev window runs Godot's default theme font, and a missing arrow glyph
	# would draw as a box in the one place the direction has to be unambiguous.
	var forward := Label.new()
	forward.text = "^ forward"
	container.add_child(forward)

	var grid := GridContainer.new()
	container.add_child(grid)

	var caption := Label.new()
	caption.text = _grid_caption(captioner, prop_name)
	container.add_child(caption)

	# The redraw rides the same Dictionary, which is what lets the coordinate line's handler reach a
	# Callable defined after it -- the lookup happens at call time, where capturing it would not.
	var line := add_lineedit(container, "Cells", cells_to_text(_cells_of(resource, prop_name)),
		func(s: String) -> void:
			var typed := cells_from_text(s)
			_write(resource, prop_name, typed)
			# GROW only. A stamp mid-edit is briefly smaller than what is being typed, and
			# re-deriving would collapse the grid and re-expand it on the next keystroke.
			state["span"] = maxi(int(state["span"]), _stamp_span(typed))
			state["redraw"].call())
	var edit: LineEdit = line.get_child(1) as LineEdit

	state["redraw"] = func() -> void:
		var span: int = state["span"]
		size_label.text = "%d x %d" % [span, span]
		minus.disabled = span - GRID_STEP < _stamp_span(_cells_of(resource, prop_name))
		plus.disabled = span >= GRID_MAX_SPAN
		_fill_cell_grid(grid, resource, prop_name, span, edit)

	minus.pressed.connect(func() -> void:
		state["span"] = maxi(GRID_MIN_SPAN, int(state["span"]) - GRID_STEP)
		state["redraw"].call())
	plus.pressed.connect(func() -> void:
		state["span"] = mini(GRID_MAX_SPAN, int(state["span"]) + GRID_STEP)
		state["redraw"].call())

	# The caption follows the anchor live, off the write hook rather than a poll or a rebuild. The
	# connection is dropped with the label: a lambda has no object to auto-disconnect against, so a
	# rebuilt form would otherwise leave it firing into a freed node.
	if caption.text != "":
		var sync := func() -> void:
			caption.text = _grid_caption(captioner, prop_name)
		captioner.changed.connect(sync)
		caption.tree_exiting.connect(func() -> void:
			if captioner.changed.is_connected(sync):
				captioner.changed.disconnect(sync))

	state["redraw"].call()


# One toggle button per cell of the span, row-major from the FORWARD row (-y) down. Rebuilt whole
# by the stepper and the coordinate line; a click never comes through here.
static func _fill_cell_grid(grid: GridContainer, resource: Resource, prop_name: String, span: int, line: LineEdit) -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	grid.columns = span
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	var half := (span - 1) / 2
	var cells := _cells_of(resource, prop_name)
	for y in range(-half, half + 1):
		for x in range(-half, half + 1):
			grid.add_child(_cell_button(Vector2i(x, y), cells.has(Vector2i(x, y)), resource, prop_name, line))


static func _cell_button(offset: Vector2i, filled: bool, resource: Resource, prop_name: String, line: LineEdit) -> Button:
	var cell := Button.new()
	cell.toggle_mode = true
	cell.button_pressed = filled
	# Out of the focus chain: a 15x15 grid is 225 stops between two spinboxes, and a stamp is a
	# mouse gesture.
	cell.focus_mode = Control.FOCUS_NONE
	cell.custom_minimum_size = Vector2(GRID_CELL_PX, GRID_CELL_PX)
	_style_cell(cell, filled, offset == Vector2i.ZERO)
	cell.toggled.connect(func(on: bool) -> void:
		var next: Array[Vector2i] = []
		for c in _cells_of(resource, prop_name):
			if c != offset:
				next.append(c)
		if on:
			next.append(offset)
		# Reading order, so the stored array and the .tres it saves into stay stable rather than
		# following whatever order the cells were clicked in.
		next.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return a.y < b.y if a.y != b.y else a.x < b.x)
		_write(resource, prop_name, next)
		_style_cell(cell, on, offset == Vector2i.ZERO)
		line.text = cells_to_text(next))
	return cell


# Every state is painted explicitly rather than leaning on the theme's pressed look: a stamp cell
# has to read as filled or empty at a glance, and the CENTRE has to read as the centre in both.
static func _style_cell(cell: Button, filled: bool, centre: bool) -> void:
	var edge := CELL_CENTRE_EDGE if centre else (CELL_FILLED_EDGE if filled else CELL_EDGE)
	var width := 2 if centre else 1
	var base := CELL_FILLED if filled else CELL_EMPTY
	var hover := CELL_FILLED_HOVER if filled else CELL_EMPTY_HOVER
	cell.add_theme_stylebox_override("normal", _cell_box(base, edge, width))
	cell.add_theme_stylebox_override("pressed", _cell_box(base, edge, width))
	cell.add_theme_stylebox_override("hover", _cell_box(hover, edge, width))
	cell.add_theme_stylebox_override("hover_pressed", _cell_box(hover, edge, width))


static func _cell_box(fill: Color, edge: Color, width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(width)
	box.set_corner_radius_all(2)
	return box

# The picker's "no resource" row -- ItemEditorTool spells the same idea NO_MAIN_KEY for its own
# bespoke picker, and the reason is identical: a field with nothing in it is a state the control
# must be able to both SHOW and SET.
const NO_RESOURCE_KEY := "(none)"

static func _add_resource_swapper(container: Node, resource: Resource, prop: Dictionary, value: Resource, rebuild: Callable) -> void:
	var base_type: String = prop.hint_string
	var candidates := []
	for entry in ProjectSettings.get_global_class_list():
		if entry["base"] == base_type:
			candidates.append(entry)
	# A type with no subclasses is still a type a null field needs to be GIVEN (#803: AttackPattern
	# became the one concrete pattern, and a new attack had no way to get one). Offered only when
	# nothing extends it, so a picker over a family never lists the family's own base.
	if candidates.is_empty():
		for entry in ProjectSettings.get_global_class_list():
			if entry["class"] == base_type:
				candidates.append(entry)
	if candidates.is_empty():
		return
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = prop.name.capitalize()
	var option := OptionButton.new()
	var current_class := ""
	if value != null and value.get_script() != null:
		current_class = value.get_script().get_global_name()
	# (none) is a REAL row, not decoration: a field with no resource is a legitimate authored state
	# (a pattern-less attack reaches bare adjacency, which AttackLint deliberately passes), so the
	# picker has to be able to express it -- ItemEditorTool's NO_MAIN_KEY, for the same reason.
	# Without it a single-candidate field was a DEAD END: add_item auto-selects the first row, so a
	# null value DISPLAYED as set, and re-picking the row already showing emits nothing, leaving no
	# click anywhere in the control that could assign the resource. Found in play (#804 follow-up).
	# (none) IS ROW ZERO, and that ordering is load-bearing rather than cosmetic: add_item silently
	# selects the first row it is given, so putting the empty state first is exactly what makes the
	# control's own auto-selection tell the truth about a null field. Reorder these two lines and
	# the picker goes back to claiming a class is set on a field that has none. An explicit
	# select(0) sat here and was DEAD -- a mutant deleting it changed nothing, which is what named
	# the ordering as the mechanism.
	option.add_item(NO_RESOURCE_KEY)
	for entry in candidates:
		option.add_item(entry["class"])
	for i in candidates.size():
		if candidates[i]["class"] == current_class:
			option.select(i + 1)
	option.item_selected.connect(func(idx):
		resource.set(prop.name, null if idx == 0 else load(candidates[idx - 1]["path"]).new())
		rebuild.call()
	)
	row.add_child(label)
	row.add_child(option)
	container.add_child(row)

static func selected_name(dropdown: OptionButton) -> String:
	if dropdown.selected < 0:
		return ""
	return dropdown.get_item_text(dropdown.selected)

# Update only fires at the LOADED file (dev call 2026-08-11, after an Update aimed at an unloaded
# scenario destroyed it): the tool passes the reason it is blocked, "" = allowed. The tooltip
# carries the reason, so the greyed button and the refused press cannot disagree (#166 shape).
static func refresh_update_button(button: Button, target: String, noun: String, block_reason := "") -> void:
	button.disabled = target == "" or block_reason != ""
	if target == "":
		button.tooltip_text = "Pick a saved %s to overwrite" % noun
	elif block_reason != "":
		button.tooltip_text = block_reason
	else:
		button.tooltip_text = "Overwrite %s" % target

# The unsaved marker (#389), twin of the confirm convention above: a save button says whether there
# is anything to do, as well as asking before it does it. Deliberately NEVER disables -- Save As
# stays legitimate on a clean panel (forking a new mood off an unchanged one), and a disabled Save
# would bury the precise "nothing has moved" answer its handler already gives. It lives here so the
# marker's SPELLING is one thing: three panels each appending their own suffix is how one of them
# ends up saying "(unsaved)".
static func mark_unsaved(button: Button, base_text: String, dirty: bool) -> void:
	button.text = base_text + (" *" if dirty else "")

# Delete asks first -- every dev Delete rides confirm_delete (dev call 2026-08-11); the tooltip
# still names the victim.
static func refresh_delete_button(button: Button, target: String, noun: String) -> void:
	button.disabled = target == ""
	if target == "":
		button.tooltip_text = "Pick a saved %s to delete" % noun
	else:
		button.tooltip_text = "Delete %s" % target

# The Yes/No gate destructive dev buttons ride. One-shot ConfirmationDialog transient to the
# dev window; frees itself on either answer. Swap the mechanism here if the OS dialog feels wrong.
static func confirm(host: Control, message: String, on_confirm: Callable) -> ConfirmationDialog:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Are you sure?"
	dialog.dialog_text = message
	dialog.ok_button_text = "Yes"
	dialog.cancel_button_text = "No"
	dialog.confirmed.connect(on_confirm)
	dialog.visibility_changed.connect(func():
		if not dialog.visible:
			dialog.queue_free())
	host.add_child(dialog)
	dialog.popup_centered()
	return dialog

# Every dev Delete rides this (dev call 2026-08-11).
static func confirm_delete(host: Control, victim: String, on_confirm: Callable) -> ConfirmationDialog:
	return confirm(host, "Delete %s? This cannot be undone." % victim, on_confirm)

# Every dev save that OVERWRITES rides this or confirm() directly (#380's convention, dev:
# "anything that can overwrite settings should" ask) -- every tool's Update, plus the Game tab's
# source save and the Objects tab's tileset save, whose messages are their own shape. Save As is
# the one save that never confirms, because refuse_existing_file makes it structurally unable to
# overwrite. First worn by the Scenario tool's Update (dev call 2026-08-12, after a mis-aimed
# Update destroyed a level the load-gate could not protect -- it WAS the loaded file).
static func confirm_overwrite(host: Control, victim: String, replacement: String,
		on_confirm: Callable) -> ConfirmationDialog:
	return confirm(host, "Overwrite %s with %s? The saved version is lost." % [victim, replacement],
		on_confirm)

# Filenames illegal on Windows -- refuse rather than sanitize (a silently renamed file is the same
# surprise one step later, and every catalog keys on the exact name). '/' is a separate question
# from the caller (#168): it's a real path separator Godot honors everywhere, and the item/attack
# catalogs scan their save folders FLAT (ResourceDir), so a '/' there wouldn't fail -- it would
# silently land the file in a subfolder no scan ever looks in. Scenarios are the opposite:
# ScenarioManager._collect_scenarios recurses, and Scenarios/fixtures/-style names are a real,
# working feature -- allow_slash is how a scenario name opts out of the ban the other two need.
const ILLEGAL_NAME_CHARS := ["\\", ":", "*", "?", "\"", "<", ">", "|"]

static func refuse_illegal_name(name: String, noun: String, status_label: Label = null, allow_slash := false) -> bool:
	var banned := ILLEGAL_NAME_CHARS.duplicate()
	if not allow_slash:
		banned.append("/")
	for c in banned:
		if name.contains(c):
			var msg := "%s names can't contain '%s'" % [noun.capitalize(), c]
			push_warning(msg)
			if status_label != null:
				status_label.text = msg
			return true
	if allow_slash:
		# A permitted '/' still has to spell an honest subfolder: '..' escapes the save root
		# entirely, and an empty/'.' segment (foo//bar, a trailing '/') degenerates the filename.
		# Either way the file lands where no catalog scan looks -- the #168 symptom, one level up.
		for segment in name.split("/"):
			if segment.strip_edges() in ["", ".", ".."]:
				var msg := "%s names can't use '%s' as a folder segment" % [noun.capitalize(), segment]
				push_warning(msg)
				if status_label != null:
					status_label.text = msg
				return true
	return false

# Save As creates, Update overwrites. Refusing a taken name is what keeps them non-overlapping.
# status_label mirrors the same message into the tool window (#168) -- push_warning alone only
# reaches the editor's Output panel, invisible in the running game where these tools actually live.
static func refuse_existing_file(path: String, noun: String, status_label: Label = null) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var msg := "That %s already exists (%s) -- load it and press Update to overwrite" % [noun, path]
	push_warning(msg)
	if status_label != null:
		status_label.text = msg
	return true

# load() serves the resource cache: without claiming the path first, a re-save leaves every later
# load() returning the stale object. No-op when the resource already owns the path. It also preserves
# the uid already in the file's header, which ResourceSaver.save() drops at runtime (#481).
#
# A path has exactly ONE object, and a save writes THROUGH to it (#589). The pool editors stage their
# edits on a duplicate(true), and saving that copy used to take_over_path it -- which clears the
# ORIGINAL's resource_path and evicts it from the cache, leaving the object every board unit, every
# mod's granted_attacks and every template's main_attack still points at alive with the old values.
# Three symptoms, one cause: the board never saw an edit, a RESPAWN never saw it either (the mod is a
# cache hit still holding the orphan, so only a relaunch cleared it), and the path-less orphan
# re-saved INLINE as a sub_resource instead of an ext_resource, forking the content silently.
static func save_over(resource: Resource, path: String, status_label: Label = null) -> bool:
	var degraded := _degraded_block_reason(resource, path)
	if degraded != "":
		push_error(degraded)
		if status_label != null:
			status_label.text = degraded
		return false
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var target := _live_target(resource, path)
	var prior_uids := uid_map_in_file(path)   # a committed file's uids must survive an overwrite (#481)
	_ensure_header_uid(path, prior_uids)   # ...and a file that never had one gets it minted (#598)
	target.take_over_path(path)
	var err := ResourceSaver.save(target, path)
	if err != OK:
		var msg := "Failed to save %s (error %s)" % [path, err]
		push_error(msg)
		if status_label != null:
			status_label.text = msg
		return false
	if not restore_uids(path, prior_uids):
		if status_label != null:
			status_label.text = "Failed to preserve the UIDs on %s" % path
		return false
	if status_label != null:
		status_label.text = ""   # clears a stale refusal now that a save actually landed
	return true


# What save_over should actually write: the object that already owns `path`, carrying `edited`'s
# values, or `edited` itself when there is nothing to write through to.
#
# Gated on the path being CACHED, because only a cached path can have stale holders -- an uncached
# one is nobody's reference yet, so it stays the cheap take_over_path it always was. The three tools
# that already hand out the live object (the Attack Editor's FAMILY mode, the Item Editor's
# templates, ObjectKnobs' TileSet) land on `live == edited` and are untouched by this.
#
# A SCRIPT mismatch falls back rather than refusing: save_over is not the surface that polices what
# kind of content belongs at a path, and adopting across scripts would set properties the target
# does not have.


# A resource that loaded DEGRADED must not be written back over the file it was degraded from:
# ContentRepair took a dangling reference OUT to get it to parse at all (#608), and saving now makes
# that loss permanent -- the silent class this whole arc is about, arriving by a new door.
#
# Refused only while the gap is STILL THERE. Fill the property in the editor and the save goes
# through, which is how the repair is meant to end: the dev opens the degraded unit, assigns a real
# weapon, saves, and the dangling reference is gone because he replaced it rather than because we
# quietly dropped it.
static func _degraded_block_reason(resource: Resource, path: String) -> String:
	var lost := ContentRepair.dropped_properties(path)
	if lost.is_empty():
		return ""
	var unfilled: Array[String] = []
	for name: String in lost:
		if _is_unset(resource.get(name)):
			unfilled.append(name)
	if unfilled.is_empty():
		return ""
	return "%s loaded without %s, because %s could not be found. Set it before saving, or restore that file -- saving now writes the loss into %s." % [
		path.get_file(), ", ".join(unfilled),
		", ".join(ContentRepair.missing_targets(path)), path.get_file()]


static func _is_unset(value: Variant) -> bool:
	if value == null:
		return true
	if value is Array:
		return (value as Array).is_empty()
	if value is Dictionary:
		return (value as Dictionary).is_empty()
	return false

static func _live_target(edited: Resource, path: String) -> Resource:
	if not ResourceLoader.has_cached(path):
		return edited
	var live := ResourceLoader.load(path)
	if live == null or live == edited or live.get_script() != edited.get_script():
		return edited
	_adopt(live, edited)
	return live


# Godot owns these: take_over_path writes the path, the caller already proved the scripts match, and
# the other two describe the file rather than the content.
const ADOPT_SKIP := ["resource_path", "resource_name", "resource_local_to_scene", "script"]


# Copy `edited`'s stored values onto `live` IN PLACE, so every existing reference sees them.
#
# Through a duplicate(true) SNAPSHOT rather than straight off `edited`: a deep copy leaves path'd
# sub-resources shared, so ext_resource references survive the save, while giving `live` its OWN
# inline ones (an unnamed AttackShape, a nested effect). Assigning `edited`'s objects directly would leave
# the editor's still-open form sharing them, and later keystrokes would then reach the board on
# nested fields but not on scalars -- half-live, which is worse than neither.
#
# Iterates the SNAPSHOT's properties, not `live`'s: the two agree on everything the script declares,
# and where they can differ (metadata) the edited version is the one being saved.
static func _adopt(live: Resource, edited: Resource) -> void:
	var snapshot := edited.duplicate(true)
	for prop in snapshot.get_property_list():
		if prop.name in ADOPT_SKIP or (prop.usage & PROPERTY_USAGE_STORAGE) == 0:
			continue
		live.set(prop.name, snapshot.get(prop.name))
	live.emit_changed()   # the hook a panel can redraw off; nothing listens yet


# The uid= attributes a .tres carries, keyed by the reference id -- its own header under "_header",
# plus every ext_resource line's uid under its id=. ResourceSaver.save() drops ALL of them at runtime,
# so an overwrite must capture them here and put them back (restore_uids). Read from the FILE rather
# than asked of ResourceLoader.get_resource_uid: that consults the uid CACHE, which a save without a
# uid has already emptied for this path. Lifted from tools/lookdev/gen_lookdev_assets.gd and widened
# to the ext_resource references (#481), so the generator and the single dev-tool writer share ONE
# answer (Law #4).
static func uid_map_in_file(path: String) -> Dictionary:
	var map := {}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return map
	for line: String in text.split("\n"):
		if line.begins_with("[gd_resource"):
			var uid := _quoted_attr(line, "uid")
			if uid != "":
				map["_header"] = uid
		elif line.begins_with("[ext_resource"):
			var uid := _quoted_attr(line, "uid")
			var id := _quoted_attr(line, "id")
			if uid != "" and id != "":
				map[id] = uid
	return map


# `key="value"` on a .tres header line, keyed with a LEADING space so `id="` never matches the `id`
# inside `uid="...` (the one attribute pair with that overlap).
static func _quoted_attr(line: String, attr: String) -> String:
	var mark := line.find(' %s="' % attr)
	if mark < 0:
		return ""
	var start := mark + attr.length() + 3
	var end := line.find('"', start)
	return line.substr(start, end - start) if end > start else ""


# The line with its uid= set to `uid`, in the position the editor writes it: last on a gd_resource
# header, right after the type= on an ext_resource line. A present-but-different uid is replaced.
static func _set_uid(line: String, uid: String) -> String:
	var have := _quoted_attr(line, "uid")
	if have == uid:
		return line
	if have != "":
		line = line.replace(' uid="%s"' % have, "")
	if line.begins_with("[gd_resource"):
		return line.replace("]", ' uid="%s"]' % uid)
	var type_close := line.find('"', line.find('type=') + 6)
	return line.insert(type_close + 1, ' uid="%s"' % uid)


# What Godot's own registry says a path's uid is, or "" if nothing claims it. The prior FILE cannot
# answer for a reference this save is the FIRST to write -- #540's atlas is one, and the editor would
# have stamped it on its next save, which is the churn that ticket exists to stop. Registry rather
# than the target's own header: tests/law/test_resource_uid_references.gd asks ResourceUID, so this
# is the same answer the law will grade the line against.


# A resource BORN through the dev tools carries no uid, and never gains one. ResourceSaver.save()
# writes none at runtime (#481), and restore_uids can only put back what the PRIOR file held -- so
# the header uid has no source at all on a file that never had one, while the editor stamps one on
# everything IT writes. Nine of ten authored weapon .tres were uid-less when this landed (#598).
#
# Why it matters: a `path=`-only ext_resource is a reference to a FILENAME. Move the target and
# every holder dangles, which is #596's failure one layer down -- Godot can follow a uid across a
# move and cannot follow a path.
#
# Registry BEFORE minting: if ResourceUID already claims this path, that id IS this file's uid and
# a fresh one would be a second uid for one file. Only a path nothing claims gets a new id.
#
# Scoped to save_over deliberately, NOT to restore_uids: the other caller of that pair is the
# lookdev meshlib generator, whose artifact already carries a uid stamped earlier (#540), so it has
# nothing to mint and no reason to grow the behaviour.
static func _ensure_header_uid(path: String, uids: Dictionary) -> void:
	if uids.get("_header", "") != "":
		return
	var claimed := _registered_uid(path)
	if claimed != "":
		uids["_header"] = claimed
		return
	var id := ResourceUID.create_id()
	ResourceUID.add_id(id, path)
	uids["_header"] = ResourceUID.id_to_text(id)


static func _registered_uid(target_path: String) -> String:
	if target_path == "":
		return ""
	var id := ResourceLoader.get_resource_uid(target_path)
	return "" if id == ResourceUID.INVALID_ID else ResourceUID.id_to_text(id)


# Put the resource's uid= attributes back into the file just saved. ResourceSaver.save() DROPS them
# at runtime -- the running game's ResourceUID holds no registration for the path, so the saver writes
# no uid= on the header OR on the ext_resource lines (or mints a new one for a fresh resource). That
# is how the Carbine main attack lost its uid on an ordinary Update, and how the family template's
# script references lost theirs (#481); take_over_path preserves none of it either.
#
# Text surgery on the header, because there is no save flag for this. The restore compares the uid
# VALUE, not just "is a uid= present", so a saver that mints a DIFFERENT uid (the fresh-resource
# case) is corrected rather than trusted. Returns false only when the file it just wrote cannot be
# read back or reopened.
static func restore_uids(path: String, prior: Dictionary) -> bool:
	if prior.is_empty():
		return true   # nothing authored a uid; nothing to preserve
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("Cannot re-read %s to restore its uids" % path)
		return false
	var lines := text.split("\n")
	var changed := false
	for i in range(lines.size()):
		var line := lines[i]
		var want: String
		if line.begins_with("[gd_resource"):
			want = prior.get("_header", "")
		elif line.begins_with("[ext_resource"):
			want = prior.get(_quoted_attr(line, "id"), "")
			if want == "":
				want = _registered_uid(_quoted_attr(line, "path"))
		else:
			continue
		if want == "" or _quoted_attr(line, "uid") == want:
			continue
		lines[i] = _set_uid(line, want)
		changed = true
	if changed:
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			push_error("Cannot reopen %s to restore its uids" % path)
			return false
		f.store_string("\n".join(lines))
		f.close()
	# Tell the ENGINE too, not just the file. ResourceUID is populated from .godot/uid_cache.bin at
	# import, so a header patched afterwards is invisible until someone re-imports -- and
	# tests/law/test_resource_uid_references.gd asks ResourceUID, so it reds against a file that is
	# already correct. Only the file's OWN uid is registered here; the ext_resource uids belong to
	# their targets and are already registered.
	var header_uid: String = prior.get("_header", "")
	if header_uid != "":
		var id := ResourceUID.text_to_id(header_uid)
		if ResourceUID.has_id(id):
			ResourceUID.set_id(id, path)
		else:
			ResourceUID.add_id(id, path)
	return true


# Removes a saved entry from disk. The catalogs that list these entries (WeaponCatalog,
# RuneCatalog, TransmutationCatalog, WeaponAttackCatalog, ScenarioManager) all re-scan disk per
# call rather than caching, so a caller's own dropdown refresh is enough to drop the deleted
# entry -- no separate cache to invalidate.
static func delete_saved_file(path: String, noun: String, status_label: Label = null) -> bool:
	if path == "":
		var msg := "No %s file on disk to delete" % noun
		push_warning(msg)
		if status_label != null:
			status_label.text = msg
		return false
	var err := DirAccess.remove_absolute(path)
	if err != OK:
		var msg := "Failed to delete %s (error %s)" % [path, err]
		push_error(msg)
		if status_label != null:
			status_label.text = msg
		return false
	if status_label != null:
		status_label.text = ""
	return true
