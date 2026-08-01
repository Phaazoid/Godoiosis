# The WeaponInstance family seam, stated once and checked against EVERY family (2026-08-01, suite
# audit). Three properties belong to the BASE CLASS, not to any one family:
#
#   1. battle state never survives copy_equippable()  -- a mission boundary resets it for free,
#      which is the entire reason those fields are non-@export;
#   2. two instances of a family track their state independently -- the #73 bug the subclass seam
#      exists to prevent (a unit can carry two of the same weapon);
#   3. a family's verbs are inert on every other family -- the base declares them so a family with
#      no signature mechanic pays nothing.
#
# Each was previously re-tested inside each family's own suite: "two carbines track independently",
# "two maces charge independently", "two chainswords rev independently", and so on -- about twelve
# cases proving three things, covering only the four families someone remembered to write them for,
# and growing by three or four more with every family added. They are now asserted once, over the
# FAMILIES table below, which covers all SEVEN.
#
# The generic observer is capture_battle_state() (#87's family-agnostic seam, base returns {}), so
# nothing here needs to know that a Carbine counts shots and a Chainsword counts turns. The one
# thing that cannot be generic is HOW to move a family off its default, so each row names its own
# verb and _disturb() dispatches -- that is the single place a new family has to appear.
#
# Adding family #8: add its row here. test_every_weapon_type_declares_a_family_row fails until you
# do, so the coverage cannot be silently skipped -- the same partition-law shape as
# tests/law/test_action_registry.gd and tests/law/test_ai_action_coverage.gd.
#
# Family-SPECIFIC behaviour stays in the family suites: the magazine's state machine in
# test_carbine_magazine.gd, the charge economy's authored-flag decoupling in
# test_kinetic_mace_charge.gd, the rev countdown in test_chainsword_rev.gd. This file only owns
# what is true of every family at once.
extends GdUnitTestSuite

# One row per WeaponType. `state` names the verb that moves a fresh instance off its default battle
# state, or "" for a family that has none. The three booleans are the self-ability verbs the family
# answers true to AFTER being disturbed (Springspear and Carbine only offer a reload once something
# has been spent, so "after" is the only moment the whole matrix is meaningful at once).
const FAMILIES := {
	WeaponData.WeaponType.CHAINSWORD:
		{"state": "rev", "rev": true, "reload": false, "burrow": false},
	WeaponData.WeaponType.SPRINGSPEAR:
		{"state": "spend", "rev": false, "reload": true, "burrow": false},
	WeaponData.WeaponType.CARBINE:
		{"state": "spend", "rev": false, "reload": true, "burrow": false},
	WeaponData.WeaponType.KINETIC_MACE:
		{"state": "bank", "rev": false, "reload": false, "burrow": false},
	WeaponData.WeaponType.DRILL:
		{"state": "", "rev": false, "reload": false, "burrow": true},
	WeaponData.WeaponType.CHEMICAL_SPITTER:
		{"state": "", "rev": false, "reload": false, "burrow": false},
	WeaponData.WeaponType.PROSTHETIC:
		{"state": "", "rev": false, "reload": false, "burrow": false},
}


func _family_name(family: WeaponData.WeaponType) -> String:
	return WeaponData.WeaponType.keys()[family]


func _fresh(family: WeaponData.WeaponType) -> WeaponInstance:
	var template := WeaponData.new()
	template.weapon_type = family
	template.main_attack = WeaponAttackData.new()
	return WeaponInstance.make(template)


# An attack that spends whatever its family banks, and one that banks it. The flags are the
# authored seam (#108) -- the families read these, never a private predicate of their own.
func _spender() -> WeaponAttackData:
	var attack := WeaponAttackData.new()
	attack.requires_readiness = true
	attack.consumes_readiness = true
	return attack


func _builder() -> WeaponAttackData:
	var attack := WeaponAttackData.new()
	attack.builds_readiness = true
	return attack


# The one thing that cannot be generic: each family's own way off its default state.
func _disturb(weapon: WeaponInstance, family: WeaponData.WeaponType) -> void:
	match str(FAMILIES[family]["state"]):
		"rev":
			weapon.rev()
		"spend":
			weapon.consume_readiness_for(_spender())
		"bank":
			weapon.consume_readiness_for(_builder())


func _is_stateful(family: WeaponData.WeaponType) -> bool:
	return str(FAMILIES[family]["state"]) != ""


# Every case that disturbs an instance calls this immediately afterwards, instead of trusting
# test_disturbing_a_stateful_family_actually_changes_its_state to have proven it earlier.
#
# The reason is measured, not theoretical. A mutation making SpringspearWeaponInstance.ready STATIC
# -- i.e. reintroducing the exact #73 bug this file exists to catch -- was NOT caught by an earlier
# draft, because a static survives between test cases: the first case to run spent it, and from
# then on _fresh() handed back an already-spent spear. Every later case took its baseline from that
# poisoned instance, disturbed something that was already disturbed, observed no change, and passed.
# Shared state defeats any assumption that a separate case established a precondition, which is
# precisely the assumption a shared-state bug is best placed to exploit.
func _assert_disturbed(weapon: WeaponInstance, family: WeaponData.WeaponType, before: Dictionary) -> void:
	if not _is_stateful(family):
		return
	assert_that(weapon.capture_battle_state()).override_failure_message(
		"%s did not move off %s when disturbed, so this case is proving nothing. Either its row's `state` verb is wrong, or the family is storing state somewhere SHARED (static/class-level) that a previous test already spent."
		% [_family_name(family), str(before)]).is_not_equal(before)


func _stateful_families() -> Array:
	var out: Array = []
	for family: WeaponData.WeaponType in FAMILIES:
		if _is_stateful(family):
			out.append(family)
	return out


# --- the completeness guard ---

func test_every_weapon_type_declares_a_family_row() -> void:
	# The partition law. A new family added to the enum has no row here, so every property below
	# would silently skip it -- this fails first and says so. NONE is the deliberate exception:
	# WeaponInstance.make() push_errors and returns null for it (pinned in
	# tests/weapons/test_weapon_instance_readiness.gd), so there is no instance to reason about.
	for value: int in WeaponData.WeaponType.values():
		if value == WeaponData.WeaponType.NONE:
			continue
		assert_bool(FAMILIES.has(value)).override_failure_message(
			"WeaponType.%s has no row in FAMILIES -- add one (state verb + verb matrix) or this family gets no seam coverage at all."
			% WeaponData.WeaponType.keys()[value]).is_true()

	# ...and no row for a type that no longer exists.
	for family: WeaponData.WeaponType in FAMILIES:
		assert_bool(WeaponData.WeaponType.values().has(family)).is_true()


func test_disturbing_a_stateful_family_actually_changes_its_state() -> void:
	# Anti-vacuity, and the case that makes the two below mean anything: if _disturb were a no-op
	# for some family, "state does not survive a copy" and "instances are independent" would both
	# pass while proving nothing at all about it.
	var checked := 0
	for family: WeaponData.WeaponType in _stateful_families():
		checked += 1
		var weapon := _fresh(family)
		var before := weapon.capture_battle_state()
		_disturb(weapon, family)
		assert_that(weapon.capture_battle_state()).override_failure_message(
			"_disturb() did not move %s off its default state (%s) -- its row's `state` verb is wrong, and every seam property below is vacuous for this family."
			% [_family_name(family), str(before)]).is_not_equal(before)
	assert_int(checked).is_greater(0)


# --- the three seam properties ---

func test_battle_state_never_survives_a_copy() -> void:
	# Non-@export state + copy_equippable()/make() is how a mission boundary resets a weapon for
	# free (#87): the snapshot has to put a magazine back EXPLICITLY, so nothing is carried by
	# accident. Checked for every family, including the stateless ones, where {} must stay {}.
	for family: WeaponData.WeaponType in FAMILIES:
		var weapon := _fresh(family)
		var default_state := weapon.capture_battle_state()
		_disturb(weapon, family)
		_assert_disturbed(weapon, family, default_state)
		var copy := weapon.copy_equippable() as WeaponInstance

		assert_that(copy.capture_battle_state()).override_failure_message(
			"A copied %s carried its battle state across (%s) -- a new mission would start mid-economy."
			% [_family_name(family), str(weapon.capture_battle_state())]
			).is_equal(default_state)
		# The other half of copy_equippable's contract: the family template stays SHARED. A bare
		# duplicate(true) would deep-copy it and silently fork the weapon off its family.
		assert_object(copy.template).override_failure_message(
			"A copied %s no longer shares its template -- editing the family would stop reaching it."
			% _family_name(family)).is_same(weapon.template)


func test_two_instances_of_a_family_track_state_independently() -> void:
	# The #73 bug this whole subclass seam exists to prevent: state on the Unit meant one spear's
	# spent flag leaked onto the other one in the same inventory. It lives on the WEAPON instead.
	for family: WeaponData.WeaponType in FAMILIES:
		var first := _fresh(family)
		var second := _fresh(family)
		var first_before := first.capture_battle_state()
		var second_before := second.capture_battle_state()
		_disturb(first, family)
		_assert_disturbed(first, family, first_before)

		assert_that(second.capture_battle_state()).override_failure_message(
			"Disturbing one %s changed the other's state -- the two are sharing storage."
			% _family_name(family)).is_equal(second_before)


func test_a_familys_verbs_never_leak_onto_another_family() -> void:
	# The base class declares can_rev/can_reload/can_burrow as inert (on EquippableData, so Unit can
	# delegate without casting). This is the matrix that says who overrides what: it replaces the
	# per-suite "a non-mace family has no charge economy" / "every other family cannot burrow"
	# cases, which each checked one verb against a hand-picked handful of families.
	for family: WeaponData.WeaponType in FAMILIES:
		var weapon := _fresh(family)
		_disturb(weapon, family)
		var row: Dictionary = FAMILIES[family]
		var name := _family_name(family)

		assert_bool(weapon.can_rev()).override_failure_message(
			"%s.can_rev() disagrees with its declared row" % name).is_equal(bool(row["rev"]))
		assert_bool(weapon.can_reload()).override_failure_message(
			"%s.can_reload() disagrees with its declared row (checked after its state verb ran)" % name
			).is_equal(bool(row["reload"]))
		assert_bool(weapon.can_burrow()).override_failure_message(
			"%s.can_burrow() disagrees with its declared row" % name).is_equal(bool(row["burrow"]))


# --- derived invariants ---

func test_a_family_reports_status_text_exactly_when_it_has_battle_state() -> void:
	# The #44 status seam's scope rule, which no single family suite could state: a family reports
	# status IFF it has state worth reporting. A stateless family returning text would put an empty
	# "Status:" line in the tooltip; a stateful one returning "" would hide the thing the player's
	# decision turns on.
	for family: WeaponData.WeaponType in FAMILIES:
		var weapon := _fresh(family)
		var reports := weapon.status_text() != ""
		assert_bool(reports).override_failure_message(
			"%s %s battle state but %s status text."
			% [_family_name(family),
				"has" if _is_stateful(family) else "has no",
				"reports no" if _is_stateful(family) else "reports"]
			).is_equal(_is_stateful(family))


func test_a_stateless_family_captures_nothing() -> void:
	# The base implementation, unoverridden: no fields, so nothing to snapshot and nothing for a
	# save to restore.
	var checked := 0
	for family: WeaponData.WeaponType in FAMILIES:
		if _is_stateful(family):
			continue
		checked += 1
		assert_dict(_fresh(family).capture_battle_state()).override_failure_message(
			"%s declares no battle state but captures some." % _family_name(family)).is_empty()
	assert_int(checked).is_greater(0)


func test_a_disturbed_family_round_trips_through_its_own_snapshot() -> void:
	# capture/apply are a PAIR (#87). Every family's snapshot must restore the state it captured,
	# or a mid-battle save silently rearms a spent weapon on load.
	for family: WeaponData.WeaponType in _stateful_families():
		var weapon := _fresh(family)
		_disturb(weapon, family)
		var snapshot := weapon.capture_battle_state()

		var restored := _fresh(family)
		restored.apply_battle_state(snapshot)
		assert_that(restored.capture_battle_state()).override_failure_message(
			"%s does not round-trip: captured %s but restored to %s."
			% [_family_name(family), str(snapshot), str(restored.capture_battle_state())]
			).is_equal(snapshot)
