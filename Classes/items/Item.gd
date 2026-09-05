extends Resource
class_name Item

# Base vocabulary for anything a unit can hold. Weight lives here, not on the equippable
# subclasses: anything that can sit in an inventory can weigh something.

# Was `item_name` until #141; renamed so all four content roots agree on one field name.
@export var display_name: String
@export var icon: Texture2D
@export var description: String

# Authored mass. A property of the ITEM alone -- no stat feeds it (the old CON body term was
# doctrine drift, removed 2026-07-27). Tracked but INERT: nothing reads it into a rule yet.
@export var weight: int = 0

# Virtual so a composite item can report more than its authored value (WeaponInstance adds
# its fitted modules). Everything else is just itself.
func get_effective_weight() -> int:
	return weight

# Field text for the dev tools' reflective editor (#473). Declared here so every item subclass
# inherits the four base fields rather than restating them -- a subclass merges this into its own.
static func property_tips() -> Dictionary:
	return {
		"display_name": "What this item is called wherever the game names it.",
		"icon": "The picture shown in menus and the inventory. Optional -- an item with none simply draws nothing.",
		"description": "Flavour text. Presentation only; no rule reads it. A weapon may leave this blank and inherit its template's -- see WeaponInstance.describe.",
		"weight": "Authored mass. Tracked but nearly inert -- fall damage is its one wired reader (#120 owns the rest).",
	}


# THE one door for reading flavour, so a kind that inherits its wording from somewhere else can say
# so in one place (#745). Everything that renders a description asks this, never the field: the field
# is storage, and for a WeaponInstance the stored value is usually empty on purpose.
func describe() -> String:
	return description
