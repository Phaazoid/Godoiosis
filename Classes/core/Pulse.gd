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

static func start(host: Node, target: Object, property: StringName, base: Variant, peak: Variant,
		period := PERIOD) -> Tween:
	var tween := host.create_tween().set_loops()
	tween.tween_property(target, NodePath(property), peak, period)
	tween.tween_property(target, NodePath(property), base, period)
	return tween

static func stop(tween: Tween, target: Object, property: StringName, base: Variant) -> void:
	if tween != null and tween.is_valid():
		tween.kill()
	if target != null and is_instance_valid(target):
		target.set(property, base)
