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
# Statics rather than consts since #1251: until then the 3D view clamped every tint at 1.0, so these
# brightened only the flat view, and they reach the shipped one at last -- tune them on the Game tab.
# Warm yellow-white: a queue row's units.
static var HIGHLIGHT_MODULATE := Color(1.4, 1.4, 1.0)
# The peak of the aim-target pulse.
static var TARGET_PULSE_MODULATE := Color(1.6, 1.6, 1.6)
# The HOVER flash (#1251, dev: "a white flash, but a bit steadier, and more white/bright"): the unit
# under the pointer, whatever it is, so the player can see whose marks just lifted. Ramp up, touch
# white, ramp down, then REST at normal (#1253, dev: "inverse the timing on how long it is glowing vs
# normal") -- the hold sat at white and left the unit bright most of the time.
static var HOVER_FLASH_MODULATE := Color(2.4, 2.4, 2.4)
static var HOVER_FLASH_RAMP := 0.4
static var HOVER_FLASH_HOLD := 0.0
static var HOVER_FLASH_REST := 0.4
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
# PRECEDENCE is unchanged and is stated at sync_pin_flash: an aim pulse still outranks this.
static var PIN_PULSE_MODULATE := Color(2.2, 2.2, 2.2)
# How long it sits at that peak, in seconds. The ramp either side is Pulse.PERIOD, so this is the
# share of the cycle the cue actually occupies rather than one frame at the top of a ramp.
static var PIN_PULSE_HOLD := 0.2
# How white the one a death's PULSE ran to flashes as it arrives (#1104), and how long the flash takes.
static var LOSS_FLASH_MODULATE := Color(2.0, 2.0, 2.0)
static var LOSS_FLASH_SECONDS := 0.3
# Every unit whose pin flash is RUNNING right now (#1074) -- the set a new flash looks in for a beat to
# join, so every pinned enemy flashes on one timer. Membership is maintained at the two doors a pin
# tween opens and closes through, sync_pin_flash and drop_pin_flash.
const PIN_FLASH_GROUP := &"pin_flashing"

var pulse_tween: Tween
# TRUE while this unit's ranges are PINNED up. Held as a flag rather than read back off pin_tween
# because the pin OUTLIVES its own pulse: an aim pulse outranks it and takes the sprite, and the
# flash has to come back when the aim moves on.
var pinned := false
var pin_tween: Tween
# TRUE while this unit is the one under the pointer, held as a flag for the pin's reason: the flash
# yields to stronger cues and has to come back after them.
var hover_flashing := false
var hover_tween: Tween


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
	sync_flashes()   # a flash underneath yields -- see there

func stop_pulse() -> void:
	if pulse_tween == null:
		return
	Pulse.stop(pulse_tween, sprite, &"modulate", base_modulate)
	pulse_tween = null
	sync_flashes()   # ...and comes back

# The pin flash (#1066): this unit's ranges are held up by a shift+click rather than by the pointer,
# and nothing on the board said so. Idempotent and called on every redraw rather than only on the
# change, so a flash killed by reset_visuals is rebuilt on the next pass instead of staying dark.
func set_pinned(value: bool) -> void:
	pinned = value
	sync_flashes()

# The hover flash (#1251), idempotent: HoverPresenter asks every frame, which is what brings it back
# after anything that outranked it lets go.
func set_hover_flash(value: bool) -> void:
	hover_flashing = value
	sync_flashes()

# THE PRECEDENCE, stated once and in one place, strongest first: a one-shot alarm (the refusal flash,
# which owns the sprite outright), the aim pulse, the hover flash, the pin flash, and last the steady
# queue-row highlight (set_highlighted). Each writes sprite.modulate and a live pulse owns that
# channel (#442), so exactly one runs. "This unit is about to be hit" is news; "the pointer is on this
# unit" is the thing the player is doing right now; "you pinned it" is a bookmark they set earlier.
#
# A pin flash that starts JOINS any already running (#1074) -- a fresh pin, and equally one coming
# back when something above lets go of it, which would otherwise restart on its own beat every time.
func sync_flashes() -> void:
	var free: bool = sprite != null and pulse_tween == null and not _alarm_running()
	var want_hover := hover_flashing and free
	var want_pin := pinned and free and not want_hover
	if not want_hover:
		drop_hover_flash()
	if not want_pin:
		drop_pin_flash()
	if want_hover and hover_tween == null:
		hover_tween = Pulse.start(self, sprite, &"modulate", base_modulate, HOVER_FLASH_MODULATE,
				HOVER_FLASH_RAMP, HOVER_FLASH_HOLD, HOVER_FLASH_REST)
	if want_pin and pin_tween == null:
		pin_tween = Pulse.start(self, sprite, &"modulate", base_modulate, PIN_PULSE_MODULATE,
				Pulse.PERIOD, PIN_PULSE_HOLD, 0.0, _running_pin_flash())
		add_to_group(PIN_FLASH_GROUP)

func _alarm_running() -> bool:
	return visual_tween != null and visual_tween.is_running()

# Stop the hover flash without forgetting it is wanted, the pin's shape.
func drop_hover_flash() -> void:
	if hover_tween == null:
		return
	Pulse.stop(hover_tween, sprite, &"modulate", base_modulate)
	hover_tween = null

# Rebuild a running hover flash so a turned knob reaches it, restyle_pin_flash's reason.
func restyle_hover_flash() -> void:
	if hover_tween == null:
		return
	drop_hover_flash()
	sync_flashes()

# Stop a standing pin flash WITHOUT forgetting the pin -- `pinned` survives, so the next sync brings
# it back. The one door a pin tween closes through, which is what keeps the group honest.
# (sync_flashes is the one that OPENS it.)
func drop_pin_flash() -> void:
	if pin_tween == null:
		return
	Pulse.stop(pin_tween, sprite, &"modulate", base_modulate)
	pin_tween = null
	if is_in_group(PIN_FLASH_GROUP):
		remove_from_group(PIN_FLASH_GROUP)

# Rebuild a STANDING pin flash so a turned knob reaches it (#1069) -- a running Tween holds the
# endpoints it was started with. sync_flashes alone would do nothing here: it is idempotent, and
# "should there be one" and "is there one" already agree.
func restyle_pin_flash() -> void:
	if pin_tween == null:
		return
	drop_pin_flash()
	sync_flashes()

# Another unit's running pin flash to beat in step with, or null when this is the first.
func _running_pin_flash() -> Tween:
	if not is_inside_tree():
		return null
	for node: Node in get_tree().get_nodes_in_group(PIN_FLASH_GROUP):
		var other := node as UnitVisuals
		if other != null and other != self and other.pin_tween != null and other.pin_tween.is_valid():
			return other.pin_tween
	return null


func reset_visuals():
	if sprite == null:
		return

	stop_pulse()
	# The pin flash goes too, and `pinned` deliberately does NOT: this is a reset of the CHANNEL,
	# and the one-shot alarm that follows it must own modulate outright. The next redraw's
	# set_pinned rebuilds the flash. The hover flash likewise, rebuilt by the next frame's ask.
	drop_pin_flash()
	drop_hover_flash()
	if visual_tween:
		visual_tween.kill()

	sprite.position = base_position
	sprite.modulate = base_modulate
	sprite.scale = base_scale
	
# A one-shot flash for the one a death's PULSE ran to (#1104). It YIELDS where play_invalid_flash
# seizes: to an aim pulse (news about this unit), to a pin or hover flash (already white), to any one-shot
# already running -- that tween also drives the lunge and the shake, and killing it mid-lunge would
# leave the sprite where the lunge had it. The lowest tier on sprite.modulate.
func play_loss_flash() -> void:
	if sprite == null or pulse_tween != null or pin_tween != null or hover_tween != null:
		return
	if _alarm_running():
		return
	visual_tween = create_tween()
	visual_tween.tween_property(sprite, "modulate", LOSS_FLASH_MODULATE, LOSS_FLASH_SECONDS * 0.3)
	visual_tween.tween_property(sprite, "modulate", base_modulate, LOSS_FLASH_SECONDS * 0.7)

func play_invalid_flash():
	if sprite == null:
		return
		
	reset_visuals()
	
	visual_tween = create_tween()
	visual_tween.set_parallel(true)
	tween_invalid_flash(visual_tween, sprite, base_modulate, base_position)

# What the refusal flash IS -- a red flash and a small shake, back to the sprite's rest -- as steps on
# a parallel tween, so the planning ghost standing in for a unit plays the same one (#1150).
static func tween_invalid_flash(tween: Tween, target: CanvasItem, rest_modulate: Color, rest_position: Vector2) -> void:
	#Color Flash
	tween.tween_property(target, "modulate", Color(1, .25, .25), .08).set_delay(.06)
	tween.tween_property(target, "modulate", Color.WHITE, .06).set_delay(.14)
	tween.tween_property(target, "modulate", rest_modulate, .12).set_delay(.22)
	
	#Shake
	tween.tween_property(target, "position", rest_position + Vector2(-3, 0), 0.04)
	tween.tween_property(target, "position", rest_position + Vector2(3, 0), 0.04).set_delay(0.04)
	tween.tween_property(target, "position", rest_position + Vector2(-2, 0), 0.04).set_delay(0.08)
	tween.tween_property(target, "position", rest_position + Vector2(2, 0),0.04).set_delay(0.12)
	tween.tween_property(target, "position", rest_position,0.04).set_delay(0.16)
	
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
	# for the same reason and by the same rule -- and a pinned enemy is hovered constantly. So does the
	# hover flash (#1251).
	if pulse_tween == null and pin_tween == null and hover_tween == null:
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

# The lunge's PEAK, where its blow lands (#480).
signal lunge_peaked

# Returns at the PEAK, not the end: the caller lands the blow there while the return leg keeps playing.
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
	visual_tween.tween_callback(lunge_peaked.emit)
	visual_tween.tween_property(sprite, "position", base_position, 0.10)

	await lunge_peaked
