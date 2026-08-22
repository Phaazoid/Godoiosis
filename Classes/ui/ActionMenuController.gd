extends Node
class_name ActionMenuController

# The player's action menu (#467): a RADIAL that replaces the floating dropdown, keeping the
# name because it asks the question ("the action-menu widget") rather than naming the shape.
#
# ONE full-rect Control is the backdrop AND the menu. The old version needed a backdrop purely to
# turn an outside click into a cancel; angular selection needs that same surface for the opposite
# reason, so the two collapsed into one node. There is no "miss" any more -- every point on screen
# lies inside some slice's sector -- which is why clicking the board no longer dismisses the menu.
# Right-click and the centre dead zone are what replaced it.
#
# THE FOUR RULES, all dev calls on #467, because none of them is re-derivable from the code:
#   COMPACTS   -- only live verbs are drawn, so a slice's angle moves with the unit. That is the
#                 price of "far too many unit dependent actions"; ACTION_DATA order is still the
#                 clockwise order, so the SEQUENCE holds still even when the angles do not.
#   CONCENTRIC -- a category opens a full ring AROUND the one it came from, and the inner rings
#                 stay drawn. The menu lives until a terminal pick, so a wrong turn costs a
#                 right-click rather than a dismiss-and-reopen.
#   ANGULAR    -- the pointer's ANGLE from _centre picks the slice; distance is meaningless except
#                 for the dead-zone test. The hit area is unbounded, so a flick in a direction is a
#                 selection wherever the pointer physically is. This is also the whole reason the
#                 scheme ports: a stick produces an angle, a d-pad an index, and neither needs the
#                 mouse's hit-testing. The deepest open ring owns every angle -- shallower rings are
#                 drawn as the path taken and are NOT pointable, which is what makes right-click the
#                 one way back and keeps "at most one ring per level" true without a rule for it.
#   THIN       -- a deeper ring paints LESS of each sector than the one inside it. The sectors still
#                 tile the full 360; only the paint narrows. Keeping selection_at ignorant of
#                 PAINT_FRACTION is what holds that split honest, and the 360-degree sweep in
#                 tests/ui/test_radial_geometry.gd is its falsifiable form.
#
# Preserved from the dropdown deliberately: `cancelled` still fires BEFORE `action_selected`, but
# now ONLY on a terminal pick. Emitting it on the way into a CATEGORY is what #105 and #107 were --
# state wiped on the way into the next mode -- so the drill-down path does not clear the selection
# the player is still choosing an action for.

const MENU_MARGIN := 8.0
const MAX_RING_DEPTH := 3      # categories, their children, and a preview beyond both
const SPRITE_FIT := 1.4        # sprite box as a multiple of DEAD_ZONE_RADIUS (< 2.0 keeps it inside)
const ARC_SAMPLES_PER_SLICE := 12
const MIN_LABEL_FONT_SIZE := 8   # a shrunk label stops here; below it the name is not a readout
const READOUT_PADDING := 8.0     # breathing room between the readout's text and its panel edge

# Look values, tuned live through GameKnobs.CLASS_KNOBS. Statics rather than exports because the
# menu is transient -- there is no standing node for a knob to address, and nothing to re-apply
# when one moves: the next open reads them. Same shape as MovementComponent.SHOVE_SLIDE_SPEED.
#
# The centre gap is deliberately WIDE and the bands deliberately THIN (dev call): the sprite is the
# point of the centre, and thin rings read as menu rather than as pie chart.
static var RING_INNER_RADIUS := 78.0
static var RING_THICKNESS := 28.0
static var RING_GAP := 7.0
static var DEAD_ZONE_RADIUS := 66.0
static var PAINT_FRACTION := 0.86
static var PAINT_FRACTION_FALLOFF := 0.1
# The ceiling on how wide any one wedge PAINTS. Without it a ring of one balloons into a whole
# donut and a ring of two into two hemispheres, which is what a compacting ring produces most of
# the time (dev: "the massive balloon arcs just don't look great"). Hit-testing is untouched --
# the sectors still tile the full circle, so the leftover angle simply belongs to the nearest
# wedge and the always-drawn highlight says which.
static var MAX_WEDGE_DEGREES := 120.0
# A PREVIEW has to be legible or it is not a preview (dev, round 3: "can't very well preview what
# I can't see"). It reads as not-open-yet by being one ring further out and carrying no highlight,
# NOT by being faint -- so this is opaque enough to read against a live board.
static var GHOST_ALPHA := 0.8
static var SLICE_COLOR := Color(0.08, 0.09, 0.12, 0.92)
static var SLICE_SELECTED_COLOR := Color(0.30, 0.45, 0.66, 0.96)
static var SLICE_DISABLED_COLOR := Color(0.08, 0.09, 0.12, 0.5)
# The dead zone made visible: the disc IS the region that selects nothing, so its edge is a
# promise rather than decoration. The sprite sits on it.
static var CENTRE_COLOR := Color(0.05, 0.06, 0.09, 0.94)
static var CENTRE_RIM_COLOR := Color(0.55, 0.62, 0.75, 0.85)
static var CENTRE_RIM_WIDTH := 2.0
# The readout below the ring. Both text colours are fully opaque on purpose: the hierarchy between
# a name and its explanation is BRIGHTNESS, because alpha over a live board is what made the first
# version hard to read at all.
static var READOUT_BACKGROUND := Color(0.04, 0.05, 0.07, 0.94)
static var READOUT_BORDER := Color(0.55, 0.62, 0.75, 0.7)
static var READOUT_BORDER_WIDTH := 1.0
static var READOUT_TITLE_COLOR := Color(1, 1, 1, 1)
static var READOUT_DETAIL_COLOR := Color(0.78, 0.82, 0.88, 1)

var local_unit: Unit

var _layer: CanvasLayer
var _root: Control
var _centre: Vector2
var _levels: Array[Dictionary] = []   # [{nodes: Array, start_deg: float}]; [0] is the categories
var _selection := -1                  # index within the deepest level; -1 = dead zone
var _preview: Array = []              # the hovered category's children, ghosted; empty when none
var _preview_start := 0.0
var _hover_seconds := 0.0             # how long _selection has been held; gates the readout

signal action_selected(action_id, local_unit)
signal cancelled(me)


func setup(unit: Unit) -> void:
	local_unit = unit

	_layer = CanvasLayer.new()
	_layer.layer = UiLayers.ACTION_MENU
	add_child(_layer)

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	# Map sprites are 16px art blown up into the centre; the default filter turns them to mush.
	_root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_root.gui_input.connect(_on_gui_input)
	_root.draw.connect(_on_draw)
	_layer.add_child(_root)


# The one door in. `nodes` is MainActionMenu.build_tree's output -- the WHOLE tree, built once,
# because a ghosted category has to know its contents before it is opened and a preview that
# re-queries could disagree with what commits.
func open(nodes: Array, at: Vector2) -> void:
	_levels = [{"nodes": nodes, "start_deg": 0.0}]
	_centre = at
	_clamp_centre.call_deferred()


# ==============================================================================
#  Geometry -- pure, so tests/ui/test_radial_geometry.gd can sweep it with no scene
# ==============================================================================

# Degrees clockwise from 12 o'clock, which is the order ACTION_DATA reads in.
static func angle_of(point: Vector2, centre: Vector2) -> float:
	var d := point - centre
	return rad_to_deg(atan2(d.x, -d.y))

static func point_at(centre: Vector2, radius: float, angle_deg: float) -> Vector2:
	var a := deg_to_rad(angle_deg)
	return centre + Vector2(sin(a), -cos(a)) * radius

# Which slice an angle falls in. The modulo guards the case where floating point lands the
# division exactly on `count`.
static func index_at(angle_deg: float, count: int, start_deg: float) -> int:
	if count <= 0:
		return -1
	var span := 360.0 / float(count)
	return int(floor(wrapf(angle_deg - start_deg, 0.0, 360.0) / span)) % count

# THE hit test. Note what it does NOT take: a paint fraction. Which sector a point falls in has
# nothing to do with how much of that sector is painted, and keeping the two apart here is what
# lets the look thin the rings without moving a single hit boundary.
static func selection_at(point: Vector2, centre: Vector2, count: int, start_deg: float) -> int:
	if point.distance_to(centre) < DEAD_ZONE_RADIUS:
		return -1
	return index_at(angle_of(point, centre), count, start_deg)

# Where a child ring begins, given the slice that opened it. The dev's call is "base it from the
# parent" so the group blooms out of where you pointed; this CENTRES the first child on the
# parent's direction rather than starting its leading edge there, which would leave a slice
# boundary directly under the cursor for a hair of jitter to flip across.
static func child_start_deg(parent_start_deg: float, parent_index: int, parent_count: int, child_count: int) -> float:
	if parent_count <= 0 or child_count <= 0:
		return 0.0
	var parent_mid := parent_start_deg + (float(parent_index) + 0.5) * (360.0 / float(parent_count))
	return wrapf(parent_mid - (360.0 / float(child_count)) * 0.5, 0.0, 360.0)

# How wide a wedge actually PAINTS: its share of the circle, narrowed by the look's fraction, then
# capped. Pure and separate from slice_polygon so the cap can be asserted on its own -- and note
# selection_at still knows nothing about any of it.
static func painted_span(count: int, paint_fraction: float, max_degrees: float) -> float:
	if count <= 0:
		return 0.0
	return minf(360.0 / float(count) * clampf(paint_fraction, 0.05, 1.0), maxf(max_degrees, 1.0))

# Where a slice's own sector points, whatever it paints there.
static func slice_mid_deg(index: int, count: int, start_deg: float) -> float:
	if count <= 0:
		return start_deg
	return start_deg + (float(index) + 0.5) * (360.0 / float(count))

# The DRAWN wedge: an annulus sector `span_deg` wide, centred on the slice's own sector. Godot's
# draw_arc strokes an arc rather than filling a wedge, so the polygon is built.
static func slice_polygon(centre: Vector2, r0: float, r1: float, index: int, count: int,
		start_deg: float, span_deg: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	if count <= 0:
		return points
	var mid := slice_mid_deg(index, count, start_deg)
	var half := span_deg * 0.5
	for i in range(ARC_SAMPLES_PER_SLICE + 1):
		var t := float(i) / float(ARC_SAMPLES_PER_SLICE)
		points.append(point_at(centre, r1, mid - half + (half * 2.0) * t))
	for i in range(ARC_SAMPLES_PER_SLICE + 1):
		var t := float(i) / float(ARC_SAMPLES_PER_SLICE)
		points.append(point_at(centre, r0, mid + half - (half * 2.0) * t))
	return points


func _ring_radii(level: int) -> Vector2:
	var r0 := RING_INNER_RADIUS + float(level) * (RING_THICKNESS + RING_GAP)
	return Vector2(r0, r0 + RING_THICKNESS)

func _paint_fraction(level: int) -> float:
	return clampf(PAINT_FRACTION - float(level) * PAINT_FRACTION_FALLOFF, 0.15, 1.0)

# Keep the whole stack on screen. Deferred by one frame at open because the Control has no size
# until it lays out, exactly as the dropdown's placement was.
func _clamp_centre() -> void:
	if _root == null:
		return
	var view := _root.get_viewport_rect().size
	var reach: float = _ring_radii(MAX_RING_DEPTH - 1).y + MENU_MARGIN
	_centre.x = clampf(_centre.x, reach, maxf(reach, view.x - reach))
	_centre.y = clampf(_centre.y, reach, maxf(reach, view.y - reach))
	_root.queue_redraw()


# ==============================================================================
#  Input -- the whole model
# ==============================================================================

# The MOUSE adapter, and the only place in this file that knows what a mouse is. Everything it
# calls -- aim_at / commit / back -- is the model's own vocabulary, which is the whole portability
# claim: another input source is another function this short, not a second hit test.
func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		aim_at((event as InputEventMouseMotion).position)
		return
	if not (event is InputEventMouseButton):
		return
	var button := event as InputEventMouseButton
	if not button.pressed:
		return
	if button.button_index == MOUSE_BUTTON_RIGHT:
		back()
	elif button.button_index == MOUSE_BUTTON_LEFT:
		aim_at(button.position)
		commit()

# "The pointer is here." Distance is discarded except for the dead-zone test.
func aim_at(point: Vector2) -> void:
	var level := _deepest()
	var nodes: Array = level["nodes"]
	var start: float = level["start_deg"]
	var picked := selection_at(point, _centre, nodes.size(), start)
	if picked == _selection:
		return
	_selection = picked
	_hover_seconds = 0.0   # a new slice starts its own wait; the readout never carries over
	_refresh_preview()
	_root.queue_redraw()


# The only thing this node processes: the readout's hover clock. It redraws exactly ONCE, on the
# frame the wait is served, rather than every frame -- a menu that repainted continuously would be
# paying for a panel that is not there yet.
func _process(delta: float) -> void:
	if _selection < 0 or _root == null:
		return
	var was_due := _readout_due()
	_hover_seconds += delta
	if _readout_due() != was_due:
		_root.queue_redraw()

# The ghost ring: the hovered category's children, drawn one level out in a not-open-yet state so
# every category's contents can be read without spending a click.
func _refresh_preview() -> void:
	_preview = []
	var node := selected_node()
	if node.is_empty() or _levels.size() >= MAX_RING_DEPTH:
		return
	var children: Array = node.get("children", [])
	if children.is_empty():
		return
	var level := _deepest()
	var nodes: Array = level["nodes"]
	_preview = children
	_preview_start = child_start_deg(level["start_deg"], _selection, nodes.size(), children.size())

# Left click. A category grows a ring and the menu SURVIVES; only a leaf ends it.
func commit() -> void:
	if _selection < 0:
		dismiss()
		return
	var node := selected_node()
	if node.is_empty() or bool(node.get("disabled", false)):
		return
	var children: Array = node.get("children", [])
	if not children.is_empty():
		var level := _deepest()
		var nodes: Array = level["nodes"]
		_levels.append({
			"nodes": children,
			"start_deg": child_start_deg(level["start_deg"], _selection, nodes.size(), children.size()),
		})
		_selection = -1
		_preview = []
		_root.queue_redraw()
		return
	# Terminal: clear-then-act, the ordering the stateless verbs and the targeting verbs both
	# depend on, and the ONLY path that still emits `cancelled`.
	cancelled.emit(self)
	action_selected.emit(int(node.get("id", -1)), local_unit)
	cleanup()

# Right click. One ring at a time, and dismiss once there is nothing left to pop.
func back() -> void:
	if _levels.size() <= 1:
		dismiss()
		return
	_levels.pop_back()
	_selection = -1
	_preview = []
	_root.queue_redraw()

func dismiss() -> void:
	cancelled.emit(self)
	cleanup()

func cleanup() -> void:
	queue_free()


func _deepest() -> Dictionary:
	return _levels[_levels.size() - 1]

# What the ring is showing right now: the live level's rows, where it starts, and how deep the
# stack is. Public because "what am I displaying" is a fair question to ask a widget -- the
# catalogue law reads these to assert on what the player can actually see.
func level_nodes() -> Array:
	if _levels.is_empty():
		return []
	return _deepest()["nodes"]

func level_start_deg() -> float:
	if _levels.is_empty():
		return 0.0
	return _deepest()["start_deg"]

func level_count() -> int:
	return _levels.size()

func centre() -> Vector2:
	return _centre

# Where slice `index` of the live ring is drawn, at whatever distance. Any point on that ray
# selects it -- the radius here is only to land outside the dead zone.
func point_in_slice(index: int, distance := 0.0) -> Vector2:
	var nodes := level_nodes()
	if nodes.is_empty():
		return _centre
	var span := 360.0 / float(nodes.size())
	var mid := level_start_deg() + (float(index) + 0.5) * span
	var radius: float = distance if distance > 0.0 else DEAD_ZONE_RADIUS + RING_THICKNESS
	return point_at(_centre, radius, mid)

func selected_node() -> Dictionary:
	if _selection < 0 or _levels.is_empty():
		return {}
	var nodes: Array = _deepest()["nodes"]
	if _selection >= nodes.size():
		return {}
	return nodes[_selection]


# ==============================================================================
#  Drawing
# ==============================================================================

func _on_draw() -> void:
	for level in range(_levels.size()):
		var is_deepest := level == _levels.size() - 1
		_draw_ring(_levels[level]["nodes"], _levels[level]["start_deg"], level, is_deepest, 1.0)
	if not _preview.is_empty():
		_draw_ring(_preview, _preview_start, _levels.size(), false, GHOST_ALPHA)
	_draw_centre()
	_draw_readout()

# `live` is what marks the ring that owns the angle; a shallower one is the path you took, drawn
# so you can see where you are and dimmed so it does not read as pointable.
func _draw_ring(nodes: Array, start_deg: float, level: int, live: bool, alpha: float) -> void:
	var radii := _ring_radii(level)
	var font := _root.get_theme_default_font()
	var font_size := _root.get_theme_default_font_size()
	for i in range(nodes.size()):
		var node: Dictionary = nodes[i]
		var color := SLICE_COLOR
		if bool(node.get("disabled", false)):
			color = SLICE_DISABLED_COLOR
		elif live and i == _selection:
			color = SLICE_SELECTED_COLOR
		color.a *= alpha
		if not live:
			color.a *= 0.7
		var span := painted_span(nodes.size(), _paint_fraction(level), MAX_WEDGE_DEGREES)
		_root.draw_colored_polygon(
			slice_polygon(_centre, radii.x, radii.y, i, nodes.size(), start_deg, span), color)
		_draw_slice_label(node, radii, i, nodes.size(), start_deg, span, font, font_size, alpha)

# A label rides the CURVE of its own wedge rather than sitting flat across it, which is what keeps
# a long name inside the paint instead of hanging off both ends (dev: "words should do their best
# to never leave the menu buttons"). Two things make it readable:
#
#   THE FLIP. Rotating by the slice's own angle points the text's head OUTWARD, which reads
#   upright on the top half and upside-down on the bottom, so the bottom half turns a further
#   180 degrees and reads with its head INWARD. Standard rubber-stamp arrangement, and the reason
#   `cos` is the test: it is positive exactly on the half where outward is up-screen.
#
#   THE SHRINK. If the name is still wider than the arc it has, the font drops until it fits, to
#   a floor -- a name that overruns is worse than a name that is small.
func _draw_slice_label(node: Dictionary, radii: Vector2, index: int, count: int, start_deg: float,
		span_deg: float, font: Font, font_size: int, alpha: float) -> void:
	if font == null:
		return
	var text: String = node.get("name", "")
	if text == "":
		return

	var mid := slice_mid_deg(index, count, start_deg)
	var radius := (radii.x + radii.y) * 0.5
	var rot := deg_to_rad(mid)
	if cos(rot) < 0.0:
		rot += PI

	var available := deg_to_rad(span_deg) * radius
	var size := font_size
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	if width > available and width > 0.0:
		size = maxi(MIN_LABEL_FONT_SIZE, int(floor(float(size) * available / width)))
		width = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x

	# Deliberately NOT scaled by the ring's alpha: on a ghosted ring the label is the entire point
	# of the preview, so it stays solid even while its wedge is not.
	var color := READOUT_TITLE_COLOR
	if bool(node.get("disabled", false)):
		color = Color(color.r, color.g, color.b, 0.55)

	# draw_set_transform applies to everything after it, so the identity has to go back on.
	_root.draw_set_transform(point_at(_centre, radius, mid), rot, Vector2.ONE)
	_root.draw_string(font, Vector2(-width * 0.5, float(size) * 0.35), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, color)
	_root.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# The centre is the unit's map sprite and nothing else -- the whole point of the wide gap. Same
# accessor the action queue's actor icon reads, so the two surfaces can never show different art.
func _draw_centre() -> void:
	# The disc first, and it is drawn whether or not there is a sprite: it is the dead zone made
	# visible, so its absence would be a lie about where clicking does nothing.
	_root.draw_circle(_centre, DEAD_ZONE_RADIUS, CENTRE_COLOR)
	if CENTRE_RIM_WIDTH > 0.0:
		_root.draw_arc(_centre, DEAD_ZONE_RADIUS, 0.0, TAU, 64, CENTRE_RIM_COLOR, CENTRE_RIM_WIDTH, true)
	if local_unit == null or not is_instance_valid(local_unit):
		return
	var tex := local_unit.get_map_sprite_texture()
	if tex == null:
		return
	var native := Vector2(tex.get_width(), tex.get_height())
	if native.x <= 0.0 or native.y <= 0.0:
		return
	var scale := (DEAD_ZONE_RADIUS * SPRITE_FIT) / maxf(native.x, native.y)
	var size := native * scale
	_root.draw_texture_rect(tex, Rect2(_centre - size * 0.5, size), false)

# The readout sits BELOW the whole stack, not in the centre: the pointer is routinely nowhere near
# the ring, so this is the only feedback that exists, and it needs room the sprite is using.
func _draw_readout() -> void:
	if not _readout_due():
		return
	var node := selected_node()
	if node.is_empty():
		return
	var font := _root.get_theme_default_font()
	if font == null:
		return
	var font_size := _root.get_theme_default_font_size()

	# Every line first, because the panel has to be sized before anything is drawn on it. The
	# detail arrives already wrapped from MainActionMenu._entry -- the stored text IS the
	# displayed text, so this only has to split it.
	var lines: Array[String] = []
	var title := String(node.get("name", ""))
	if title != "":
		lines.append(title)
	var detail := String(node.get("tooltip", ""))
	if detail != "":
		for line in detail.split("\n"):
			lines.append(line)
	if lines.is_empty():
		return

	var line_height := float(font_size) * 1.35
	var widest := 0.0
	for line: String in lines:
		widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x)

	var top: float = _centre.y + _ring_radii(_levels.size() - 1).y + float(font_size)
	var box := Rect2(
		_centre.x - widest * 0.5 - READOUT_PADDING,
		top - READOUT_PADDING,
		widest + READOUT_PADDING * 2.0,
		line_height * float(lines.size()) + READOUT_PADDING * 2.0)
	_root.draw_rect(box, READOUT_BACKGROUND, true)
	if READOUT_BORDER_WIDTH > 0.0:
		_root.draw_rect(box, READOUT_BORDER, false, READOUT_BORDER_WIDTH)

	# Solid, both of them (dev, round 3: "the transparency + lack of background hurts the eyes").
	# The hierarchy between the name and its explanation is BRIGHTNESS, never alpha -- alpha is what
	# made this hard to read in the first place.
	var y := top + float(font_size)
	for i in range(lines.size()):
		_draw_centred_line(font, font_size, lines[i], y,
			READOUT_TITLE_COLOR if i == 0 else READOUT_DETAIL_COLOR)
		y += line_height


# The readout waits out a hover, so sweeping the ring does not strobe a panel under it. The delay
# is the PROJECT'S tooltip delay -- the same store the inspect panel's own hover text reads
# (`gui/timers/tooltip_delay_sec`), so the two surfaces cannot drift apart or need a second number
# to keep in sync (dev: "same amount as in the inspect menu").
func _readout_due() -> bool:
	return _selection >= 0 and _hover_seconds >= hover_delay()

static func hover_delay() -> float:
	return float(ProjectSettings.get_setting("gui/timers/tooltip_delay_sec", 0.5))

func _draw_centred_line(font: Font, font_size: int, text: String, y: float, color: Color) -> void:
	if text == "":
		return
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	_root.draw_string(font, Vector2(_centre.x - width * 0.5, y), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
