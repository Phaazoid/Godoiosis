extends Panel

# Portrait corner of the inspect panel; falls back to the faceless placeholder
# (parity with the hover card).
#
# IT ALSO WEARS THE AURA RING (#930), because the ring wraps a portrait and this is the node that IS
# the portrait -- the same relationship PreMissionCard's identity column has to its map sprite, so the
# two surfaces carry one motif rather than two. It lives here rather than in info_panel.gd for the
# ordinary reason: that script is on StatsSection, a sibling subtree, and would have to reach across
# the panel to dress something it does not own.
#
# THE RING IS A CHILD, ADDED AFTER THE TEXTURE, and the order is what makes it work: a sibling drawn
# later draws on top, which is what lets the hover readout's scrim land ON the portrait rather than
# behind it. Built once and told, never rebuilt -- it owns hover state, and freeing a node the cursor
# is inside is #745's trap.

const FALLBACK: Texture2D = preload("res://Art/Units/Portraits/faceless_one.png")
const RING_PX := 108.0

@onready var portrait_texture: TextureRect = $PortraitTexture

var _aura_ring: AuraRing


func set_unit(unit: Unit):
	if unit == null:
		portrait_texture.texture = null
		if _aura_ring != null:
			_aura_ring.set_unit(null)
		return
	portrait_texture.texture = unit.unit_data.portrait if unit.unit_data.portrait != null else FALLBACK
	if _aura_ring == null:
		_aura_ring = AuraRing.over_portrait(unit, RING_PX)
		_aura_ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(_aura_ring)
	else:
		_aura_ring.set_unit(unit)
