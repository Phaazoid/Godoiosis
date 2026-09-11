extends Node
class_name AudioDirector

# THE ONE PLACE A SOUND IS PLAYED (#136). A game collaborator with a back-ref, built last in
# game._build_collaborators -- the DevController/MissionLog pattern -- and it OWNS NO RULE: what a
# cue means is decided by whatever already decided it (an AttackData's authored fields, a
# PlayerSettings row), and this only plays the result.
#
# A COLLABORATOR, NOT A battle3d NODE. ArcLightning is the model for consuming volley_struck, but it
# is a node of the 3D host because a bolt is something the diorama draws. A sound is not view-
# specific, and hanging this off battle3d would leave a Main.tscn launch silent. Not an autoload
# either: this project has none by policy.
#
# PROCESS_MODE_ALWAYS, and it is correctness rather than convenience. ModalLock sets
# game.process_mode = DISABLED, which propagates down the subtree, and a DISABLED parent STOPS an
# AudioStreamPlayer's stream -- measured 2026-09-11, headless: player INHERIT under a DISABLED
# parent reads playing=false, the same player ALWAYS reads true. So a director on INHERIT would cut
# a hit sound off mid-blow the moment the pause menu opened. The pool inherits ALWAYS from here,
# which is why the players themselves declare nothing. Second reason: the settings page is behind
# that same lock, so a frozen director could not move the volume while it is being dragged.
#
# FLAT, NOT POSITIONAL (dev, 2026-09-11). AudioStreamPlayer, no listener and no attenuation -- the
# camera may fly anywhere and the sound is unaffected. Going positional later changes the play site,
# not this design.

# The FALLBACK voice -- what a blow sounds like when its attack authors nothing, which is most of
# them. An attack's own sound is `AttackData.sound` and beats this; the lethality rungs (a kill, a
# Crisis) are the next slice.
const IMPACT: AudioStream = preload("res://Audio/SFX/impact.mp3")

const BUS_NAME := "SFX"
const POOL_SIZE := 4

var game: Node

var _players: Array[AudioStreamPlayer] = []
# Monotonic per play, so a stolen voice is the oldest rather than an arbitrary one.
var _started: Array[int] = []
var _stamp := 0
var _bus := 0
# What the bus was last set to, so _process writes only on a change rather than every frame.
var _applied := -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_bus = AudioServer.get_bus_index(BUS_NAME)
	if _bus == -1:
		push_warning("AudioDirector: no '%s' bus -- falling back to Master." % BUS_NAME)
		_bus = 0

	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = AudioServer.get_bus_name(_bus)
		add_child(player)
		_players.append(player)
		_started.append(-1)

	var executor: OrderExecutor = game.order_executor
	executor.volley_struck.connect(_on_volley_struck)


func _process(_delta: float) -> void:
	var level := PlayerSettings.level_of(PlayerSettings.Setting.SFX_VOLUME)
	if is_equal_approx(level, _applied):
		return
	_applied = level
	# Mute rather than linear_to_db(0), which is -inf and reads as a broken slider anywhere it is
	# shown as a number.
	AudioServer.set_bus_mute(_bus, level <= 0.0)
	if level > 0.0:
		AudioServer.set_bus_volume_db(_bus, linear_to_db(level))


# ONE PER VOLLEY -- OrderExecutor emits once per blast however many it hits (#887), so the
# granularity is the project's own rather than a choice made here.
func _on_volley_struck(attack: AttackAction) -> void:
	var cue := cue_for(attack)
	if cue != null:
		play(cue)


# What this blow sounds like: the attack's OWN voice if it authors one, else the generic impact if
# it damages, else nothing.
#
# THE DAMAGE GATE NOW GOVERNS THE DEFAULT ALONE, and that is a deliberate narrowing (#136 slice 2).
# A generic punch is wrong on a heal; an AUTHORED heal chime is not, and there is no reason the data
# cannot say so. Nothing changes today -- no heal authors a sound -- so this widens what is
# expressible without moving any live behaviour.
static func cue_for(attack: AttackAction) -> AudioStream:
	var fired := attack.fired_attack
	if fired != null and fired.sound != null:
		return fired.sound
	return IMPACT if plays_impact(attack) else null


# Does this blow make the GENERIC impact sound? NULL-TOLERANT: fired_attack is null for the
# bare-fists fallback, and a bare fist damages, so null plays. A heal or a pure-utility attack does
# not -- volley_struck fires for those too, and a heal that punches is the bug this refuses.
static func plays_impact(attack: AttackAction) -> bool:
	var fired := attack.fired_attack
	if fired == null:
		return true
	return not fired.heals and not fired.deals_no_damage


func play(stream: AudioStream) -> void:
	var chosen := _free_player()
	if chosen == -1:
		chosen = _oldest_player()
	_stamp += 1
	_started[chosen] = _stamp
	var player := _players[chosen]
	player.stream = stream
	player.play()


func _free_player() -> int:
	for i in _players.size():
		if not _players[i].playing:
			return i
	return -1


func _oldest_player() -> int:
	var oldest := 0
	for i in _players.size():
		if _started[i] < _started[oldest]:
			oldest = i
	return oldest


# --- read seams, for tests and for anything that wants to know without reaching into the pool ---

func voices_playing() -> int:
	var n := 0
	for player in _players:
		if player.playing:
			n += 1
	return n


# WHICH streams are sounding, not just how many -- the seam a per-weapon case asserts identity
# through, so a test never reaches into the pool itself.
func streams_playing() -> Array[AudioStream]:
	var live: Array[AudioStream] = []
	for player in _players:
		if player.playing and player.stream != null:
			live.append(player.stream)
	return live


func pool_size() -> int:
	return _players.size()
