class_name ShapePlate
extends VBoxContainer

# A read-only picture of ONE attack's geometry (#732): where it may be aimed, and what it covers once
# it lands. Grid space, attacker at the centre, drawn in the same convention the Attack Editor's
# stamp grid authors in (#804), so the two read as one idea.
#
# WHAT UP MEANS IS THE ATTACK'S ANSWER, not this class's (#818): the attacker's FACING for a
# self-anchored attack, board NORTH for one placed at range, since an anchored shape no longer turns.
# Both surfaces read AttackData.grid_up_label for the caption, because a label spelled twice is two
# labels and one of them goes stale.
#
# IT DERIVES NOTHING. Since #808 an attack's geometry is two fields -- the RANGE trio on AttackData
# and a shared AttackShape -- and Reach is the one place that answers using both. Both queries here
# are board-blind by Reach's own contract: get_attack_cells_from's anchored branch never touches the
# board, and get_affected_cells_from returns the untruncated placement when handed a null one. A
# second copy of the bevel, the min-range dead zone or the null-shape fallback is exactly what this
# class exists not to be.
#
# THE INKS ARE THE BOARD'S. OverlayManager.attack_reach_color and aim_fill_color are what the player
# already sees under a live aim, they follow the aim palette #422 let them pick, and "the cells you
# can aim at" having a second colour here would be one meaning with two answers.
#
# NOT DevWidgets.add_cell_grid, which is the authoring twin: that one builds toggle buttons wired to
# write the resource and clamps its span to leave a ring you can click into. Both are authoring
# concerns. What the two share is `reach * 2 + 1`, which is arithmetic rather than a rule.

# The plate is a FIXED box and the cell size is what gives, so a long-ranged attack cannot widen the
# card. MAX span falls out of the two: the largest odd span whose cells still clear MIN_CELL_PX.
const BOX_PX := 116
const MIN_CELL_PX := 6
const MIN_SPAN := 3
const SEP := 2

var _grid: GridContainer
var _caption: Label


func _init() -> void:
	add_theme_constant_override("separation", 3)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", SEP)
	_grid.add_theme_constant_override("v_separation", SEP)
	_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(_grid)

	_caption = Label.new()
	_caption.add_theme_font_size_override("font_size", 9)
	# The caption sits OUTSIDE the plate's own cells, on whatever hosts it -- the fitting card's frame
	# or the Attack Editor's, dark under either palette. HEADER_TEXT is paper ink and read as brown on
	# brown there; the cells below keep it, because a cell IS a section (#814).
	_caption.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.FRAME_TEXT))
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_caption)


# The widest odd span this box can draw without the cells falling under the legibility floor.
# Solved rather than tabled: BOX + SEP >= span * (MIN_CELL_PX + SEP).
static func max_span() -> int:
	var fits := int((BOX_PX + SEP) / float(MIN_CELL_PX + SEP))
	return maxi(MIN_SPAN, fits - 1 if fits % 2 == 0 else fits)


# The aim this plate DRAWS: straight ahead, at maximum reach, pulled in to the edge of the plate when
# the range outruns it. Without that clamp the footprint of a long shot lands off-plate and the one
# ink that says what the attack HITS disappears exactly when the range is most worth showing.
static func drawn_reach(attack: AttackData) -> int:
	if attack == null:
		return 0
	return mini(attack.max_range, (max_span() - 1) / 2)


func show_attack(attack: AttackData) -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	if attack == null:
		_caption.text = "no attack"
		return

	var reach := drawn_reach(attack)
	# A facing has no ring to draw -- the aim IS the direction, so the shape on the attacker is the
	# whole picture. The aimed cell is one step forward, which is what gives the placement its cardinal.
	# The anchored probe aims straight up for a different reason since #818: that placement no longer
	# turns, so the aim picks WHERE the footprint sits and not which way it faces, and up keeps it
	# inside the plate.
	var directional := attack.is_directional()
	var aim := Vector2i.UP if directional else Vector2i(0, -reach)
	var ring: Array[Vector2i] = []
	if not directional:
		ring = Reach.get_attack_cells_from(null, Vector2i.ZERO, Vector2i.ZERO, attack)
	var hits := Reach.get_affected_cells_from(null, Vector2i.ZERO, aim, attack, null)

	var drawn: Array[Vector2i] = []
	drawn.append_array(ring)
	drawn.append_array(hits)
	var span := _span_for(drawn)
	var half := (span - 1) / 2
	var cell := int((BOX_PX - (span - 1) * SEP) / float(span))
	_grid.columns = span
	for y in range(-half, half + 1):
		for x in range(-half, half + 1):
			var at := Vector2i(x, y)
			_grid.add_child(_cell(cell, ring.has(at), hits.has(at), at == Vector2i.ZERO, attack))

	# The clip is DECLARED, never silent: a ring cut off at the plate's edge without a word would be a
	# lie about where the attack stops.
	var up: String = attack.grid_up_label("stamp")
	_caption.text = up if reach >= attack.max_range else "%s · shown to %d" % [up, reach]


# The smallest odd span that holds what was drawn, floored so there is always a ring of context and
# capped at what the box can render.
static func _span_for(cells: Array[Vector2i]) -> int:
	var reach := 0
	for c in cells:
		reach = maxi(reach, maxi(absi(c.x), absi(c.y)))
	return clampi(reach * 2 + 1, MIN_SPAN, max_span())


# COVERED beats AIMABLE where they overlap: the more specific fact about a cell is what the attack
# does to it, not that you could point at it.
static func _cell(px: int, aimable: bool, hit: bool, centre: bool, attack: AttackData) -> Panel:
	var box := StyleBoxFlat.new()
	box.bg_color = QueueStyle.ink(QueueStyle.Role.SECTION_BG)
	box.border_color = QueueStyle.ink(QueueStyle.Role.SECTION_BORDER)
	if aimable:
		box.bg_color = OverlayManager.attack_reach_color(attack)
	if hit:
		box.bg_color = OverlayManager.aim_fill_color()
	box.set_border_width_all(1)
	if centre:
		box.border_color = QueueStyle.ink(QueueStyle.Role.HEADER_TEXT)
		box.set_border_width_all(2)
	var pane := Panel.new()
	pane.custom_minimum_size = Vector2(px, px)
	pane.add_theme_stylebox_override("panel", box)
	return pane
