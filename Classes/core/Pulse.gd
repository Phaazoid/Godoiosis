extends Object
class_name Pulse

# One looping pulse, shared by every "look at this" signal: the Execute button, the units/tiles an
# aim is about to affect, and the 3D readout over a unit the plan is about to fell (#313).
# SquadActionQueueControl held the only copy until 2026-08-01.
# Distinct from UnitVisuals.play_invalid_flash, which is a ONE-SHOT alarm.
#
# The PROPERTY is a parameter rather than a hardcoded `modulate` (#313): a 3D readout has no
# modulate to write — its colour lives on a material — and the cadence is the one thing every
# "look at this" cue must agree on. Naming the property keeps that agreement at one call.
#
# The caller owns the returned Tween and MUST stop it. A pulse left running keeps writing its
# property underneath everything else that writes it.

const PERIOD := 0.5

# `hold` parks the tween AT THE PEAK for that long before it comes back (#1069). Default zero, so
# every caller that does not ask for one is bit-identical to what it was.
#
# It exists because a symmetric ramp cannot say "flash". The dev, on the pin flash: "the flashes are
# very hard to see. Instead of going dark, the flashes should be going white, and linger on the
# white part of the flash a bit longer, to draw attention." A base -> peak -> base ramp touches its
# peak for one frame and spends half its cycle returning to normal, so the eye adapts to the bright
# state and reads the DIPS as the event -- which is exactly "going dark". A hold inverts that: the
# peak is where the cue lives and the ramps are how it gets there.
#
# That also makes CADENCE a way for two cues on one property to differ, which is visual-clarity.md
# principle 2's rule about not letting two motifs collide -- see UnitVisuals, where the aim pulse
# breathes and the pin flash sits.
static func start(host: Node, target: Object, property: StringName, base: Variant, peak: Variant,
		period := PERIOD, hold := 0.0) -> Tween:
	var tween := host.create_tween().set_loops()
	tween.tween_property(target, NodePath(property), peak, period)
	if hold > 0.0:
		tween.tween_interval(hold)
	tween.tween_property(target, NodePath(property), base, period)
	return tween

static func stop(tween: Tween, target: Object, property: StringName, base: Variant) -> void:
	if tween != null and tween.is_valid():
		tween.kill()
	if target != null and is_instance_valid(target):
		target.set(property, base)
