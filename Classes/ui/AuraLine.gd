extends Control
class_name AuraLine

# The rune card's aura LINE (#1319): the carrier's pool with a carving's demand laid over it, drawn as
# one row across the card above the plate -- each element's name, then five ticks. It replaced the
# AuraRing that stood beside the plate (#1019) on the dev's ruling (2026-11-09: "change that to a line,
# perhaps above it, let that whole space be filled out by the range display").
#
# IT DRAWS AuraRing's MODEL AND OWNS NONE. AuraRing.rows() is the one answer to what a unit holds and a
# carving asks, and AuraRing.readout() is the one sentence explaining it (this line's tooltip); the
# ring and this line are two drawings of that model, the PathArrows/PathLines split. What this class
# owns is the DEMAND's marks, since no ring draws a demand any more.
#
# A TICK HAS FIVE STATES (tick_state): held; spare (held past the recipe, in an element the hit scales
# off, so it is damage); asked for and not held (hollow -- an outline, because DIM_ALPHA and FAINT_ALPHA
# already spend the alpha channel); an affinity not grown (dim); an element never growable (faint
# grey). What the carving asks is an UNDERLINE under that many ticks, where the ring drew an arc
# (#1022). An element the carving does not ask for is knocked back by saturation, never alpha.
#
# AUTHORED INK: the line sits on ModalCard's frame, dark under both palettes (#814's question, asked).

# One tick per aura point up to AuraRing.MAX_TICKS, the ring's display cap: the tooltip carries the
# real integer past it.
const BAR := Vector2(5, 14)
const GAP := 3.0                 # between two ticks of one element
const GROUP_GAP := 16.0          # between one element's ticks and the next element's name
const NAME_GAP := 4.0            # between a name and its first tick
const FONT_SIZE := 11
const UNDERLINE_W := 2.0
const UNDERLINE_DROP := 3.5      # the bar's foot -> the underline's centreline
const PAD_TOP := 3.0
const HEIGHT := 24.0

const HOLLOW_ALPHA := 0.85
const HOLLOW_EDGE := 1.2
# The glow behind a spare tick, per side. Two spare ticks side by side must keep a drawable gap
# (GAP - 2 * HALO_GROW >= 1px, test_aura_line), or the run reads as one block -- #930's fuse failure.
const HALO_GROW := 1.0
const HALO_ALPHA := 0.35
# How far an element the carving does not ask for is knocked back while a demand is on screen.
const OFF_RECIPE_SATURATION := 0.35

enum Tick { HELD, SPARE, ASKED, AFFINE, NEVER }

var unit: Unit
var carving: TransmutationData


static func for_carrier(target: Unit) -> AuraLine:
	var line := AuraLine.new()
	line.unit = target
	# STOP, or the readout tooltip is dead.
	line.mouse_filter = Control.MOUSE_FILTER_STOP
	line.refresh()
	return line


# Which carving's demand this line shows, or null for the pool alone.
func set_carving(demand: TransmutationData) -> void:
	carving = demand
	refresh()


func refresh() -> void:
	tooltip_text = AuraRing.readout(unit, carving)
	visible = not AuraRing.rows(unit, carving).is_empty()
	update_minimum_size()
	queue_redraw()


# --- the model's marks -----------------------------------------------------------------------------

# What tick `k` of `row` is. Pure, so a case can pin the hollow and halo rules without a pixel.
static func tick_state(row: AuraRing.Row, k: int) -> Tick:
	if k < row.depth:
		return Tick.SPARE if row.wanted > 0 and row.scales and k >= row.wanted else Tick.HELD
	if k < row.wanted:
		return Tick.ASKED
	return Tick.AFFINE if row.affine else Tick.NEVER


# An element the shown carving does not ask for. SATURATION, never alpha: an alpha knock-back reads as
# a third empty state rather than as a quieter colour.
static func knocked_back(ink: Color) -> Color:
	var quiet := ink
	quiet.s *= OFF_RECIPE_SATURATION
	return quiet


# --- drawing ---------------------------------------------------------------------------------------

func _get_minimum_size() -> Vector2:
	var font := get_theme_default_font()
	if font == null:
		return Vector2(0.0, HEIGHT)
	var width := 0.0
	for row: AuraRing.Row in AuraRing.rows(unit, carving):
		width += _name_width(font, row.element) + NAME_GAP + _ticks_width() + GROUP_GAP
	return Vector2(maxf(0.0, width - GROUP_GAP), HEIGHT)


func _draw() -> void:
	var font := get_theme_default_font()
	var demanded := carving != null
	var x := 0.0
	for row: AuraRing.Row in AuraRing.rows(unit, carving):
		var lit := ElementPalette.color_for_element(row.element)
		if demanded and row.wanted == 0:
			lit = knocked_back(lit)
		draw_string(font, Vector2(x, PAD_TOP + BAR.y - 2.0), Elemental.display_name(row.element),
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE, lit)
		x += _name_width(font, row.element) + NAME_GAP
		var start := x
		for k in AuraRing.MAX_TICKS:
			_draw_tick(Rect2(Vector2(x, PAD_TOP), BAR), tick_state(row, k), lit)
			x += BAR.x + GAP
		if row.wanted > 0:
			var foot := PAD_TOP + BAR.y + UNDERLINE_DROP
			var span := float(mini(row.wanted, AuraRing.MAX_TICKS)) * (BAR.x + GAP) - GAP
			draw_line(Vector2(start, foot), Vector2(start + span, foot),
				ElementPalette.color_for_element(row.element), UNDERLINE_W)
		x += GROUP_GAP - GAP


func _draw_tick(bar: Rect2, state: Tick, lit: Color) -> void:
	match state:
		Tick.HELD:
			draw_rect(bar, lit, true)
		Tick.SPARE:
			draw_rect(bar.grow(HALO_GROW), Color(lit, HALO_ALPHA), true)
			draw_rect(bar, lit, true)
		Tick.ASKED:
			draw_rect(bar.grow(-HOLLOW_EDGE * 0.5), Color(lit, HOLLOW_ALPHA), false, HOLLOW_EDGE)
		Tick.AFFINE:
			draw_rect(bar, Color(lit, AuraRing.DIM_ALPHA), true)
		Tick.NEVER:
			draw_rect(bar, Color(ElementPalette.NEUTRAL, AuraRing.FAINT_ALPHA), true)


static func _name_width(font: Font, element: Elemental.Element) -> float:
	return font.get_string_size(Elemental.display_name(element), HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		FONT_SIZE).x


static func _ticks_width() -> float:
	return AuraRing.MAX_TICKS * (BAR.x + GAP) - GAP
