extends Control
class_name AuraRing

# A unit's elemental aura, as a ring of five fixed sectors with five ticks each -- one filled tick per
# aura point (#930). THREE surfaces draw it: the pre-mission card's 52px map sprite, the inspect
# panel's 96px portrait at twice the size, and the rune detail card (#1019), which overlays what a
# carving ASKS FOR on top of what the carrier holds. #292's parity asked before rather than after,
# and one motif rather than two.
#
# THE RUNE CARD'S RING MAY HAVE NO CARRIER AT ALL -- a rune in the stash is held by nobody, so the
# centre is empty and every sector reads as pure demand. That is why rows() takes both halves and
# refuses only when it is given neither.
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
# A DEMAND ADDS TWO MORE (#1019), and only when one is being shown. HOLLOW is a tick the carving asks
# for and the carrier does not hold -- the deficit, drawn as an outline rather than at a lower alpha,
# because alpha is the channel the two empty states already use and a third value on it is
# indistinguishable at a 5px tick. HALOED is a tick held PAST the recipe: base_damage sums the
# wielder's aura over every sigil and is uncapped, so a surplus point is not waste, it is damage, and
# nothing on screen said so. A sector the recipe does not ask for is knocked back by DESATURATION,
# for the same reason hollow is not an alpha -- so the recipe's own elements read first without any
# empty tick changing what it means.
#
# ...AND THE COST IS AN ARC, outside the band, spanning exactly the ticks the carving asks for
# (#1022). The ticks say what is PAID and the arc says what is OWED, which is why it is a stroke
# rather than more marks: a quantity read round the sector in one gesture cannot be miscounted the
# way five separate bars can.
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
const CLEARANCE := 1.0                  # the gap between the portrait's ink box and the band
# Inside this fraction of the outer radius is the PORTRAIT, not a sector: pointing at the character's
# face is not pointing at an element. Outside it the whole 72-degree wedge is the target, because
# hitting a four-pixel band with a mouse is not a thing to ask of anyone.
const HOT_RATIO := 0.6

const DIM_ALPHA := 0.30                 # affine, pool empty -- the limb tax, or not yet grown
const FAINT_ALPHA := 0.16               # an element this unit can never grow

# What a HIGHLIGHTED bar looks like: the border is the bar's own width, and the colour shrinks to
# this fraction of it so the border has somewhere to be. The two are a pair -- lower the ratio for a
# heavier border, raise it to keep more colour -- and the tension they sit in is real: on the card a
# bar is 2.55px, so at 0.55 the border lands at ~0.57px a side and antialiases to a soft white edge
# rather than a crisp one. Growing it instead would put the footprint back where it fused.
const HOVER_CORE_RATIO := 0.55
const HOVER_BORDER := 0.8               # how far the border wraps past each END of the bar

# What an ASKED-FOR tick the carrier cannot pay looks like: the bar's outline at the element's own
# hue, with nothing inside it. The edge is a fraction of the bar's own width so the footprint is
# unchanged -- the HOVER_CORE_RATIO discipline, for the reason #930 found the hard way: anything that
# grows a bar SIDEWAYS fuses the five of them into one arc at the card's radius.
const HOLLOW_EDGE_RATIO := 0.30
const HOLLOW_ALPHA := 0.85

# The glow behind a tick held PAST what the recipe asks. A RATIO OF THE MID RADIUS, never a pixel
# count: the ticks sit `mid * 0.2164` apart at every ring size, so 0.053 a side is exactly where they
# fuse and a px constant that reads right on the 116px card is a solid ribbon on the 52px one. This is
# the smallest weight that still reads.
const HALO_SPREAD_RATIO := 0.034
const HALO_ALPHA := 0.35

# How far an OFF-RECIPE sector is knocked back while a demand is on screen -- saturation, never alpha.
# An alpha knock-back at 0.40 against DIM_ALPHA's 0.30 is indistinguishable at a 5px tick, so "holds
# two Aether the recipe does not want" and "has never grown Aether" would render as the same picture.
const OFF_RECIPE_SATURATION := 0.35

# THE DEMAND ARC: a solid stroke OUTSIDE the tick band spanning exactly the ticks this carving asks
# for, so the cost is one gesture read round the sector rather than a count of marks (#1022; it was
# in the approved mockup and #1019 shipped without it).
#
# The band gives up ARC_PAD_RATIO of the half-box to make room, and ONLY when a demand is drawn --
# which is what leaves the pre-mission card's 52px ring and the panel's 108px one at exactly the
# radius they had, by construction rather than by a flag anyone sets. All three are fractions of the
# same half-box, so they scale together and "the arc fits inside the node" is arithmetic a case can
# assert instead of a pixel count somebody typed.
const ARC_PAD_RATIO := 0.12
const ARC_GAP_RATIO := 0.069     # band's outer edge -> the arc's centreline
const ARC_WIDTH_RATIO := 0.041

# Which palette this ring's colours come out of -- see the header. SKINNED follows the player's menu
# colours (the pre-mission card); AUTHORED is the dev's own element wheel (the inspect panel).
enum Ground { AUTHORED, SKINNED }

# A `Fit` enum lived here until #990 and is deliberately gone rather than left inert: its whole job was
# deciding the centre, and the card's branch now computes exactly what the panel's does. Whether a ring
# DRAWS its own portrait is already answered by `portrait` being null or not.

# One element's line in the readout. rows() is the model; everything below only draws it.
class Row:
	var element: Elemental.Element = Elemental.Element.NONE
	var affine := false
	var depth := 0
	# How many sigils of this element the shown carving asks for; 0 when no carving is shown, and 0
	# for an element an off-recipe sector. Kept as the raw weight rather than as a deficit, because
	# the deficit is `wanted - depth` and the SURPLUS is `depth - wanted` -- one number answers both,
	# and a stored deficit could not say which ticks the halo belongs on.
	var wanted := 0


var unit: Unit
var ground: Ground = Ground.AUTHORED
var portrait: Texture2D                 # drawn in the middle, card-side; the panel's is a node below us
# The carving whose demand is drawn over the pool, or null. NOT a second model -- rows() folds it in,
# so _draw goes on rendering exactly what rows() returns (see the header's own law).
var carving: TransmutationData

# Which element the cursor is in, or NONE. Public because it is the one piece of hover state a
# headless case can assert -- _gui_input takes a synthetic motion event and this is the answer.
var hovered: Elemental.Element = Elemental.Element.NONE

var _centre := Vector2.ZERO
var _outer := 0.0
var _inner := 0.0
# Room reserved outside the band for the demand arc, or 0.0 when no demand is drawn. Derived in
# _layout beside the radii, for the same reason _portrait_rect is: a case reads the geometry the
# frame would have used rather than re-deriving it.
var _arc_room := 0.0
# Where the portrait is DRAWN -- derived in _layout beside the radii rather than worked out in _draw,
# so a headless case can read the geometry the frame would have used (#990).
var _portrait_rect := Rect2()


# --- the model -------------------------------------------------------------------------------------

# Every sigil element, in wheel order, with what this unit can grow and what it holds. Read through
# Unit -- never UnitInstance -- because PreMissionCard's law is that a second implementation reading
# the instance directly is the duplicate seam spawning the roster as real Units exists to prevent.
# A CARVING WITH NO CARRIER STILL HAS A MODEL, which is the one place the null contract widened
# (#1019): a rune in the stash is held by nobody, so every row reads depth 0 and affine FALSE while
# `wanted` carries the whole answer. `rows(null)` on its own is still empty, unchanged -- nothing to
# say about nobody is the honest answer when there is no demand either.
static func rows(target: Unit, demand: TransmutationData = null) -> Array[Row]:
	var result: Array[Row] = []
	if target == null and demand == null:
		return result
	for element: Elemental.Element in WHEEL:
		var row := Row.new()
		row.element = element
		row.affine = target != null and target.has_affinity(element)
		row.depth = target.get_element_aura(element) if target != null else 0
		row.wanted = demand.sigils.count(element) if demand != null else 0
		result.append(row)
	return result


# The sentence both surfaces hover, built once here. The concept's own wording comes off the Glossary
# so the card, the panel and the glossary page cannot word it three ways; only the numbers are local.
#
# THE LIST IS IN RANK ORDER, not wheel order and not depth order. Affinity is an ordered set whose
# [0] reads as primary, and since #930 draws no primary marker this text is the only place rank
# survives -- which matters because rank and depth genuinely disagree in shipped content (Celest's
# primary Earth is her shallowest pool).
static func readout(target: Unit, demand: TransmutationData = null) -> String:
	if target == null and demand == null:
		return ""
	var lines: Array[String] = [Glossary.short(Glossary.Term.AURA)]
	lines.append_array(_pool_lines(target))
	lines.append_array(_mark_lines(rows(target, demand), demand))
	return UiText.wrap("\n".join(lines))


# What this carrier holds, in affinity rank order. Empty for a ring with nobody in the middle, which
# is the rune card's stash case -- a demand is still worth explaining there, and a pool is not.
static func _pool_lines(target: Unit) -> Array[String]:
	var lines: Array[String] = []
	if target == null:
		lines.append("Nobody is carrying this, so the ring shows only what is asked for.")
		return lines
	var order: Array[Elemental.Element] = target.affinity_order()
	if order.is_empty():
		lines.append("No elemental affinity — a rune is inert rock in this unit's hands.")
		return lines

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
	return lines


# The ring explains its OWN MARKS and judges nothing (the header's law) -- whether a carving can
# actually be channelled is the ladder's answer and belongs to whoever is hosting this ring.
#
# EACH LINE IS KEYED ON A MARK THAT IS ACTUALLY DRAWN, so a recipe the carrier covers exactly says
# nothing at all rather than describing two states the picture does not contain.
static func _mark_lines(model: Array[Row], demand: TransmutationData) -> Array[String]:
	var lines: Array[String] = []
	if demand == null:
		return lines
	var short := false
	var spare := false
	for row: Row in model:
		short = short or row.wanted > row.depth
		spare = spare or (row.wanted > 0 and row.depth > row.wanted)
	if short:
		lines.append("A hollow mark is aura this circle asks for that is not there.")
	# The damage clause is the carving's own to make: a utility carving suppresses scaling outright
	# (AttackData.deals_no_damage), so surplus aura buys it nothing and saying otherwise would be a
	# readout promising a number the resolver never adds.
	if spare and demand.deals_no_damage:
		lines.append("A halo is aura past the recipe. This circle deals no damage, so it buys depth "
			+ "rather than force.")
	elif spare:
		lines.append("A halo is aura past the recipe — every point of it is damage.")
	return lines


# --- building --------------------------------------------------------------------------------------

# The card's ring: it FRAMES THE CHARACTER, not the canvas. Every map sprite draws its ink in the
# lower half of its sheet (MapSpriteInk), so the sprite is ZOOMED until the character fills the ring
# rather than fitted cell-and-all into the box -- #937's law, arriving at the surface its own sweep
# missed (#990). Until then 52px of column bought ~19px of character, and the ring, honestly framing
# that ink, came out 32px across inside a 52px node with the top 28 of it blank canvas.
#
# SQUARE, because the ring is concentric with its node now. That is 8px SHORTER than the old box, and
# the card's layout does not move: `who`'s height is set by the meta column beside this one either way.
static func for_portrait(target: Unit, sprite: Texture2D, box_px: float) -> AuraRing:
	var ring := AuraRing.new()
	ring.unit = target
	ring.portrait = sprite
	ring.ground = Ground.SKINNED
	# The one number stated anywhere; everything else is derived from the live rect (see _layout).
	ring.custom_minimum_size = Vector2(box_px, box_px)
	ring._ready_common()
	return ring


# The inspect panel's: laid OVER its own 96px portrait, which is drawn by the TextureRect beneath
# this node rather than by us -- so no ink offset (a portrait is not a map sprite) and no texture.
#
# IT SITS ON THE PORTRAIT'S OUTER EDGE RATHER THAN OUTSIDE IT, and that is arithmetic rather than
# taste: a circle clears a square only at radius >= half its diagonal, so a ring standing clear of a
# 96px portrait needs a 162px box -- +66px of header against the 72px of headroom the panel has
# (measured: its body wants 648 of 720 before this ticket). 108 costs 12 and reads as a ring laid on
# a portrait, which is the ordinary form of this motif anyway.
static func over_portrait(target: Unit) -> AuraRing:
	var ring := AuraRing.new()
	ring.unit = target
	ring.ground = Ground.AUTHORED
	ring._ready_common()
	return ring


# The rune card's (#1019): the carrier's pool with a carving's demand laid over it, sized to stand
# beside the plate rather than inside a column, so a hollow tick has room to read as an outline.
#
# AUTHORED, and that is #814's question asked rather than a copy of the panel's answer: this ring
# sits directly on ModalCard's frame, which is panel_box() and therefore dark under BOTH palettes
# (parchment's PANEL_BG is the dark frame its paper lies on). The cost bars further down that same
# card sit inside a section box -- paper, under parchment -- and take SKINNED. One card, two grounds.
#
# A NULL TARGET IS LEGAL and is the whole stash case: no sprite, an empty centre, demand only.
static func for_demand(target: Unit, sprite: Texture2D, box_px: float) -> AuraRing:
	var ring := AuraRing.new()
	ring.unit = target
	ring.portrait = sprite
	ring.ground = Ground.AUTHORED
	ring.custom_minimum_size = Vector2(box_px, box_px)
	ring._ready_common()
	return ring


func _ready_common() -> void:
	# STOP, or _gui_input never fires and the whole hover is dead. On the card there is no child node
	# to steal it either -- the portrait is DRAWN rather than parented, which is also what lets the
	# hover scrim land on top of it instead of underneath; on the panel the portrait is a SIBLING
	# below us, so the same is true one node along.
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	resized.connect(_layout)
	_layout()
	_bind()
	refresh()


# THE GEOMETRY IS DERIVED FROM THE RECT THIS RING ACTUALLY OCCUPIES, never from a size passed in.
# The panel's ring is a FULL_RECT child of a Panel, and a Panel aggregates nothing -- so a constant
# here would be a second answer to "how big is the ring" that the scene silently overrules, and the
# two would disagree the day either moved. Only the CARD states a number, because there its own
# minimum is what makes the column that wide.
#
# ONE ANSWER FOR BOTH SURFACES since #990. The panel's portrait fills its own square and the card's is
# zoomed until it does, so "where is the centre" stopped having two answers -- and the card is where
# that matters, because a ring the sprite is drawn INTO frames the character by construction rather
# than by agreeing with an offset (#560's finding, now structural).
func _layout() -> void:
	_centre = size * 0.5
	var half := minf(size.x, size.y) * 0.5
	# The band gives up room for the arc, and only while there is an arc -- see ARC_PAD_RATIO. A ring
	# with no carving is bit-identical to what it was before #1022.
	_arc_room = half * ARC_PAD_RATIO if carving != null else 0.0
	_outer = half - _arc_room
	_inner = _outer * (1.0 - BAND_RATIO)
	# CLEARANCE keeps its meaning and changes direction: the ink is drawn to just inside the band
	# rather than the band pushed out past the ink.
	if portrait != null:
		_portrait_rect = MapSpriteInk.ink_fit_rect(_centre, _inner - CLEARANCE)
	queue_redraw()


# Everything that can change under a standing ring: the pool itself moves when a limb is lost, and
# the demand moves whenever the host's picker lands on another carving.
func refresh() -> void:
	tooltip_text = readout(unit, carving)
	queue_redraw()


# Which carving's demand this ring shows, or null for none. One door rather than a public field the
# host writes and then has to remember to refresh behind.
func set_carving(demand: TransmutationData) -> void:
	carving = demand
	# THE RADIUS DEPENDS ON IT, so this re-lays out rather than only redrawing: the band shrinks to
	# make room for the arc the first time a demand arrives (see _layout).
	_layout()
	refresh()


func set_unit(target: Unit) -> void:
	_release()
	unit = target
	hovered = Elemental.Element.NONE
	_bind()
	refresh()


# THE RING KEEPS ITSELF CURRENT rather than waiting to be told, because the pool moves under a
# standing panel: every lost limb docks the deepest one, and `stats_changed` is the signal the settle
# pass after a maim already fires (Unit._go_downed -> _settle_stat_change). A host that had to
# remember to refresh it is a host that will forget on the next door that downs somebody.
func _bind() -> void:
	if unit != null and not unit.stats_changed.is_connected(refresh):
		unit.stats_changed.connect(refresh)


# Guarded the way info_panel guards its own teardown: a freed ref compares == null as TRUE (#149),
# so this has to ask whether the instance is still valid rather than whether it is null.
func _release() -> void:
	if unit != null and is_instance_valid(unit) and unit.stats_changed.is_connected(refresh):
		unit.stats_changed.disconnect(refresh)


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
		draw_texture_rect(portrait, _portrait_rect, false)
	var mid := (_inner + _outer) * 0.5
	var width := maxf(2.0, mid * TICK_W_RATIO)
	var model := rows(unit, carving)
	# A HALO IS SIZED OFF THE MID RADIUS, so it keeps its proportion on all three surfaces -- see
	# HALO_SPREAD_RATIO. Solved once here rather than per sector, the radii being the ring's.
	var spread := mid * HALO_SPREAD_RATIO
	for i in model.size():
		_draw_sector(model[i], i, width, spread, carving != null)
	if hovered != Elemental.Element.NONE:
		_draw_hover_readout(model)


func _draw_sector(row: Row, index: int, width: float, spread: float, demanded: bool) -> void:
	var lit := _element_ink(row.element)
	# OFF-RECIPE, while a recipe is on screen: knocked back so the asked-for elements read first. It
	# is applied to the sector's HUE, so it reaches the lit ticks and the dim affine ones alike and
	# leaves the never-growable grey (which has no saturation to lose) exactly as it was.
	if demanded and row.wanted == 0:
		lit = knocked_back(lit)
	var usable := SECTOR - SECTOR_PAD * 2.0
	var start := ARC_START + index * SECTOR + SECTOR_PAD
	var highlighted := hovered == row.element
	for k in MAX_TICKS:
		var angle := start + usable * (float(k) + 0.5) / float(MAX_TICKS)
		var step := Vector2(cos(angle), sin(angle))
		var from := _centre + step * _inner
		var to := _centre + step * _outer
		var ink := lit
		var hollow := false
		if k >= row.depth:
			# ASKED FOR AND NOT HELD: hollow rather than dim, because DIM_ALPHA and FAINT_ALPHA
			# already spend the alpha channel and a third value on it reads as neither at 5px.
			if demanded and k < row.wanted:
				ink.a = HOLLOW_ALPHA
				hollow = true
			else:
				ink.a = DIM_ALPHA if row.affine else FAINT_ALPHA
				if not row.affine:
					ink = _neutral_ink(ink.a)
		elif row.wanted > 0 and k >= row.wanted:
			# HELD PAST THE RECIPE. Drawn BEHIND the bar rather than instead of it: the tick is an
			# ordinary aura point and the glow is the surplus, which is exactly what it buys.
			var glow := lit
			glow.a = HALO_ALPHA
			draw_line(from, to, glow, width + spread * 2.0, true)
		# THE BORDER STAYS INSIDE THE BAR'S OWN FOOTPRINT: drawn at the full width and a shade longer,
		# with the COLOUR shrinking to fit inside it. Every bar therefore keeps exactly the gap it
		# started with -- which is the whole point, because an outline that grew SIDEWAYS fused the
		# five of them into one arc: at the card's radius the bars sit 5.0px apart and `width + 2` is
		# 4.55px wide, leaving 0.5px between them. The panel's are 10.8px apart, which is why the same
		# code read correctly on one surface and as a solid ribbon on the other (dev, 2026-09-13).
		var bar := width
		if highlighted:
			var cap := step * HOVER_BORDER
			draw_line(from - cap, to + cap, _outline_ink(), width, true)
			bar = width * HOVER_CORE_RATIO
		if hollow:
			_draw_hollow(from, to, step, bar, ink)
		else:
			draw_line(from, to, ink, bar, true)

	# THE COST, as one stroke over the ticks it is owed in -- drawn last so it lies over nothing and
	# under nothing, being outside the band entirely. Its span is exactly the asked-for ticks, which
	# is what makes it readable as a QUANTITY rather than as decoration on the sector.
	if row.wanted > 0:
		_draw_demand_arc(start, usable, row.wanted, _element_ink(row.element))


# The demand arc for one sector. Its three numbers are fractions of the half-box (see ARC_PAD_RATIO),
# so the whole mark scales with the ring and cannot outgrow the room _layout reserved for it.
func _draw_demand_arc(start: float, usable: float, wanted: int, ink: Color) -> void:
	var half := _outer + _arc_room
	var radius := _outer + half * ARC_GAP_RATIO
	var thickness := maxf(1.5, half * ARC_WIDTH_RATIO)
	var span := usable * float(mini(wanted, MAX_TICKS)) / float(MAX_TICKS)
	draw_arc(_centre, radius, start, start + span, maxi(8, wanted * 8), ink, thickness, true)


# An empty bar, drawn as its own outline. INSET by half the stroke at all four sides so the mark's
# footprint is the filled bar's exactly -- the HOVER_BORDER discipline, and for the same reason: a
# mark that grew sideways would fuse the five of a sector into one arc at the card's radius.
#
# A POLYLINE rather than draw_rect, which is axis-aligned while every tick here is rotated onto its
# own sector's angle.
func _draw_hollow(from: Vector2, to: Vector2, step: Vector2, bar: float, ink: Color) -> void:
	var edge := maxf(1.0, bar * HOLLOW_EDGE_RATIO)
	var side := Vector2(-step.y, step.x) * maxf(0.5, (bar - edge) * 0.5)
	var cap := step * edge * 0.5
	var a := from + cap + side
	var b := to - cap + side
	var c := to - cap - side
	var d := from + cap - side
	draw_polyline(PackedVector2Array([a, b, c, d, a]), ink, edge, true)


# "Aether 2" across the middle while the cursor is in that arc (dev, #930). Both surfaces have art
# behind that text -- this ring's own sprite on the card, the TextureRect below it on the panel -- so
# the ground's own colour goes down first. A SCRIM rather than a modulate, because darkening the
# picture would be right on slate and wrong on parchment's cream paper, and because on the panel the
# portrait is not ours to touch.
func _draw_hover_readout(model: Array[Row]) -> void:
	var row: Row = null
	for candidate: Row in model:
		if candidate.element == hovered:
			row = candidate
	if row == null:
		return
	var font := get_theme_default_font()
	var font_size := 11
	# HELD OVER ASKED-FOR while a recipe is up -- the chip idiom the rune card already uses on its own
	# rows, so "Fire 0/2" and "Fire 3/2" read as short and over without a second vocabulary.
	var text: String = "%s %d/%d" % [Elemental.display_name(row.element), row.depth, row.wanted] \
		if row.wanted > 0 else "%s %d" % [Elemental.display_name(row.element), row.depth]
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


# An element the shown recipe does not ask for. SATURATION, never alpha -- an alpha knock-back lands
# between DIM_ALPHA and full and reads as a third empty state rather than as a quieter colour, which
# is the mistake this constant exists to have already made once.
#
# STATIC AND PUBLIC for the reason element_at is: which CHANNEL this moves is the thing worth pinning,
# and a case asking the painter would be pinning the painter.
static func knocked_back(ink: Color) -> Color:
	var quiet := ink
	quiet.s *= OFF_RECIPE_SATURATION
	return quiet
