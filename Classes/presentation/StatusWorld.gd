class_name StatusWorld
extends Node3D

# What a worn element state throws into the WORLD around a unit (#358 slice 2): a Wet unit's drips
# and their splashes, a Chilled unit's cold mist and frost breath. Slice 1 drew the state ON the
# sprite; this is everything that leaves it. A child of UnitMirror, which reports every unit wearing
# a state once a frame (`wear`) and then lets this node act (`advance`) -- HealthBlockDebris' shape.
#
# CONTINUOUS EFFECTS ON #656's RULES. One resident emitter per kind (StatusParticles), and the
# schedule is CPU-side: each wearer carries an accumulator (`owed += rate x level x delta`, one
# emission per whole unit) on the mirror's own scaled delta, so a hitstop stops new emissions with
# the world and a fading state thins out rather than cutting off. Which overhang, which edge, which
# jitter comes off a hash of the unit and a counter -- slice 1's per-unit seed policy -- so the
# scatter is derived, never rolled.
#
# WHERE ON THE ART is StatusArt's answer and UnitSprite3D.texel_to_world's arithmetic, never a
# second scan: drips fall from exactly the overhangs icicles hang from.
#
# A DRIP LANDS EXACTLY, with no collision node: it falls at the constant speed that ends its fixed
# lifetime on the surface below it, and its splash is queued for that instant at that point. The
# trade is that a drip does not accelerate; at a third of a second it is hard to see, and it buys a
# landing a headless case can state.
#
# Per-unit state is RETIRED when a unit stops being reported, so it needs no hook in the mirror's
# removal loop. A splash already queued still lands after its unit has gone -- the drip is in the air.

var _drip: StatusParticles
var _splash: StatusParticles
var _mist: StatusParticles
var _breath: StatusParticles

var _wearers: Dictionary[int, Wearer] = {}
# Splashes owed by drips still falling: {"due": clock time, "at": landing point, "key": seed}.
var _splashes: Array[Dictionary] = []


class Wearer extends RefCounted:
	var sprite: UnitSprite3D
	var cell := Vector2i.ZERO
	var level := Vector3.ZERO
	var seed := 0.0
	var reported := false
	var drips_owed := 0.0
	var drips := 0
	var mist_owed := 0.0
	var mists := 0
	var next_breath := -1.0   # the status clock's time of the next puff; -1 until one is scheduled
	var breaths := 0


func _ready() -> void:
	_drip = _emitter(StatusParticles.Kind.DRIP)
	_splash = _emitter(StatusParticles.Kind.SPLASH)
	_mist = _emitter(StatusParticles.Kind.MIST)
	_breath = _emitter(StatusParticles.Kind.BREATH)


func _emitter(of: StatusParticles.Kind) -> StatusParticles:
	var emitter := StatusParticles.make(of)
	add_child(emitter)
	return emitter


func cover(board: AABB) -> void:
	for emitter in emitters():
		emitter.cover(board)


func emitters() -> Array[StatusParticles]:
	var all: Array[StatusParticles] = [_drip, _splash, _mist, _breath]
	return all


func emitter(of: StatusParticles.Kind) -> StatusParticles:
	return emitters()[of]


# One unit wearing a state this frame. `sprite` is whichever sprite STANDS for it -- the real one,
# or the planning ghost that replaced it -- and `cell` the board cell under that sprite, whose
# surface its drips land on.
func wear(id: int, sprite: UnitSprite3D, cell: Vector2i, level: Vector3, seed: float) -> void:
	var wearer: Wearer = _wearers.get(id)
	if wearer == null:
		wearer = Wearer.new()
		_wearers[id] = wearer
	wearer.sprite = sprite
	wearer.cell = cell
	wearer.level = level
	wearer.seed = seed
	wearer.reported = true


func wearer_count() -> int:
	return _wearers.size()


func pending_splashes() -> int:
	return _splashes.size()


func advance(delta: float, clock: float, heights: BoardHeights) -> void:
	for emitter in emitters():
		emitter.apply()
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var right := Vector3.RIGHT
	var toward := Vector3.BACK
	if camera != null:
		toward = camera.global_transform.basis.z
		right = Vector3.UP.cross(toward).normalized()
	for id: int in _wearers.keys():
		var wearer: Wearer = _wearers[id]
		if not wearer.reported or not is_instance_valid(wearer.sprite):
			_wearers.erase(id)
			continue
		wearer.reported = false
		if wearer.sprite.texture == null:
			continue
		var map := StatusArt.map_for(wearer.sprite.texture)
		if map == null:
			continue
		var frame := StatusArt.frame_of(wearer.sprite.texture)
		_drip_from(id, wearer, map, frame, delta, clock, heights, right, toward)
		_mist_from(id, wearer, map, frame, delta, heights, right, toward)
		_breathe(id, wearer, map, frame, clock, right, toward)
	_land_splashes(clock)


func _drip_from(id: int, wearer: Wearer, map: StatusArt.Map, frame: Rect2, delta: float,
		clock: float, heights: BoardHeights, right: Vector3, toward: Vector3) -> void:
	wearer.drips_owed += StatusLook.wet_drip_rate * wearer.level.x * delta
	if wearer.drips_owed < 1.0:
		return
	var hangs := in_frame(map.overhangs, frame)
	var fall := maxf(StatusLook.wet_drip_fall_time, 0.05)
	var texel := wearer.sprite.pixel_size
	while wearer.drips_owed >= 1.0:
		wearer.drips_owed -= 1.0
		wearer.drips += 1
		if hangs.is_empty():
			continue   # art with nothing overhanging drips only in its streaks
		var hang := hangs[pick(hangs.size(), id, wearer.drips)]
		# Off the overhang's BOTTOM edge, a texel toward the camera so it draws in front of the body
		# it runs past on the way down.
		var start := wearer.sprite.texel_to_world(Vector2(hang.x + 0.5, hang.y + 1.0), right) \
				+ toward * texel
		var ground := ground_under(wearer.cell, start, heights)
		_drip.throw(start, drip_velocity(start, ground, fall))
		_splashes.append({"due": clock + fall, "at": Vector3(start.x, ground, start.z),
				"key": hash([id, wearer.drips, 1])})


func _land_splashes(clock: float) -> void:
	var texel := 1.0 / UnitSprite3D.texels_per_unit
	var still: Array[Dictionary] = []
	for splash in _splashes:
		if clock < float(splash["due"]):
			still.append(splash)
			continue
		if StatusLook.wet_splash_count <= 0:
			continue   # ParticleFan throws at least one; zero here means no splash at all
		# Half a texel of lift, so a droplet born ON the ground does not share its plane (#656).
		for drop in ParticleFan.scatter(splash["at"], int(splash["key"]), StatusLook.wet_splash_count,
				texel, StatusLook.wet_splash_speed, StatusLook.wet_splash_rise, texel * 0.5):
			_splash.throw(drop["position"], drop["velocity"])
	_splashes = still


func _mist_from(id: int, wearer: Wearer, map: StatusArt.Map, frame: Rect2, delta: float,
		heights: BoardHeights, right: Vector3, toward: Vector3) -> void:
	wearer.mist_owed += StatusLook.chill_mist_rate * wearer.level.y * delta
	if wearer.mist_owed < 1.0:
		return
	var edges := in_frame(map.edges, frame)
	var life := maxf(StatusLook.chill_mist_life, 0.05)
	var texel := wearer.sprite.pixel_size
	var axis := wearer.sprite.global_position
	while wearer.mist_owed >= 1.0:
		wearer.mist_owed -= 1.0
		wearer.mists += 1
		if edges.is_empty():
			continue
		var edge := edges[pick(edges.size(), id, wearer.mists)]
		var start := wearer.sprite.texel_to_world(Vector2(edge.x + 0.5, edge.y + 0.5), right)
		var out := right * signf((start - axis).dot(right))
		var wander := StatusLook.chill_mist_drift * (0.5 + 0.5 * unit_hash(id, wearer.mists, 2))
		var depth := StatusLook.chill_mist_drift * (unit_hash(id, wearer.mists, 3) * 2.0 - 1.0)
		var end := start + out * wander + toward * depth
		end.y = ground_under(wearer.cell, end, heights) + texel * 0.5
		_mist.throw(start, travel(start, end, life))


func _breathe(id: int, wearer: Wearer, map: StatusArt.Map, frame: Rect2, clock: float,
		right: Vector3, toward: Vector3) -> void:
	if wearer.level.y <= 0.0:
		wearer.next_breath = -1.0
		return
	var period := maxf(StatusLook.chill_breath_period, 0.05)
	if wearer.next_breath < 0.0:
		# Phased by the unit's seed, so a frozen squad does not breathe in unison.
		wearer.next_breath = clock + period * wearer.seed
	if clock < wearer.next_breath:
		return
	while wearer.next_breath <= clock:
		wearer.next_breath += period
	wearer.breaths += 1
	var mouth := wearer.sprite.texel_to_world(breath_anchor(map.ink, frame), right) \
			+ toward * wearer.sprite.pixel_size
	var ahead := right * (1.0 if faces_right(wearer.sprite.flip_h) else -1.0)
	var speed := StatusLook.chill_breath_speed
	var puffs := ceili(float(StatusLook.chill_breath_count) * wearer.level.y)
	for i in puffs:
		var n := wearer.breaths * 16 + i
		var velocity := ahead * speed * (0.8 + 0.4 * unit_hash(id, n, 4)) \
				+ Vector3.UP * speed * (0.15 + 0.2 * unit_hash(id, n, 5)) \
				+ toward * speed * 0.2 * (unit_hash(id, n, 6) - 0.5)
		_breath.throw(mouth, velocity)


# --- the rules, pure -----------------------------------------------------------------------------


# The constant fall that puts a drip on the ground exactly as its life ends.
static func drip_velocity(start: Vector3, ground_y: float, fall_time: float) -> Vector3:
	return Vector3(0.0, -maxf(start.y - ground_y, 0.0) / maxf(fall_time, 0.05), 0.0)


# The constant velocity that carries a particle from `from` to `to` over its life.
static func travel(from: Vector3, to: Vector3, life: float) -> Vector3:
	return (to - from) / maxf(life, 0.05)


# The surface under a world point, on the board and wherever a tear-out has carried that cell.
static func ground_under(cell: Vector2i, at: Vector3, heights: BoardHeights) -> float:
	var lifted := BoardSpace.staged_offset(cell)
	return BoardSpace.surface_height_at(cell, at.x - lifted.x, at.z - lifted.z, heights) + lifted.y


# The mouth: the one constant anchor every sprite shares for now (dev, #358 grill), as shares of the
# ink box in the UNFLIPPED art. An atlas frame falls back to its own box, since the scan's ink is
# the whole sheet's.
static func breath_anchor(ink: Rect2i, frame: Rect2) -> Vector2:
	var box := Rect2(ink)
	if not frame.encloses(box):
		box = frame
	return box.position + Vector2(StatusLook.chill_breath_x * box.size.x,
			StatusLook.chill_breath_y * box.size.y)


# Which way the unit faces on screen. flip_h mirrors the art, and the art's own way is a fact about
# the pack (UnitSprite3D.ART_FACES_SCREEN_RIGHT).
static func faces_right(flip_h: bool) -> bool:
	return flip_h != UnitSprite3D.ART_FACES_SCREEN_RIGHT


static func in_frame(texels: Array[Vector2i], frame: Rect2) -> Array[Vector2i]:
	var inside: Array[Vector2i] = []
	for texel in texels:
		if frame.has_point(Vector2(texel)):
			inside.append(texel)
	return inside


static func pick(count: int, id: int, n: int) -> int:
	return absi(hash([id, n])) % maxi(count, 1)


# 0..1, derived from the unit, a counter and what it is for.
static func unit_hash(id: int, n: int, salt: int) -> float:
	return float(absi(hash([id, n, salt])) % 1000) / 1000.0
