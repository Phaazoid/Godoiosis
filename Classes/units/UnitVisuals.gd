# A Unit's own sprite effects: the flash/shake/lunge tweens, the hover and aim-pulse
# highlights, and the projected-stand-in hide. It owns writes to $MapSprite's
# position/modulate/scale/z_index and restores them from the base_* snapshot taken at
# _ready. It is deliberately NOT the whole unit's visual state — the downed art is a
# separate node owned by Unit itself, which is why `projected` below is declared rather
# than inferred from sprite.visible.
extends Node
class_name UnitVisuals

@export var sprite: Sprite2D

# TRUE while a planning ghost stands in for this unit. Declared rather than read back off
# sprite.visible, because Unit._show_downed_sprite writes that same flag for a completely
# different reason (swapping to the downed art). One flag, two questions -- which is
# exactly how the 3D mirror ended up hiding downed units: it copied the flag and got
# "projected" as the answer. Law #4: give the second question its own storage.
var projected := false

var visual_tween: Tween
const HIGHLIGHT_MODULATE := Color(1.4, 1.4, 1.0)   # warm yellow-white; tune to taste
const TARGET_PULSE_MODULATE := Color(1.6, 1.6, 1.6)   # peak of the aim-target pulse
# ...and the peak of the PIN flash (#1066, dev: "units that are toggled need to be indicated in some
# way. I think they should flash, too.").
#
# WHITE, AND IT LINGERS THERE (#1069). #1066 made this DELIBERATELY SHALLOWER than the aim's, on the
# reasoning that a pin is a bookmark you set yourself and should breathe rather than strobe. The dev
# played it: "the flashes are very hard to see. Instead of going dark, the flashes should be going
# white, and linger on the white part of the flash a bit longer, to draw attention."
#
# So the two cues stop differing by DEPTH and differ by CADENCE instead -- the aim breathes
# continuously, this snaps to white and sits there -- which is the distinction visual-clarity.md
# principle 2 actually asks for, and it leaves the pin free to be the brighter of the two. The
# PRECEDENCE is unchanged and is stated at _sync_pin_flash: an aim pulse still outranks this.
static var PIN_PULSE_MODULATE := Color(2.2, 2.2, 2.2)
# How long it sits at that peak, in seconds. The ramp either side is Pulse.PERIOD, so this is the
# share of the cycle the cue actually occupies -- at 0.45 against a 0.5 ramp it is white for about a
# third of the time rather than for one frame.
static var PIN_PULSE_HOLD := 0.45

var pulse_tween: Tween
# TRUE while this unit's ranges are PINNED up. Held as a flag rather than read back off pin_tween
# because the pin OUTLIVES its own pulse: an aim pulse outranks it and takes the sprite, and the
# flash has to come back when the aim moves on.
var pinned := false
var pin_tween: Tween


var base_position: Vector2
var base_modulate: Color
var base_scale: Vector2
var base_z_index: int

func _ready():
	if sprite == null:
		push_error("Unit Visuals Missing Sprite")
		return
		
	base_position = sprite.position
	base_modulate = sprite.modulate
	base_scale = sprite.scale
	# Deliberately the CONST, not sprite.z_index: child _ready runs before the parent's, and
	# Unit._ready is what assigns BASE_SPRITE_INDEX to the sprite. Reading it here would
	# capture the scene's pre-assignment value.
	base_z_index = Unit.BASE_SPRITE_INDEX

# Looping, unlike play_invalid_flash: it runs as long as an aim covers this unit, so every other
# writer of sprite.modulate has to yield while it lives.
func start_pulse() -> void:
	if sprite == null or pulse_tween != null:
		return
	pulse_tween = Pulse.start(self, sprite, &"modulate", base_modulate, TARGET_PULSE_MODULATE)
	_sync_pin_flash()   # a pin flash underneath yields -- see there

func stop_pulse() -> void:
	if pulse_tween == null:
		return
	Pulse.stop(pulse_tween, sprite, &"modulate", base_modulate)
	pulse_tween = null
	_sync_pin_flash()   # ...and comes back

# The pin flash (#1066): this unit's ranges are held up by a shift+click rather than by the pointer,
# and nothing on the board said so. Idempotent and called on every redraw rather than only on the
# change, so a flash killed by reset_visuals is rebuilt on the next pass instead of staying dark.
func set_pinned(value: bool) -> void:
	pinned = value
	_sync_pin_flash()

# THE PRECEDENCE, stated once and in one place: an aim pulse OUTRANKS a pin flash. Both write
# sprite.modulate and a live pulse owns that channel (#442), so exactly one may run -- and "this
# unit is about to be hit" is news, where "you pinned it" is a bookmark you set yourself.
func _sync_pin_flash() -> void:
	var want: bool = pinned and sprite != null and pulse_tween == null
	if want == (pin_tween != null):
		return
	if want:
		pin_tween = Pulse.start(self, sprite, &"modulate", base_modulate, PIN_PULSE_MODULATE,
				Pulse.PERIOD, PIN_PULSE_HOLD)
	else:
		Pulse.stop(pin_tween, sprite, &"modulate", base_modulate)
		pin_tween = null

# Rebuild a STANDING pin flash so a turned knob reaches it (#1069). Its own door rather than a
# clause in _sync_pin_flash, which is deliberately idempotent -- it compares "should there be one"
# against "is there one" and does nothing when they agree, which is exactly the case here.
func restyle_pin_flash() -> void:
	if pin_tween == null:
		return
	Pulse.stop(pin_tween, sprite, &"modulate", base_modulate)
	pin_tween = null
	_sync_pin_flash()


func reset_visuals():
	if sprite == null:
		return

	stop_pulse()
	# The pin flash goes too, and `pinned` deliberately does NOT: this is a reset of the CHANNEL,
	# and the one-shot alarm that follows it must own modulate outright. The next redraw's
	# set_pinned rebuilds the flash.
	if pin_tween != null:
		Pulse.stop(pin_tween, sprite, &"modulate", base_modulate)
		pin_tween = null
	if visual_tween:
		visual_tween.kill()

	sprite.position = base_position
	sprite.modulate = base_modulate
	sprite.scale = base_scale
	
func play_invalid_flash():
	if sprite == null:
		return
		
	reset_visuals()
	
	visual_tween = create_tween()
	visual_tween.set_parallel(true)
	
	#Color Flash
	visual_tween.tween_property(sprite, "modulate", Color(1, .25, .25), .08).set_delay(.06)
	visual_tween.tween_property(sprite, "modulate", Color.WHITE, .06).set_delay(.14)
	visual_tween.tween_property(sprite, "modulate", base_modulate, .12).set_delay(.22)
	
	#Shake
	visual_tween.tween_property(sprite, "position", base_position + Vector2(-3, 0), 0.04)
	visual_tween.tween_property(sprite, "position", base_position + Vector2(3, 0), 0.04).set_delay(0.04)
	visual_tween.tween_property(sprite, "position", base_position + Vector2(-2, 0), 0.04).set_delay(0.08)
	visual_tween.tween_property(sprite, "position", base_position + Vector2(2, 0),0.04).set_delay(0.12)
	visual_tween.tween_property(sprite, "position", base_position,0.04).set_delay(0.16)
	
func set_hovered(value: bool):
	if sprite == null:
		return
		
	if value:
		sprite.z_index = base_z_index + 5
	else:
		sprite.z_index = base_z_index

func set_highlighted(value: bool) -> void:
	if sprite == null:
		return
	# A live pulse owns modulate; hovering a pulsing unit must not stomp it. The pin flash counts,
	# for the same reason and by the same rule -- and a pinned enemy is hovered constantly.
	if pulse_tween == null and pin_tween == null:
		sprite.modulate = HIGHLIGHT_MODULATE if value else base_modulate
	set_hovered(value)

func set_projected(value: bool):
	if sprite == null:
		return
	projected = value
	if value:
		sprite.hide()
	else:
		sprite.show()
		
# How far an effect has displaced the art from where it rests, in the Unit node's own pixels.
# The 3D mirror's one read of it (#321): everything else this class writes is either already
# mirrored (modulate) or has no 3D meaning, so this is the whole of the offset channel.
func animation_offset() -> Vector2:
	if sprite == null:
		return Vector2.ZERO
	return sprite.position - base_position

func play_attack_lunge(direction: Vector2):
	if sprite == null:
		return
		
	if visual_tween:
		visual_tween.kill()
	
	sprite.position = base_position
	var lunge_distance := GridUtils.TILE_SIZE / 2
	var lunge_pos = base_position + direction.normalized() * lunge_distance
	visual_tween = create_tween()
	
	visual_tween.tween_property(sprite, "position", lunge_pos, 0.08)
	visual_tween.tween_property(sprite, "position", base_position, 0.10)
	
	await visual_tween.finished
