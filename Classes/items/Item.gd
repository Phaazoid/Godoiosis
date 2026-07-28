extends Resource
class_name Item

# Base vocabulary for anything a unit can hold. Weight lives here, not on the equippable
# subclasses: anything that can sit in an inventory can weigh something.

@export var item_name: String
@export var icon: Texture2D
@export var description: String

# Authored mass. A property of the ITEM alone -- no stat feeds it (the old CON body term was
# doctrine drift, removed 2026-07-27). Tracked but INERT: nothing reads it into a rule yet.
@export var weight: int = 0

# Virtual so a composite item can report more than its authored value (WeaponInstance adds
# its fitted modules). Everything else is just itself.
func get_effective_weight() -> int:
	return weight
