extends Object
class_name StateIcons

# Single source of truth for elemental-state icon art, shared by every surface that shows a
# unit's held states (hover card, inspect bar). Append-only alongside Elemental.State.
const ICONS := {
	Elemental.State.WET: preload("res://Art/Icons/WetIcon.png"),
}
const ICON_SIZE := Vector2i(16, 16)

# Clears `container` and refills it with one 16x16 icon per non-NONE state the unit holds.
# A state with no art yet falls back to a short text label, so nothing is silently dropped.
static func populate(container: Node, states: Array) -> void:
	for child in container.get_children():
		child.queue_free()
	for state in states:
		if state == Elemental.State.NONE:
			continue
		var tex: Texture2D = ICONS.get(state, null)
		if tex != null:
			var rect := TextureRect.new()
			rect.texture = tex
			rect.custom_minimum_size = ICON_SIZE
			rect.expand_mode = TextureRect.EXPAND_KEEP_SIZE
			rect.stretch_mode = TextureRect.STRETCH_KEEP
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			container.add_child(rect)
		else:
			var lbl := Label.new()
			lbl.text = Elemental.State.keys()[state].capitalize()
			lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			container.add_child(lbl)
