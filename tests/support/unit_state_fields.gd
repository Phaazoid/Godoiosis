# How a body's every script variable is treated (#1480): the tables tests/law/test_unit_state_copy.gd
# checks UnitState.copy against, refusing a field none names, and the fingerprint
# tests/law/test_a_pass_writes_no_live_body.gd compares a live body by. One classification for both
# laws, so a new field is classified once.
extends RefCounted

# How a copy treats a field, and so what a fingerprint records of it.
enum Kind {
	EQUAL,      # a value: equal on the copy; the fingerprint records the value
	OWN,        # a container: equal contents, its own instance; the fingerprint records the contents
	SHARED,     # authored or identity: the same object; the fingerprint records which object
	TWIN,       # a carried weapon: the copy's own instance, with the same fields
	CHECKED,    # an owned object whose own table checks it (the instance, the limbs, the inventory)
}

const UNIT_STATE := {
	"unit": Kind.SHARED,
	"instance": Kind.CHECKED,
	"inventory": Kind.CHECKED,
	"equipped_weapon": Kind.TWIN,
	"worn_armor": Kind.SHARED,
	"attunement": Kind.SHARED,
	"element_states": Kind.OWN,
	"stat_effects": Kind.OWN,
	"lifecycle_state": Kind.EQUAL,
	"wounded": Kind.EQUAL,
	"in_crisis": Kind.EQUAL,
	"crisis_surge_pending": Kind.EQUAL,
	"downed_turns_remaining": Kind.EQUAL,
}

const UNIT_INSTANCE := {
	"data": Kind.SHARED,
	"stats": Kind.OWN,
	"aura": Kind.OWN,
	"affinity": Kind.OWN,
	"is_alkahest_affine": Kind.EQUAL,
	"current_hp": Kind.EQUAL,
	"weapon_proficiency": Kind.OWN,
	"jobs": Kind.OWN,
	"limbs": Kind.CHECKED,
	"permadead": Kind.EQUAL,
}

const LIMB_FITTING := {
	"state": Kind.EQUAL,
	"prosthetic_stat": Kind.EQUAL,
	"prosthetic_item": Kind.TWIN,
}

# Every family's fields, Item's and WeaponInstance's included. The battle state rides
# capture_battle_state/apply_battle_state; the rest rides copy_for_grant.
const WEAPON := {
	"display_name": Kind.EQUAL,
	"icon": Kind.SHARED,
	"description": Kind.EQUAL,
	"weight": Kind.EQUAL,
	"template": Kind.SHARED,
	"limb_kind": Kind.EQUAL,
	"spaces": Kind.OWN,
	"shots_remaining": Kind.EQUAL,
	"revved_turns_remaining": Kind.EQUAL,
	"charges": Kind.EQUAL,
	"charge": Kind.EQUAL,
	"ready": Kind.EQUAL,
}


# The live body as plain values, so two fingerprints taken around a pass compare with `==` and a
# difference names its field. Walks the tables above, so a field they classify is a field it records.
static func fingerprint(body: UnitState) -> Dictionary:
	var out := {}
	_record(out, "", body, UNIT_STATE)
	_record(out, "instance.", body.instance, UNIT_INSTANCE)
	for slot in body.instance.limbs:
		_record(out, "limbs[%d]." % slot, body.instance.limbs[slot], LIMB_FITTING)
	out["inventory.size"] = body.inventory.size()
	for i in body.inventory.size():
		_record_item(out, "inventory[%d]" % i, body.inventory[i])
	return out


static func _record(out: Dictionary, prefix: String, obj: Object, table: Dictionary) -> void:
	for name: String in table:
		if not name in obj:
			continue
		var value: Variant = obj.get(name)
		match table[name]:
			Kind.EQUAL:
				out[prefix + name] = value
			Kind.OWN:
				out[prefix + name] = value.duplicate(true)
			Kind.SHARED:
				out[prefix + name] = _identity(value)
			Kind.TWIN:
				_record_item(out, prefix + name, value)


# A carried item: which object, and for a weapon its own fields too, so a spent live tank shows.
static func _record_item(out: Dictionary, key: String, item: Variant) -> void:
	out[key] = _identity(item)
	if item is WeaponInstance:
		_record(out, key + ".", item, WEAPON)


static func _identity(value: Variant) -> Variant:
	if value is Object:
		return (value as Object).get_instance_id() if is_instance_valid(value) else 0
	return value


# The keys whose values differ between two fingerprints, for a failure message.
static func diff(before: Dictionary, after: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for key: String in before:
		if not after.has(key) or after[key] != before[key]:
			keys.append(key)
	for key: String in after:
		if not before.has(key):
			keys.append(key)
	return keys
