extends Object
class_name ElementPalette

# Single source of truth for what an ELEMENT looks like in 2D UI -- StateIcons' shape, for colour
# instead of art (#685). Nothing in the project answered "what colour is Fire" before this: the
# board's own colour forks (OverlayManager's reach/aim statics, #422's AIM_PALETTES) are keyed on
# heals-vs-damage and watch-vs-attack, never on Elemental.Element.
#
# Deliberately NOT part of the aim palette a player picks -- widening THAT vocabulary is #675's job,
# and these are the dev's own authored colours, tuned through GameKnobs' Elemental tab.
#
# `static var` rather than `const` because each one is a GameKnobs.CLASS_KNOBS row: a feel value gets
# a knob, and this is 2D UI, which the node-property table structurally cannot reach.
static var ELEMENT_FIRE := Color(0.937, 0.451, 0.314)
static var ELEMENT_WATER := Color(0.353, 0.682, 0.91)
static var ELEMENT_SHOCK := Color(0.706, 0.541, 0.91)
static var ELEMENT_ICE := Color(0.557, 0.827, 0.918)
static var ELEMENT_EARTH := Color(0.812, 0.639, 0.306)
static var ELEMENT_AIR := Color(0.486, 0.788, 0.58)
static var ELEMENT_AETHER := Color(0.878, 0.486, 0.753)

# What a row with no element wears -- the rail's off state, and the reason a neutral is here rather
# than at the caller: an insulated hit and a plain sword swing must not be told apart by accident.
const NEUTRAL := Color(0.29, 0.29, 0.33)


static func color_for_element(element: Elemental.Element) -> Color:
	match element:
		Elemental.Element.FIRE: return ELEMENT_FIRE
		Elemental.Element.WATER: return ELEMENT_WATER
		Elemental.Element.SHOCK: return ELEMENT_SHOCK
		Elemental.Element.ICE: return ELEMENT_ICE
		Elemental.Element.EARTH: return ELEMENT_EARTH
		Elemental.Element.AIR: return ELEMENT_AIR
		Elemental.Element.AETHER: return ELEMENT_AETHER
	return NEUTRAL


# A STATE borrows the colour of the element that deposits it rather than owning a second set: the
# player learns one vocabulary, and a chill chip cannot drift from the ice that caused it. Second
# projection of one store, not a second store (Law #4).
static func color_for_state(state: Elemental.State) -> Color:
	match state:
		Elemental.State.WET: return ELEMENT_WATER
		Elemental.State.CHILLED: return ELEMENT_ICE
	return NEUTRAL
