extends Object
class_name Pulse

# One looping modulate pulse, shared by every "look at this" signal: the Execute button, and the
# units/tiles an aim is about to affect. SquadActionQueueControl held the only copy until 2026-08-01.
# Distinct from UnitVisuals.play_invalid_flash, which is a ONE-SHOT alarm.
#
# The caller owns the returned Tween and MUST stop it. A pulse left running keeps writing modulate
# underneath everything else that writes modulate.

const PERIOD := 0.5

static func start(host: Node, target: CanvasItem, base: Color, peak: Color, period := PERIOD) -> Tween:
	var tween := host.create_tween().set_loops()
	tween.tween_property(target, "modulate", peak, period)
	tween.tween_property(target, "modulate", base, period)
	return tween

static func stop(tween: Tween, target: CanvasItem, base: Color) -> void:
	if tween != null and tween.is_valid():
		tween.kill()
	if target != null and is_instance_valid(target):
		target.modulate = base
