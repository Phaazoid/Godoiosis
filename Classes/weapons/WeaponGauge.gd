class_name WeaponGauge
extends RefCounted

# A weapon's live count as numbers a label can print (#1045): a STOCK it spends and refills (rounds,
# charge, a wound spring, a tank) or a TIMER running down (turns of rev left). THE structured answer
# to that state -- status_text() words its sentence from this, and the action ring prints label()
# beside an attack's name. A snapshot, never a live view: asked again after the state moves.

enum Kind { STOCK, TIMER }

var kind: Kind = Kind.STOCK
var current := 0
var maximum := 0


static func stock(p_current: int, p_maximum: int) -> WeaponGauge:
	var g := WeaponGauge.new()
	g.kind = Kind.STOCK
	g.current = p_current
	g.maximum = p_maximum
	return g


static func timer(turns_left: int, duration: int) -> WeaponGauge:
	var g := WeaponGauge.new()
	g.kind = Kind.TIMER
	g.current = turns_left
	g.maximum = duration
	return g


# A stock reads as a fraction and a timer as turns, so the two cannot be mistaken for one another
# (dev, 2026-09-28: the rev timer "should look meaningfully different than the ammo count").
func label() -> String:
	if kind == Kind.TIMER:
		return "%d turn" % current if current == 1 else "%d turns" % current
	return "%d/%d" % [current, maximum]
