extends Control
class_name AuraRing

# A unit's elemental aura, as a ring of five fixed sectors with five ticks each -- one filled tick per
# aura point (#930). Two surfaces draw it: small around the pre-mission card's portrait, large and
# labelled in the in-battle inspect panel, which is #292's parity asked before rather than after.
#
# THE FIRST _draw() WIDGET IN Classes/ui/ (presentation/UnitHealthBar.gd is the only precedent
# anywhere). A ring of 25 rotated ticks is not a container of Labels, and the hover highlight has to
# repaint one sector rather than rebuild a row -- but it IS a new shape for this folder, said out loud
# here and in #930's PR body rather than left to be found in a diff.
#
# IT DERIVES NOTHING AND JUDGES NOTHING. rows() is the whole model and _draw() renders what it
# returns -- which is also what lets a headless suite assert the readout without a pixel.
#
# AFFINITY AND AURA ARE TWO FIELDS AND THIS IS WHERE THAT PAYS OFF (UnitInstance.gd's own note): the
# limb tax empties a pool while the growth right survives, so a tick has THREE states, not two. Lit is
# an aura point; dim-but-coloured is an affinity with nothing in it yet; faint grey is an element this
# unit can never grow. A readout keyed on `aura >= 1` erases exactly the case the model was split for.
#
# THE HIDDEN SIXTH IS NEVER DRAWN, structurally rather than by a filter: rows() walks
# Elemental.SIGIL_ELEMENTS, and alkahest is not in that vocabulary at all -- it is a bool on
# UnitInstance that nothing here reads (docs/design/alchemy-kit.md: "no Alkahest bar; Isaac simply
# shows aura in every element").
#
# THE INK IS THE SURFACE'S, NOT THIS CLASS'S. The card is parchment-skinnable and reads QueueStyle;
# the inspect panel is not and does not. One source would hand the panel's permanently dark ground the
# hues _adapt darkened for cream paper -- #814's bug, one surface further on -- so the caller says
# which ground this ring is landing on and every colour below follows that one fork.

# Fire<->Water and Earth<->Air are the two oppositions (alchemy-kit.md). Five sectors put the furthest
# pair 144 degrees apart, and this order puts BOTH pairs there; Aether -- life and spirit, the odd one
# out -- takes the arc that is left. A PERMUTATION of Elemental.SIGIL_ELEMENTS, which
# test_aura_ring pins: a sixth sigil must fail loudly rather than silently lose a sector.
const WHEEL: Array[Elemental.Element] = [
	Elemental.Element.FIRE,
	Elemental.Element.AIR,
	Elemental.Element.WATER,
	Elemental.Element.AETHER,
	Elemental.Element.EARTH,
]

# A DISPLAY cap, and only that. Aura has no ceiling in the model (alchemy-kit.md: "no ceiling number:
# scarcity is the cap"); content soft-caps at weight 3 and the deepest pool anyone ships is Dorian's
# Aether 5. Past five the ring draws five and the READOUT carries the real integer -- the half that
# cannot lie.
const MAX_TICKS := 5

# Sector 0 STARTS at twelve o'clock and the wheel runs clockwise, which is the arrangement the #930
# mockup was ruled on. A sector's label sits at the middle of its own arc.
const SECTOR := TAU / 5.0
const ARC_START := -PI / 2.0
const SECTOR_PAD := deg_to_rad(5.0)     # the gap between one element's arc and the next

const BAND_RATIO := 0.16                # tick length, as a fraction of the outer radius
const TICK_W_RATIO := 0.11              # tick thickness, as a fraction of the mid radius
const CLEARANCE := 1.0                  # how far the band sits outside the portrait's ink box
# Inside this fraction of the outer radius is the PORTRAIT, not a sector: pointing at the character's
# face is not pointing at an element. Outside it the whole 72-degree wedge is the target, because
# hitting a four-pixel band with a mouse is not a thing to ask of anyone.
const HOT_RATIO := 0.6

const DIM_ALPHA := 0.30                 # affine, pool empty -- the limb tax, or not yet grown
const FAINT_ALPHA := 0.16               # an element this unit can never grow

# Which palette this ring's colours come out of -- see the header. SKINNED follows the player's menu
# colours (the pre-mission card); AUTHORED is the dev's own element wheel (the inspect panel).
enum Ground { AUTHORED, SKINNED }

# One element's line in the readout. rows() is the model; everything below only draws it.
class Row:
	var element: Elemental.Element = Elemental.Element.NONE
	var affine := false
	var depth := 0


var unit: Unit
var ground: Ground = Ground.AUTHORED
var labelled := false                   # element names at the arcs (the panel has room; the card does not)
var portrait: Texture2D                 # drawn in the middle, card-side; null leaves the centre empty

# Which element the cursor is in, or NONE. Public because it is the one piece of hover state a
# headless case can assert -- _gui_input takes a synthetic motion event and this is the answer.
var hovered: Elemental.Element = Elemental.Element.NONE

var _centre := Vector2.ZERO
var _outer := 0.0
var _inner := 0.0


# --- the model -------------------------------------------------------------------------------------

# Every sigil element, in wheel order, with what this unit can grow and what it holds. Read through
# Unit -- never UnitInstance -- because PreMissionCard's law is that a second implementation reading
# the instance directly is the duplicate seam spawning the roster as real Units exists to prevent.
static func rows(target: Unit) -> Array[Row]:
	var result: Array[Row] = []
	if target == null:
		return result
	for element: Elemental.Element in WHEEL:
		var row := Row.new()
		row.element = element
		row.affine = target.has_affinity(element)
		row.depth = target.get_element_aura(element)
		result.append(row)
	return result


# The sentence both surfaces hover, built once here. The concept's own wording comes off the Glossary
# so the card, the panel and the glossary page cannot word it three ways; only the numbers are local.
#
# THE LIST IS IN RANK ORDER, not wheel order and not depth order. Affinity is an ordered set whose
# [0] reads as primary, and since #930 draws no primary marker this text is the only place rank
# survives -- which matters because rank and depth genuinely disagree in shipped content (Celest's
# primary Earth is her shallowest pool).
static func readout(target: Unit) -> String:
	if target == null:
		return ""
	var lines: Array[String] = [Glossary.short(Glossary.Term.AURA)]
	var order: Array[Elemental.Element] = target.affinity_order()
	if order.is_empty():
		lines.append("No elemental affinity — a rune is inert rock in this unit's hands.")
		return UiText.wrap("\n".join(lines))

	var parts: Array[String] = []
	var any_empty := false
	for element: Elemental.Element in order:
		var depth := target.get_element_aura(element)
		any_empty = any_empty or depth == 0
		parts.append("%s %d" % [Elemental.display_name(element), depth])
	lines.append("%s (in affinity rank order — %s is primary)"
		% [" · ".join(parts), Elemental.display_name(order[0])])
	if any_empty:
		lines.append("An element at 0 is still theirs to grow: a lost limb empties the deepest pool "
			+ "without taking the affinity with it.")
	return UiText.wrap("\n".join(lines))


# --- building --------------------------------------------------------------------------------------

# The card's ring: it FRAMES THE CHARACTER, not the canvas. Every map sprite draws its ink in the
# lower half of its sheet (MapSpriteInk), so a ring centred on the 52px box would sit a third of the
# box above the person inside it -- #560's finding, arriving at a second surface.
static func for_portrait(target: Unit, sprite: Texture2D, box_px: float) -> AuraRing:
	var ring := AuraRing.new()
	ring.unit = target
	ring.portrait = sprite
	ring.ground = Ground.SKINNED
	ring._centre = MapSpriteInk.ink_centre(box_px)
	ring._inner = MapSpriteInk.ink_reach(box_px) + CLEARANCE
	ring._outer = ring._inner / (1.0 - BAND_RATIO)
	# Tall enough for the band below the ink; the ink sits low, so the ring never clears the top edge.
	ring.custom_minimum_size = Vector2(box_px, ceilf(ring._centre.y + ring._outer))
	ring._ready_common()
	return ring


# The inspect panel's: no portrait in the middle, and the room to name every element (dev, #930).
static func standing(target: Unit, size_px: float) -> AuraRing:
	var ring := AuraRing.new()
	ring.unit = target
	ring.labelled = true
	ring.ground = Ground.AUTHORED
	ring._centre = Vector2(size_px, size_px) * 0.5
	ring._outer = size_px * 0.30          # the rest of the radius is the label ring
	ring._inner = ring._outer * (1.0 - BAND_RATIO)
	ring.custom_minimum_size = Vector2(size_px, size_px)
	ring._ready_common()
	return ring


func _ready_common() -> void:
	# STOP, or _gui_input never fires and the whole hover is dead. There is no child node to steal it
	# from us: the portrait is DRAWN rather than parented, which is also what lets the hover scrim
	# land on top of it instead of underneath.
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	refresh()


# Everything that can change under a standing ring: the pool itself moves when a limb is lost.
func refresh() -> void:
	tooltip_text = readout(unit)
	queue_redraw()


func set_unit(target: Unit) -> void:
	unit = target
	hovered = Elemental.Element.NONE
	refresh()


# --- hover -----------------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion == null:
		return
	_set_hovered(element_at(motion.position))


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_set_hovered(Elemental.Element.NONE)


# Which element owns the point under the cursor. PUBLIC so a case can ask it directly, and because
# _gui_input's own answer is the thing worth pinning -- an angle bucket off by one sector is a bug
# no assertion about colour would catch.
func element_at(point: Vector2) -> Elemental.Element:
	var offset := point - _centre
	if offset.length() < _outer * HOT_RATIO:
		return Elemental.Element.NONE
	var turn := wrapf(offset.angle() - ARC_START, 0.0, TAU)
	return WHEEL[mini(int(turn / SECTOR), WHEEL.size() - 1)]


func _set_hovered(element: Elemental.Element) -> void:
	if hovered == element:
		return
	hovered = element
	queue_redraw()


# --- drawing ---------------------------------------------------------------------------------------

func _draw() -> void:
	if portrait != null:
		draw_texture_rect(portrait, Rect2(Vector2.ZERO, Vector2(size.x, size.x)), false)
	var mid := (_inner + _outer) * 0.5
	var width := maxf(2.0, mid * TICK_W_RATIO)
	var model := rows(unit)
	for i in model.size():
		_draw_sector(model[i], i, width)
	if hovered != Elemental.Element.NONE:
		_draw_hover_readout(model)


func _draw_sector(row: Row, index: int, width: float) -> void:
	var lit := _element_ink(row.element)
	var usable := SECTOR - SECTOR_PAD * 2.0
	var start := ARC_START + index * SECTOR + SECTOR_PAD
	var highlighted := hovered == row.element
	for k in MAX_TICKS:
		var angle := start + usable * (float(k) + 0.5) / float(MAX_TICKS)
		var step := Vector2(cos(angle), sin(angle))
		var from := _centre + step * _inner
		var to := _centre + step * _outer
		# The outline is drawn UNDER a wider stroke of the same line, which is what makes it read as an
		# outline rather than as a second tick beside the first.
		if highlighted:
			draw_line(from, to, _outline_ink(), width + 2.0, true)
		var ink := lit
		if k >= row.depth:
			ink.a = DIM_ALPHA if row.affine else FAINT_ALPHA
			if not row.affine:
				ink = _neutral_ink(ink.a)
		draw_line(from, to, ink, width, true)
	if labelled:
		_draw_label(row, index, highlighted)


func _draw_label(row: Row, index: int, highlighted: bool) -> void:
	var font := get_theme_default_font()
	var font_size := 11
	var angle := ARC_START + (float(index) + 0.5) * SECTOR
	var at := _centre + Vector2(cos(angle), sin(angle)) * (_outer + font_size * 1.4)
	var ink := _outline_ink() if highlighted else _element_ink(row.element)
	if not highlighted and not row.affine:
		ink = _neutral_ink(0.55)
	var box := font.get_string_size(Elemental.display_name(row.element),
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(font, at - box * Vector2(0.5, -0.35), Elemental.display_name(row.element),
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)


# "Aether 2" across the middle while the cursor is in that arc (dev, #930). On the card that means
# over the portrait, so the ground's own colour goes down first -- a SCRIM rather than a modulate,
# because darkening the sprite would be right on slate and wrong on parchment's cream paper.
func _draw_hover_readout(model: Array[Row]) -> void:
	var row: Row = null
	for candidate: Row in model:
		if candidate.element == hovered:
			row = candidate
	if row == null:
		return
	var font := get_theme_default_font()
	var font_size := 11
	var text := "%s %d" % [Elemental.display_name(row.element), row.depth]
	if portrait != null:
		var scrim := _ground_ink()
		scrim.a = 0.86
		draw_circle(_centre, _inner, scrim)
	var box := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(font, _centre - box * Vector2(0.5, -0.35), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, _element_ink(row.element))


# --- ink, per ground --------------------------------------------------------------------------------

func _element_ink(element: Elemental.Element) -> Color:
	return QueueStyle.element_ink(element) if ground == Ground.SKINNED \
		else ElementPalette.color_for_element(element)


# What a highlight is drawn in. BODY_TEXT is the role that means "text on this surface's own ground",
# so on the card it is white over slate and dark ink over parchment -- a highlight that cannot vanish
# into the paper it lands on. The panel has one ground and takes its own near-white.
func _outline_ink() -> Color:
	return QueueStyle.ink(QueueStyle.Role.BODY_TEXT) if ground == Ground.SKINNED \
		else Color(0.95, 0.96, 0.98)


func _ground_ink() -> Color:
	return QueueStyle.ink(QueueStyle.Role.SECTION_BG) if ground == Ground.SKINNED \
		else Color(0.09, 0.09, 0.1)


func _neutral_ink(alpha: float) -> Color:
	var ink := ElementPalette.NEUTRAL if ground == Ground.AUTHORED \
		else QueueStyle.adapted_ink(ElementPalette.NEUTRAL)
	ink.a = alpha
	return ink
