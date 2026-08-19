extends Object
class_name StateIcons

# Single source of truth for elemental-state icon art, shared by every surface that shows a
# unit's held states (hover card, inspect bar, and since #357 the world-space row over the health
# bar). Append-only alongside Elemental.State.
const ICONS := {
	Elemental.State.WET: preload("res://Art/Icons/StateIcons/WetIcon.png"),
	# PLACEHOLDER (dev call, #357): the FROZEN terrain tile standing in until a 16px CHILLED icon
	# exists. It lands here rather than at any one surface, so all three pick it up at once.
	Elemental.State.CHILLED: preload("res://Art/Icons/TerrainIcons/Ice.png"),
}
# The size every icon RENDERS at, not the size the source art happens to be — those disagree (the
# wet drop is 32px, the ice tile 16px) and an unnormalised row shows one at half the other's size.
# 32 is the larger source, so existing surfaces are untouched and only the placeholder scales.
const ICON_SIZE := Vector2i(32, 32)

# The art a state list resolves to, in the caller's own order — what a surface that draws its own
# icons reads, so nothing outside this file indexes ICONS directly (#357's 3D row). A state with no
# art is SKIPPED here rather than falling back the way populate does below: a world-space row has no
# text to fall back to. With CHILLED covered that skip is a guard for the next state, not live.
static func textures_for(states: Array) -> Array[Texture2D]:
	var textures: Array[Texture2D] = []
	for state in states:
		if state == Elemental.State.NONE:
			continue
		var tex: Texture2D = ICONS.get(state, null)
		if tex != null:
			textures.append(tex)
	return textures


# Clears `container` and refills it with one ICON_SIZE icon per non-NONE state the unit holds.
# A state with no art yet falls back to a short text label, so nothing is silently dropped.
# Every entry carries the state's glossary short text as its tooltip (#135) — the unit half of
# visual-clarity.md's tooltip doctrine: hovering an elemental effect explains it in place.
static func populate(container: Node, states: Array) -> void:
	for child in container.get_children():
		child.queue_free()
	for state in states:
		if state == Elemental.State.NONE:
			continue
		var tip: String = UiText.wrap("%s — %s" % [Elemental.state_display_name(state),
			Glossary.short(Glossary.term_for_element_state(state))])
		var tex: Texture2D = ICONS.get(state, null)
		if tex != null:
			var rect := TextureRect.new()
			rect.texture = tex
			# Rendered AT ICON_SIZE whatever the source resolution — the same recipe
			# HoverInfoPanelControl already draws these 16px terrain icons at 32 with. Nearest
			# because the scale is a clean power of two and this is pixel art.
			rect.custom_minimum_size = ICON_SIZE
			rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			rect.tooltip_text = tip
			rect.mouse_filter = Control.MOUSE_FILTER_STOP
			container.add_child(rect)
		else:
			var lbl := Label.new()
			lbl.text = Elemental.state_display_name(state)
			lbl.tooltip_text = tip
			lbl.mouse_filter = Control.MOUSE_FILTER_STOP
			container.add_child(lbl)
