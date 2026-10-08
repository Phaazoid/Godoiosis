class_name StrikeMarks2D
extends Node2D

# What a QUEUED attack leaves on the board (#1247): the queue row's own attack icon on a small dark
# badge, standing between attacker and target, with a pointer aimed at the target and, at range, a
# dashed line attacker -> target. One mark per queue ROW of hits -- an aim's volley, a counter, a watch
# shot -- so the board and the panel cannot disagree about what is coming. A payload folds into the
# hit that dropped it: its own chord runs from the impact to the impact.
#
# The DERIVATION, the GEOMETRY and the BADGE ART live here and both views read them: OverlayManager
# holds the store, this node draws it flat, OverlayMirror lifts the same points into the diorama.
# Points are in ThreatLines2D's trace space (x, rule-height, y), through its `segment`, so a mark
# hangs at body height exactly where a reach mark does.
#
# Rulings (dev, 2026-10-07, off two mockup rounds on a real report frame): the icon is the ROW's own
# (a lethal hit wears its rung, a folded volley plain swords); the badge STANDS, camera-facing; your
# side is the attack-reach red and the enemy's the reach marks' pink; counters draw in the same style;
# each mark keeps to its RIGHT-hand lane, so a blow and the counter answering it sit side by side;
# hovering a unit lifts every mark it is part of, both ends, over everything; and the footprint draws
# only when it covers more than the one tile the badge already points at.

const LINE_WIDTH := 1.5
# The badge's art: a 16px icon on a disc this many texels across, ringed RING_TEXELS deep.
const BADGE_TEXELS := 24
const RING_TEXELS := 2

# Each mark's sideways offset to the right of its travel, in cells.
static var STRIKE_LANE := 0.17
# The badge's width in world units (= cells). The diorama sizes its sprite from this; the flat view
# draws it at the same share of a tile.
static var STRIKE_BADGE_SIZE := 0.45
# How far the pointer runs past the badge's rim toward the target, in cells.
static var STRIKE_POINTER_LENGTH := 0.16
# The disc the icon sits on.
static var STRIKE_BADGE_GROUND := Color(0.094, 0.094, 0.118, 1.0)

# The store this node draws, handed in by OverlayManager, and each entry's focus_rank.
var entries: Array[Dictionary] = []
var focus_ranks: Array[int] = []

static var _badges: Dictionary = {}


# One entry per queue row of hits: {"from", "to", "chord", "members", "attacker", "targets", "icon",
# "tint", "colour", "footprint"}. `chord` is ThreatLines2D.segment's, before the lane.
static func from_plan(plan: ResolvedPlan, board: BoardContext) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if plan == null:
		return out
	var hits: Array[AttackAction] = []
	hits.append_array(plan.attacks)
	# Only the rows the panel shows: a counter or watch shot the pass resolved into nothing has none.
	for counter: CounterAttackAction in plan.counters:
		if counter.resolved == null or not counter.resolved.skipped:
			hits.append(counter)
	for shot: AttackAction in plan.watch_shots:
		if shot.resolved != null and not shot.resolved.skipped:
			hits.append(shot)
	var group: Array[AttackAction] = []
	for hit: AttackAction in hits:
		if hit.actor == null or not is_instance_valid(hit.actor):
			continue
		if hit.dropped_by != null:
			_fold_payload(out, hit)
			continue
		if not group.is_empty() and not AttackAction.same_volley(group[0], hit):
			out.append(_entry(group, board))
			group = []
		group.append(hit)
	if not group.is_empty():
		out.append(_entry(group, board))
	return out


static func _entry(group: Array[AttackAction], board: BoardContext) -> Dictionary:
	var lead := group[0]
	var targets: Array[Unit] = []
	var footprint: Array[Vector2i] = []
	for hit: AttackAction in group:
		if hit.target != null and is_instance_valid(hit.target) and not targets.has(hit.target):
			targets.append(hit.target)
		for cell in hit.footprint:
			if not footprint.has(cell):
				footprint.append(cell)
	var members: Array[AttackAction] = []
	members.assign(group)
	return {
		"from": lead.origin_cell, "to": lead.target_cell,
		"chord": ThreatLines2D.segment(lead.origin_cell, lead.target_cell, board),
		"members": members, "attacker": lead.actor, "targets": targets,
		"icon": AttackAction.group_icon(lead, group.size()), "tint": lead.get_ui_modulate(),
		"colour": colour_of(lead), "footprint": footprint,
	}


# A payload joins the mark of the hit that dropped it -- its members, its victims and its tiles.
static func _fold_payload(out: Array[Dictionary], hit: AttackAction) -> void:
	for entry in out:
		var members: Array = entry["members"]
		if not members.has(hit.dropped_by):
			continue
		members.append(hit)
		var targets: Array = entry["targets"]
		if hit.target != null and is_instance_valid(hit.target) and not targets.has(hit.target):
			targets.append(hit.target)
		var footprint: Array = entry["footprint"]
		for cell in hit.footprint:
			if not footprint.has(cell):
				footprint.append(cell)
		return


# Whose side, never who is in control: a heal wears the aim's heal green, the enemy the reach marks'
# pink, and your side the aim's own reach colour (the watch tint for a watch shot). Opaque, since the
# row's own modulate is what fades a mark.
static func colour_of(hit: AttackAction) -> Color:
	var attack := hit.fired_attack
	var colour: Color
	if attack != null and attack.heals:
		colour = OverlayManager.attack_reach_color(attack)
	elif SquadLines2D.is_hostile(hit.actor.get_faction()):
		colour = ThreatLines2D.MARK_LINE_COLOR
	else:
		colour = OverlayManager.attack_reach_color(attack, hit.is_watch_shot)
	return Color(colour.r, colour.g, colour.b, 1.0)


# How far a mark lifts for this hovered unit: 2 = it is the unit's own attack, 1 = it is aimed at
# the unit, 0 = neither. The unit's own marks come out on top of the ones aimed at it (#1251).
static func focus_rank(entry: Dictionary, unit: Unit) -> int:
	if unit == null or not is_instance_valid(unit):
		return 0
	if entry["attacker"] == unit:
		return 2
	return 1 if (entry["targets"] as Array).has(unit) else 0


# --- Geometry, in trace space ---------------------------------------------------------------------

# The chord moved STRIKE_LANE cells to the right of its own travel.
static func lane_chord(chord: PackedVector3Array) -> PackedVector3Array:
	if chord.size() < 2:
		return chord
	var flat := Vector3(chord[1].x - chord[0].x, 0.0, chord[1].z - chord[0].z)
	if flat.length_squared() <= 0.0:
		return chord
	var travel := flat.normalized()
	var shift := Vector3(-travel.z, 0.0, travel.x) * STRIKE_LANE
	return PackedVector3Array([chord[0] + shift, chord[1] + shift])


# Where the badge hangs: the middle of the laned chord.
static func badge_point(entry: Dictionary) -> Vector3:
	var lane := lane_chord(entry["chord"])
	if lane.size() < 2:
		return Vector3.ZERO
	return lane[0].lerp(lane[1], 0.5)


# The mark's line work: {"shaft": the dashed stroke, empty when the badge would cover it, "base" and
# "tip": the pointer cone}. Distances are WORLD units along the chord, so a sloped chord measures
# the same as a flat one: the pointer runs from the badge's rim, and at range the tip stops
# ThreatLines2D.MARK_INSET short of the target, as a reach mark's does.
static func line_work(entry: Dictionary) -> Dictionary:
	var lane := lane_chord(entry["chord"])
	if lane.size() < 2:
		return {}
	var a := lane[0]
	var b := lane[1]
	var run := _world_length(a, b)
	if run <= 0.0:
		return {}
	var rim := run * 0.5 + STRIKE_BADGE_SIZE * 0.5
	var tip := maxf(run - ThreatLines2D.MARK_INSET, rim + STRIKE_POINTER_LENGTH)
	var base := tip - STRIKE_POINTER_LENGTH
	var shaft := PackedVector3Array()
	if base - ThreatLines2D.MARK_INSET > STRIKE_BADGE_SIZE:
		shaft.append(a.lerp(b, ThreatLines2D.MARK_INSET / run))
		shaft.append(a.lerp(b, base / run))
	return {"shaft": shaft, "base": a.lerp(b, base / run), "tip": a.lerp(b, tip / run)}


static func _world_length(a: Vector3, b: Vector3) -> float:
	var d := b - a
	return Vector3(d.x, d.y * BoardSpace.ROW_HEIGHT, d.z).length()


# --- The badge's art ---------------------------------------------------------------------------------

# The icon on a dark disc ringed in `colour`, cached per icon and colour. The ring is baked rather
# than tinted, because a tint would colour the icon too.
static func badge_texture(icon: Texture2D, colour: Color) -> Texture2D:
	var key := "%d|%s|%s" % [0 if icon == null else icon.get_instance_id(), colour.to_html(),
			STRIKE_BADGE_GROUND.to_html()]
	if _badges.has(key):
		return _badges[key]
	var image := Image.create(BADGE_TEXELS, BADGE_TEXELS, false, Image.FORMAT_RGBA8)
	var centre := float(BADGE_TEXELS) * 0.5
	var ring := Color(colour.r, colour.g, colour.b, 1.0)
	for y in BADGE_TEXELS:
		for x in BADGE_TEXELS:
			var d := Vector2(float(x) + 0.5 - centre, float(y) + 0.5 - centre).length()
			if d <= centre - float(RING_TEXELS):
				image.set_pixel(x, y, STRIKE_BADGE_GROUND)
			elif d <= centre:
				image.set_pixel(x, y, ring)
	var art: Image = null
	if icon != null:
		art = icon.get_image()
	if art != null:
		art = art.duplicate() as Image
		if art.is_compressed():
			art.decompress()
		art.convert(Image.FORMAT_RGBA8)
		var at := Vector2i(floori(float(BADGE_TEXELS - art.get_width()) * 0.5),
				floori(float(BADGE_TEXELS - art.get_height()) * 0.5))
		image.blend_rect(art, Rect2i(Vector2i.ZERO, art.get_size()), at)
	var texture := ImageTexture.create_from_image(image)
	_badges[key] = texture
	return texture


# A turned badge knob: every badge is re-baked on its next read.
static func clear_badges() -> void:
	_badges.clear()


# --- The flat view -----------------------------------------------------------------------------------

func _draw() -> void:
	# By focus rank, so the hovered unit's marks draw over the rest and its own over those aimed at it.
	for rank: int in [0, 1, 2]:
		for i in entries.size():
			if (focus_ranks[i] if i < focus_ranks.size() else 0) == rank:
				_draw_entry(entries[i])


func _draw_entry(entry: Dictionary) -> void:
	var colour: Color = entry["colour"] * (entry["tint"] as Color)
	var work := line_work(entry)
	if work.is_empty():
		return
	var shaft: PackedVector3Array = work["shaft"]
	if shaft.size() == 2:
		var from := _flat(shaft[0])
		var to := _flat(shaft[1])
		var length := from.distance_to(to) / float(GridUtils.TILE_SIZE)
		var spans := SquadLines2D.dash_spans(length, 0.0)
		for span: Vector2 in spans:
			draw_line(from.lerp(to, span.x / length), from.lerp(to, span.y / length), colour, LINE_WIDTH)
	var base := _flat(work["base"])
	var tip := _flat(work["tip"])
	var across := (tip - base).orthogonal().normalized() * LINE_WIDTH * ThreatLines2D.CONE_WIDTH_SCALE * 0.5
	draw_colored_polygon(PackedVector2Array([base + across, tip, base - across]), colour)
	var size := Vector2.ONE * STRIKE_BADGE_SIZE * float(GridUtils.TILE_SIZE)
	var centre := _flat(badge_point(entry))
	draw_texture_rect(badge_texture(entry["icon"], entry["colour"]), Rect2(centre - size * 0.5, size),
			false, entry["tint"])


func _flat(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z) * float(GridUtils.TILE_SIZE)
