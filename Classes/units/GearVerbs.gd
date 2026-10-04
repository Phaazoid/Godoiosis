extends Object
class_name GearVerbs

# The inspect dock's six loadout verbs (#46 slice 2b): whether a unit may do one to a slot, and the
# act. ONE rule for the three places that perform them -- the dock's buttons (inventory_panel), the
# replay viewer re-applying a recorded act (ReplayDriver), and the headless Play API.
#
# Every refusal is the owning gate's own sentence (can_equip_reason, use_block_reason,
# remove_block_reason) wherever one exists. The few this file words itself ("already equipped",
# "nothing worn") answer a verb on a row the dock never offers it on, so no player reads them.
#
# UNEQUIP and REMOVE_ARMOR read NO index: they are about the unit, the doors behind them take none,
# and the dock has always recorded Remove with index -1 -- an index rule here would stop every run
# recorded before it from replaying.

enum Verb { EQUIP, UNEQUIP, WEAR, REMOVE_ARMOR, USE, TOSS }


# The recorded name -- the key lower-cased, which is the vocabulary MissionLog has always written
# into a run's "gear" events, so a renamed member breaks every recorded run.
static func name_of(verb: Verb) -> String:
	return String(Verb.keys()[verb]).to_lower()


# The verb a recorded name means, or -1 for a name this build does not know.
static func from_name(verb_name: String) -> int:
	return Verb.keys().find(verb_name.to_upper())


# WHY this unit may not do that to that slot -- "" means it may.
static func block_reason(unit: Unit, verb: Verb, index: int) -> String:
	match verb:
		Verb.UNEQUIP:
			return "" if unit.get_equipped_weapon() != null \
				else "%s has nothing equipped." % unit.get_unit_name()
		Verb.REMOVE_ARMOR:
			return "" if unit.worn_armor != null \
				else "%s is wearing no armour." % unit.get_unit_name()
		Verb.TOSS:
			return unit.remove_block_reason(index)
	var item: Item = unit.inventory[index] if index >= 0 and index < unit.inventory.size() else null
	if item == null:
		return "There is nothing in that slot."
	match verb:
		Verb.EQUIP:
			var equippable := item as EquippableData
			if equippable == null or equippable is ArmorData:
				return "%s is not something to equip." % item.shown_name()
			if item == unit.get_equipped_weapon():
				return "%s is already equipped." % item.shown_name()
			return equippable.can_equip_reason(unit)
		Verb.WEAR:
			var armor := item as ArmorData
			if armor == null:
				return "%s is not armour." % item.shown_name()
			if item == unit.worn_armor:
				return "%s is already worn." % item.shown_name()
			return armor.can_equip_reason(unit)
		Verb.USE:
			var vial := item as VialData
			if vial == null:
				return "That is not a vial."
			return vial.use_block_reason(unit)
	return ""


# Performs it, or says why not -- "" on success. The reason is asked first and the act is the same
# call's second half (Loadout.move's shape), each through the one Unit door that verb has.
static func perform(unit: Unit, verb: Verb, index: int) -> String:
	var refusal := block_reason(unit, verb, index)
	if refusal != "":
		return refusal
	match verb:
		Verb.EQUIP:
			unit.equip_weapon_from_inventory(index)
		Verb.UNEQUIP:
			unit.unequip_weapon()
		Verb.WEAR:
			unit.wear_armor(index)
		Verb.REMOVE_ARMOR:
			unit.remove_armor()
		Verb.USE:
			unit.use_vial(index)
		Verb.TOSS:
			unit.remove_item(index)
	return ""
