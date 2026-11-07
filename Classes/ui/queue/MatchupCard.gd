extends PanelContainer
class_name MatchupCard

# The matchup card (#1629): a right-click on a queue row opens the exchange that order makes, laid out
# side to side. The attacker stands on the left facing right, its target (or every target of a volley)
# on the right facing left. The damage each way is a plate pointing at whoever takes it, in the
# DEALER's side colour. What else the exchange does sits underneath as pills: the target's states and
# combos (OutcomeFacts, the row's own list), a sinking, and each tile reaction's word (#1528).
# Owned, placed and closed by SquadActionQueueControl.
#
# IT READS ONLY THE PLAN THE QUEUE HOLDS (Law #2): each member's ResolvedOutcome, the volley's tile
# changes (ResolvedPlan.deposits_of), its sinkings and the counters it provokes. It resolves nothing,
# and it holds the plan while open, because deposits_of and same_volley need it alive. The one live
# read is the ground's art under a tile word, which describes the board now.

signal close_requested

const WIDTH := 560.0
const BOTTOM_MARGIN := 14.0
const SIDE_WIDTH := 150.0

# The first element-to-art map in the project. It moves to ElementPalette when a second surface needs it.
const ELEMENT_ART := {
	Elemental.Element.FIRE: preload("res://Art/Icons/ElementIcons/Fire.png"),
	Elemental.Element.WATER: preload("res://Art/Icons/ElementIcons/Water.png"),
	Elemental.Element.AIR: preload("res://Art/Icons/ElementIcons/Air.png"),
	Elemental.Element.EARTH: preload("res://Art/Icons/ElementIcons/Earth.png"),
	Elemental.Element.AETHER: preload("res://Art/Icons/ElementIcons/Aether.png"),
	Elemental.Element.SHOCK: preload("res://Art/Icons/StateIcons/ShockIcon.png"),
}

var lead: AttackAction
var whole_volley := false
var plan: ResolvedPlan
var _members: Array[AttackAction] = []
var _grid: TileMapLayer


func setup(lead_: AttackAction, members: Array[AttackAction], plan_: ResolvedPlan, grid: TileMapLayer,
		whole_volley_: bool) -> void:
	lead = lead_
	_members = members
	plan = plan_
	_grid = grid
	whole_volley = whole_volley_
	name = "MatchupCard"
	_build()
	_place()
	_silence_children(self)
	mouse_filter = Control.MOUSE_FILTER_STOP


# A right-click's release on the card closes it, the edge the rows open on. Both edges are taken, so
# neither falls through to the board's cancel.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if not event.pressed:
			close_requested.emit()
		accept_event()


# Bottom-centre of the design space, growing upward as the card fills.
func _place() -> void:
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_left = -WIDTH * 0.5
	offset_right = WIDTH * 0.5
	offset_top = -BOTTOM_MARGIN
	offset_bottom = -BOTTOM_MARGIN


# The card is ONE click target: everything inside it is drawn, not pressed.
func _silence_children(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_silence_children(child)


func _build() -> void:
	add_theme_stylebox_override("panel", _frame_box())
	custom_minimum_size = Vector2(WIDTH, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	add_child(col)

	var first: ResolvedOutcome = _members[0].resolved if not _members.is_empty() else null
	var elements: Array[Elemental.Element] = []
	if first != null:
		elements = first.elements
	var attacker_ink := ActionQueueRow.side_ink(lead.actor)
	var hit_ink := QueueStyle.element_ink(elements[0]) if not elements.is_empty() else attacker_ink
	var counters := _counters()
	var target_ink := ActionQueueRow.side_ink(_members[0].target) if not _members.is_empty() else ActionQueueRow.side_ink(null)

	var stage := PanelContainer.new()
	stage.add_theme_stylebox_override("panel", _stage_box())
	col.add_child(stage)
	stage.add_child(Backdrop.new(attacker_ink, target_ink, hit_ink))
	var inset := MarginContainer.new()
	inset.add_theme_constant_override("margin_left", 10)
	inset.add_theme_constant_override("margin_right", 10)
	inset.add_theme_constant_override("margin_top", 8)
	inset.add_theme_constant_override("margin_bottom", 8)
	stage.add_child(inset)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	inset.add_child(line)

	# LEFT: the attacker, its bar moved only by what hits it back.
	var hp_now: int = lead.actor.get_current_hp() if is_instance_valid(lead.actor) else 0
	var before := hp_now
	var after := hp_now
	if not counters.is_empty():
		before = counters[0].resolved.hp_before
		after = counters[-1].resolved.displayed_hp_after()
	var attacker := _side(lead.get_actor_texture(), lead.get_actor_modulate(), _name_of(lead.actor),
			before, after, -1, _max_hp(lead.actor), attacker_ink, true,
			AttackAction.lethality_icon(counters[-1].resolved) if not counters.is_empty() else null)
	attacker.name = "Attacker"
	line.add_child(attacker)

	line.add_child(_centre(elements, attacker_ink, counters))

	# RIGHT: the target, every target of a volley, or the ground an empty aim lands on.
	var sinks := _sinks()
	if whole_volley and _members.size() > 1:
		var stack := VBoxContainer.new()
		stack.name = "Volley"
		stack.alignment = BoxContainer.ALIGNMENT_CENTER
		stack.add_theme_constant_override("separation", 3)
		line.add_child(stack)
		for i in _members.size():
			var row := _member_row(_members[i], _sinks_of(_members[i], sinks))
			row.name = "Member%d" % i
			stack.add_child(row)
	elif _members[0].target != null:
		var member := _members[0]
		var r := member.resolved
		var own := _sinks_of(member, sinks)
		var target := _side(member.get_target_texture(), _modulate_of(member.target), member.get_target_name(),
				r.hp_before, r.displayed_hp_after(), _final_hp(r, own), _max_hp(member.target), target_ink, false,
				_lethality(r, own))
		target.name = "Target"
		target.modulate = member.get_ui_modulate()
		line.add_child(target)
	else:
		line.add_child(_ground_side(lead.target_cell))

	# BOTTOM: what else happens, as pills on a tray.
	var pills: Array[Control] = []
	if not (whole_volley and _members.size() > 1):
		var own := _sinks_of(_members[0], sinks)
		var seen := {}
		var facts: Array[OutcomeFacts.Fact] = OutcomeFacts.of(_members[0].resolved)
		for sink in own:
			facts.append_array(OutcomeFacts.of(sink.resolved))
		for fact in facts:
			if seen.has(fact.word):
				continue
			seen[fact.word] = true
			var icons: Array[Texture2D] = [fact.icon]
			var pill := _pill(icons, fact.word, fact.ink)
			pill.name = "FactPill%d" % seen.size()
			pills.append(pill)
	var ground := _ground_pills(hit_ink)
	pills.append_array(ground)
	if not pills.is_empty():
		var tray := PanelContainer.new()
		tray.add_theme_stylebox_override("panel", _tray_box())
		var flow := HFlowContainer.new()
		flow.name = "Tray"
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 4)
		tray.add_child(flow)
		for pill in pills:
			flow.add_child(pill)
		col.add_child(tray)


# The attack's name, and a plate each way: the hit pointing right, each counter pointing left.
func _centre(elements: Array[Elemental.Element], attacker_ink: Color, counters: Array[CounterAttackAction]) -> Control:
	var centre := VBoxContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.alignment = BoxContainer.ALIGNMENT_CENTER
	centre.add_theme_constant_override("separation", 6)
	var attack := lead.fired_attack
	var title := _label(attack.display_name if attack != null else "", QueueStyle.ink(QueueStyle.Role.NAME_TEXT), 13)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	centre.add_child(title)

	var hit := ArrowPlate.new(_hit_text(), attacker_ink, true, Vector2(100, 34), 22, element_art(elements))
	hit.name = "HitPlate"
	hit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	centre.add_child(hit)
	for i in counters.size():
		var c := counters[i]
		var back := ArrowPlate.new(str(c.resolved.damage), ActionQueueRow.side_ink(c.actor), false, Vector2(84, 26), 16,
				element_art(c.resolved.elements))
		back.name = "CounterPlate%d" % i
		back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		centre.add_child(back)
	return centre


# What the hit plate says: the damage, a heal's "+N", or a range when a volley's victims differ.
func _hit_text() -> String:
	var heals := lead.fired_attack != null and lead.fired_attack.heals
	var low := INF
	var high := -INF
	for member in _members:
		var r := member.resolved
		if r == null or not r.reads_hp:
			continue
		var amount: int = r.hp_restored() if heals else r.damage
		low = minf(low, amount)
		high = maxf(high, amount)
	if low == INF:
		return ""
	var prefix := "+" if heals else ""
	if low == high:
		return "%s%d" % [prefix, int(low)]
	return "%s%d-%d" % [prefix, int(low), int(high)]


# The counters this exchange provokes that land on the attacker, in the order they resolve.
func _counters() -> Array[CounterAttackAction]:
	var out: Array[CounterAttackAction] = []
	for c in plan.counters:
		if c.resolved == null or c.resolved.skipped:
			continue
		if _members.has(c.source_attack) and c.target == lead.actor:
			out.append(c)
	return out


# The volley's sinkings. The plan hangs them all on the volley's LAST member, so each is matched to
# its member by the body that sinks.
func _sinks() -> Array[SinkAction]:
	var volley: Array[AttackAction] = [lead]
	if not lead.volley.is_empty():
		volley = lead.volley
	var out: Array[SinkAction] = []
	for member in volley:
		out.append_array(plan.sinks_caused_by(member))
	return out


static func _sinks_of(member: AttackAction, sinks: Array[SinkAction]) -> Array[SinkAction]:
	var own: Array[SinkAction] = []
	for sink in sinks:
		if member.target != null and sink.actor == member.target:
			own.append(sink)
	return own


static func _final_hp(r: ResolvedOutcome, sinks: Array[SinkAction]) -> int:
	return sinks[-1].resolved.displayed_hp_after() if not sinks.is_empty() else r.displayed_hp_after()


static func _lethality(r: ResolvedOutcome, sinks: Array[SinkAction]) -> Texture2D:
	for i in range(sinks.size() - 1, -1, -1):
		var icon := AttackAction.lethality_icon(sinks[i].resolved)
		if icon != null:
			return icon
	return AttackAction.lethality_icon(r)


# One side: a portrait on its ring, the name on a pill, the HP bar and its numbers.
func _side(texture: Texture2D, tint: Color, who: String, before: int, after: int, final: int, max_hp: int,
		ink: Color, faces_right: bool, lethal: Texture2D) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	box.custom_minimum_size = Vector2(SIDE_WIDTH, 0)
	box.add_child(Figure.new(texture, tint, ink, faces_right, Vector2(SIDE_WIDTH, 70)))
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", _name_box(ink))
	plate.add_child(_label(who, QueueStyle.ink(QueueStyle.Role.NAME_TEXT), 12))
	plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(plate)
	box.add_child(HpBar.new(before, after, final, max_hp, ink, SIDE_WIDTH))
	box.add_child(_hp_numbers(before, after, final, ink, true, lethal))
	return box


# A volley victim, compact: a small figure, its name and numbers, and a bar showing the hit and the
# sinking as two separate losses.
func _member_row(member: AttackAction, sinks: Array[SinkAction]) -> Control:
	var r := member.resolved
	var ink := ActionQueueRow.side_ink(member.target)
	var row := PanelContainer.new()
	var box := QueueStyle.tint_box(ink)
	box.bg_color = _alpha(ink, 0.1)
	box.content_margin_right = 7.0
	box.content_margin_bottom = 3.0
	row.add_theme_stylebox_override("panel", box)
	row.modulate = member.get_ui_modulate()
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	row.add_child(line)
	line.add_child(Figure.new(member.get_target_texture(), _modulate_of(member.target), ink, false, Vector2(30, 30)))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	line.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	head.add_child(_label(member.get_target_name(), QueueStyle.ink(QueueStyle.Role.NAME_TEXT), 11))
	var final := _final_hp(r, sinks)
	var nums := _hp_numbers(r.hp_before, r.displayed_hp_after(), final, ink, false, _lethality(r, sinks))
	nums.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nums.alignment = BoxContainer.ALIGNMENT_END
	head.add_child(nums)
	col.add_child(HpBar.new(r.hp_before, r.displayed_hp_after(), final, _max_hp(member.target), ink, SIDE_WIDTH))
	return row


# An aim at empty ground puts the ground on the right: its tile art and its authored name.
func _ground_side(cell: Vector2i) -> Control:
	var box := VBoxContainer.new()
	box.name = "Ground"
	box.add_theme_constant_override("separation", 3)
	box.custom_minimum_size = Vector2(SIDE_WIDTH, 0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var art := _ground_art(cell)
	if art != null:
		var icon := _icon(art, 48)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(icon)
	var who := GridUtils.authored_tile_display_name(_grid.get_cell_tile_data(cell)) if _grid != null else ""
	if who != "":
		var plate := PanelContainer.new()
		plate.add_theme_stylebox_override("panel", _name_box(QueueStyle.ink(QueueStyle.Role.HEADER_TEXT)))
		plate.add_child(_label(who, QueueStyle.ink(QueueStyle.Role.NAME_TEXT), 12))
		plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(plate)
	return box


func _hp_numbers(before: int, after: int, final: int, ink: Color, big: bool, lethal: Texture2D) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_theme_constant_override("separation", 3)
	var dim := _alpha(ink, 0.65)
	var steps: Array[int] = [before]
	if after != before:
		steps.append(after)
	if final >= 0 and final != after:
		steps.append(final)
	for i in steps.size():
		if i > 0:
			line.add_child(_label("→", dim, 11))
		var last := i == steps.size() - 1
		line.add_child(_label(str(steps[i]), ink if last else dim, (15 if big else 11) if last else 11))
	if lethal != null:
		line.add_child(_icon(lethal, 14 if big else 12))
	return line


# Each tile reaction's word once (#1528), with how many tiles said it and a picture of the change:
# what the ground loses, then what it gains. A side with no state shows the ground itself, so ice
# melting off water reads ice -> water and grass catching reads grass -> fire.
func _ground_pills(ink: Color) -> Array[Control]:
	var count := {}
	var order: Array[String] = []
	var first := {}
	for effect in plan.deposits_of(lead):
		for word in effect.popups:
			if not count.has(word):
				order.append(word)
				first[word] = effect
			count[word] = int(count.get(word, 0)) + 1
	var pills: Array[Control] = []
	for i in order.size():
		var word := order[i]
		var effect: ResolvedCellEffect = first[word]
		var n: int = count[word]
		var pill := _pill(_change_art(effect), "%s  ×%d" % [word, n] if n > 1 else word, ink)
		pill.name = "GroundPill%d" % i
		pills.append(pill)
	return pills


func _change_art(effect: ResolvedCellEffect) -> Array[Texture2D]:
	var lost: Array[Texture2D] = []
	for state in effect.states_removed:
		var art: Texture2D = OverlayManager.TERRAIN_STATE_ICONS.get(state, null)
		if art != null:
			lost.append(art)
	var gained: Array[Texture2D] = []
	for state in effect.states_added:
		var art: Texture2D = OverlayManager.TERRAIN_STATE_ICONS.get(state, null)
		if art != null:
			gained.append(art)
	var ground := _ground_art(effect.cell)
	if lost.is_empty() and ground != null:
		lost.append(ground)
	if gained.is_empty() and ground != null:
		gained.append(ground)
	var out: Array[Texture2D] = []
	out.append_array(lost)
	if lost != gained:
		out.append(null)   # the arrow between before and after
		out.append_array(gained)
	return out


func _ground_art(cell: Vector2i) -> Texture2D:
	if _grid == null:
		return null
	var art := GridUtils.get_terrain_icon_at_cell(_grid, cell)
	return null if art == GridUtils.ERROR_ICON else art


# A pill: icons (a null between two runs draws as an arrow), then the word.
func _pill(icons: Array[Texture2D], word: String, ink: Color) -> Control:
	var pill := PanelContainer.new()
	var box := QueueStyle.tint_box(ink)
	box.content_margin_left = 6.0
	box.content_margin_right = 7.0
	pill.add_theme_stylebox_override("panel", box)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 3)
	pill.add_child(line)
	for art in icons:
		if art == null:
			if line.get_child_count() > 0:
				line.add_child(_label("→", QueueStyle.ink(QueueStyle.Role.HEADER_TEXT), 12))
		else:
			line.add_child(_icon(art, 18))
	var label := _label(word, ink, 12)
	label.name = "Word"
	line.add_child(label)
	return pill


# --- reads ----------------------------------------------------------------------------------------

static func element_art(elements: Array[Elemental.Element]) -> Texture2D:
	for e in elements:
		if ELEMENT_ART.has(e):
			return ELEMENT_ART[e]
	return null


static func _name_of(unit: Unit) -> String:
	return unit.get_unit_name() if unit != null and is_instance_valid(unit) else ""


static func _max_hp(unit: Unit) -> int:
	return unit.get_max_hp() if unit != null and is_instance_valid(unit) else 1


static func _modulate_of(unit: Unit) -> Color:
	return unit.modulate if unit != null and is_instance_valid(unit) else Color.WHITE


# --- chrome ---------------------------------------------------------------------------------------

func _frame_box() -> StyleBoxFlat:
	var box := QueueStyle.panel_box().duplicate() as StyleBoxFlat
	box.set_content_margin_all(5.0)
	box.shadow_color = Color(0, 0, 0, 0.45)
	box.shadow_size = 6
	box.shadow_offset = Vector2(0, 3)
	return box


func _stage_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = QueueStyle.ink(QueueStyle.Role.SECTION_BG)
	box.set_corner_radius_all(3)
	box.set_content_margin_all(0.0)
	return box


func _tray_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = QueueStyle.ink(QueueStyle.Role.SECTION_BG)
	box.border_color = QueueStyle.ink(QueueStyle.Role.SECTION_BORDER)
	box.set_border_width_all(1)
	box.set_corner_radius_all(3)
	box.content_margin_left = 7.0
	box.content_margin_right = 7.0
	box.content_margin_top = 4.0
	box.content_margin_bottom = 4.0
	return box


func _name_box(ink: Color) -> StyleBoxFlat:
	var box := QueueStyle.tint_box(ink)
	box.set_corner_radius_all(8)
	box.content_margin_left = 9.0
	box.content_margin_right = 9.0
	box.content_margin_top = 0.0
	return box


static func _icon(art: Texture2D, px: int) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = art
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.custom_minimum_size = Vector2(px, px)
	return rect


static func _label(text: String, ink: Color, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", ink)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


static func _alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)


# --- drawn pieces ---------------------------------------------------------------------------------

# Each half washed in its side's ink from the outer edge, a faint diagonal hatch, the hit's element
# glowing between the two, and a thin top rule running attacker -> element -> target.
class Backdrop extends Control:
	var _left: Color
	var _right: Color
	var _hit: Color

	func _init(left: Color, right: Color, hit: Color) -> void:
		_left = left
		_right = right
		_hit = hit
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var seam := w * 0.5
		var slant := 16.0
		var wash := QueueStyle.MATCHUP_WASH
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(seam + slant, 0), Vector2(seam - slant, h), Vector2(0, h)]),
				PackedColorArray([_a(_left, wash), _a(_left, 0.0), _a(_left, 0.0), _a(_left, wash * 0.6)]))
		draw_polygon(PackedVector2Array([Vector2(seam + slant, 0), Vector2(w, 0), Vector2(w, h), Vector2(seam - slant, h)]),
				PackedColorArray([_a(_right, 0.0), _a(_right, wash), _a(_right, wash * 0.6), _a(_right, 0.0)]))
		var hatch := _a(QueueStyle.ink(QueueStyle.Role.NAME_TEXT), QueueStyle.MATCHUP_HATCH)
		var x := -h
		while x < w:
			var x0 := maxf(x, 0.0)
			var x1 := minf(x + h, w)
			if x1 > x0:
				draw_line(Vector2(x0, h - (x0 - x)), Vector2(x1, h - (x1 - x)), hatch, 1.0)
			x += 7.0
		var c := Vector2(seam, h * 0.5)
		var rad := Vector2(110.0, h * 0.5)
		var steps := 32
		for i in steps:
			var a0 := TAU * i / steps
			var a1 := TAU * (i + 1) / steps
			draw_polygon(PackedVector2Array([c, c + Vector2(cos(a0), sin(a0)) * rad, c + Vector2(cos(a1), sin(a1)) * rad]),
					PackedColorArray([_a(_hit, QueueStyle.MATCHUP_GLOW), _a(_hit, 0.0), _a(_hit, 0.0)]))
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(seam, 0), Vector2(seam, 3), Vector2(0, 3)]),
				PackedColorArray([_left, _hit, _hit, _left]))
		draw_polygon(PackedVector2Array([Vector2(seam, 0), Vector2(w, 0), Vector2(w, 3), Vector2(seam, 3)]),
				PackedColorArray([_hit, _right, _right, _hit]))

	static func _a(c: Color, alpha: float) -> Color:
		return Color(c.r, c.g, c.b, alpha)


# A portrait standing on a ring in its side's ink, the board's own mark under a unit. The art faces
# screen right (UnitSprite3D.ART_FACES_SCREEN_RIGHT), so only a figure facing left is flipped.
class Figure extends Control:
	var _ink: Color
	var _extent: Vector2

	func _init(art: Texture2D, tint: Color, ink: Color, faces_right: bool, extent: Vector2) -> void:
		_ink = ink
		_extent = extent
		custom_minimum_size = extent
		var portrait := TextureRect.new()
		portrait.name = "Portrait"
		portrait.texture = MapSpriteInk.portrait(art)
		portrait.modulate = tint
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		portrait.flip_h = faces_right != UnitSprite3D.ART_FACES_SCREEN_RIGHT
		portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(portrait)

	func _draw() -> void:
		var c := Vector2(size.x * 0.5, size.y - _extent.y * 0.09)
		var r := Vector2(_extent.y * 0.4, _extent.y * 0.12)
		var ring := PackedVector2Array()
		for i in 32:
			var a := TAU * i / 32.0
			ring.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
		draw_colored_polygon(ring, Color(0, 0, 0, 0.35))
		ring.append(ring[0])
		draw_polyline(ring, Color(_ink.r, _ink.g, _ink.b, 0.9), 1.5)


# A damage plate shaped as an arrow at whoever takes it, with the hit's element as an icon.
class ArrowPlate extends Control:
	var _fill: Color
	var _points_right: bool

	func _init(text: String, fill: Color, points_right: bool, extent: Vector2, text_size: int, art: Texture2D) -> void:
		_fill = fill
		_points_right = points_right
		custom_minimum_size = extent
		var tip := extent.y * 0.5
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 5)
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		if points_right:
			row.offset_right = -tip * 0.6
		else:
			row.offset_left = tip * 0.6
		add_child(row)
		if art != null:
			var glyph := MatchupCard._icon(art, int(extent.y * 0.55))
			glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(glyph)
		if text != "":
			var label := MatchupCard._label(text, Color(1, 1, 1), text_size)
			label.name = "Amount"
			label.add_theme_constant_override("outline_size", 5)
			label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
			row.add_child(label)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var tip := h * 0.5
		var light := _fill.lightened(0.18)
		var dark := _fill.darkened(0.22)
		var pts: PackedVector2Array
		var tints: PackedColorArray
		if _points_right:
			pts = PackedVector2Array([Vector2(0, 0), Vector2(w - tip, 0), Vector2(w, h * 0.5), Vector2(w - tip, h), Vector2(0, h)])
			tints = PackedColorArray([light, light, _fill, dark, dark])
		else:
			pts = PackedVector2Array([Vector2(tip, 0), Vector2(w, 0), Vector2(w, h), Vector2(tip, h), Vector2(0, h * 0.5)])
			tints = PackedColorArray([light, light, dark, dark, _fill])
		var shadow := PackedVector2Array()
		for p in pts:
			shadow.append(p + Vector2(2, 2))
		draw_colored_polygon(shadow, Color(0, 0, 0, 0.35))
		draw_polygon(pts, tints)
		var rim := pts.duplicate()
		rim.append(pts[0])
		draw_polyline(rim, _fill.lightened(0.45), 1.0)


# An HP bar: what is left in the side's ink, the hit in white, a sinking after it in water blue, a
# heal's gain lighter, and a tick every 10 HP.
class HpBar extends Control:
	var _before: int
	var _after: int
	var _final: int
	var _max: int
	var _ink: Color

	func _init(before: int, after: int, final: int, max_hp: int, ink: Color, width: float) -> void:
		_before = before
		_after = after
		_final = after if final < 0 else final
		_max = maxi(max_hp, 1)
		_ink = ink
		custom_minimum_size = Vector2(width, 11)

	func _draw() -> void:
		var full := Rect2(Vector2.ZERO, size)
		var inner := full.grow(-1.0)
		draw_rect(full, Color(0.03, 0.03, 0.04, 0.92))
		var span := inner.size.x / float(_max)
		var b := span * clampi(_before, 0, _max)
		var a := span * clampi(_after, 0, _max)
		var f := span * clampi(_final, 0, _max)
		var base := minf(f, b)
		draw_rect(Rect2(inner.position, Vector2(base, inner.size.y)), _ink)
		draw_rect(Rect2(inner.position, Vector2(base, 2)), _ink.lightened(0.35))
		if _after > _before:
			draw_rect(Rect2(inner.position + Vector2(b, 0), Vector2(a - b, inner.size.y)), _ink.lightened(0.45))
		else:
			draw_rect(Rect2(inner.position + Vector2(f, 0), Vector2(a - f, inner.size.y)),
					QueueStyle.element_ink(Elemental.Element.WATER))
			draw_rect(Rect2(inner.position + Vector2(a, 0), Vector2(b - a, inner.size.y)), Color(1, 1, 1, 0.88))
		var hp := 10
		while hp < _max:
			var x := inner.position.x + span * hp
			draw_line(Vector2(x, inner.position.y), Vector2(x, inner.end.y), Color(0, 0, 0, 0.5), 1.0)
			hp += 10
		draw_rect(full, _ink.darkened(0.35), false, 1.0)
