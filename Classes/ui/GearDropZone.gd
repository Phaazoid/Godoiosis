class_name GearDropZone
extends PanelContainer

# Somewhere gear can LAND (#741) -- a unit's item list, or the stash's. GearRow extends this and adds
# the dragging half, so a row is a drop zone that can also be picked up.
#
# THE ZONE JUDGES NOTHING ITSELF. Both callables come from the surface that owns the Loadout, and
# they are the same pair the click path uses: _can_drop_data asks the judge, _drop_data calls the
# act. A drag that decided for itself would be a second answer to "may this move" -- the shape #744
# spent a ticket collapsing one layer down, and the reason all four directions are one function.
#
# `owner_unit` null means THE STASH, at both ends, which is what makes stash->unit, unit->stash and
# unit->unit one call rather than three near-copies.

signal clicked(item: Item, owner_unit: Unit)

const PAYLOAD_ITEM := "gear_item"
const PAYLOAD_FROM := "gear_from"

# Godot starts a drag once the pointer has travelled ~10px while held, and only then asks
# _get_drag_data. A gesture shorter than that is never a drag, so it is a click -- one threshold, two
# verdicts, no gap between them and no way to be both.
const CLICK_SLOP := 10.0

var owner_unit: Unit = null
var _press_at := Vector2.INF
var judge: Callable = Callable()     # (item, from, to) -> String, "" = allowed
var perform: Callable = Callable()   # (item, from, to) -> String, "" = done


func wire(unit: Unit, judge_move: Callable, perform_move: Callable) -> void:
	owner_unit = unit
	judge = judge_move
	perform = perform_move
	mouse_filter = Control.MOUSE_FILTER_STOP   # IGNORE would take this out of the drag's reach


# A CLICK IS THE RELEASE, NOT THE PRESS, AND THAT IS WHAT MAKES DRAGGING POSSIBLE AT ALL (#789).
#
# Acting on the press told the screen to redraw, and the redraw frees every row in both lists to
# rebuild them -- including the one the pointer is still holding down, one idle frame later. Godot
# asks _get_drag_data only after ~10px of movement WHILE HELD, which takes several frames, so the
# drag source was always destroyed before it could be asked and _get_drag_data never ran once.
# Clicking still worked, because a click is over before the free; dragging could not work at all.
#
# The travelled distance is what separates the two, and the threshold is Godot's own: a gesture that
# reaches it becomes a drag and this never sees the release, one that does not is a click.
func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if click.pressed:
		_press_at = click.position
		return
	# INF when this row never saw the press -- the pointer arrived from somewhere else, and that is
	# nobody's click. Vector2.INF answers INF to distance_to, so the sentinel needs no second guard
	# beside the comparison; one of those was here, and a mutant deleting it changed nothing.
	var travelled := _press_at.distance_to(click.position)
	_press_at = Vector2.INF
	if travelled <= CLICK_SLOP:
		clicked.emit(_dragged_item(), owner_unit)


# What this zone offers when picked up. A bare zone is a destination only; GearRow overrides it.
func _dragged_item() -> Item:
	return null


# TYPE-CHECKED, never cast. Godot offers _can_drop_data whatever the CURRENT drag carries, and that
# is not always one of ours -- a null, a String, an addon's own payload. `as Dictionary` is a hard
# cast on a non-Object type, so it does not degrade to null the way an object cast does: it throws,
# and takes the frame with it.
static func payload_of(data: Variant) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	var carried: Dictionary = data
	return carried if carried.has(PAYLOAD_ITEM) else {}


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	var carried := payload_of(data)
	if carried.is_empty() or not judge.is_valid():
		return false
	return judge.call(carried[PAYLOAD_ITEM], carried[PAYLOAD_FROM], owner_unit) == ""


func _drop_data(_at: Vector2, data: Variant) -> void:
	var carried := payload_of(data)
	if carried.is_empty() or not perform.is_valid():
		return
	perform.call(carried[PAYLOAD_ITEM], carried[PAYLOAD_FROM], owner_unit)
