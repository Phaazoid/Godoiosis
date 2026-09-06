# #697: carried pure materia -- the vial item, the Use verb, the held charge, and the DIFFERENTIAL
# burn. Canon: docs/design/alchemy-kit.md -> Materia -> Carried pure -- the vial.
#
# THE ONE LAW is what most of these guard: nothing here may refuse a cast. use_block_reason is the
# only refusal in the ticket and it refuses a WASTED BURN, never a cast.
#
# The board is stubbed rather than painted (test_materia_sources.gd's idiom) -- the fixture grid has
# no TileSet, and the on-a-source cases are what make the burn rule interesting.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const FIRE := Elemental.Element.FIRE
const WATER := Elemental.Element.WATER

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)

class _StubBoard extends BoardContext:
	var kinds: Dictionary
	func _init(g: TileMapLayer, u: Array[Unit], m: SquadManager, k: Dictionary) -> void:
		super(g, u, m)
		kinds = k
	func terrain_kind_at(cell: Vector2i) -> Terrain.Kind:
		return kinds.get(cell, Terrain.Kind.NONE)

func _board(kinds: Dictionary = {}) -> _StubBoard:
	var none: Array[Unit] = []
	return _StubBoard.new(null, none, _sm, kinds)

func _vial(element: Elemental.Element, alkahest := false) -> VialData:
	var v := VialData.new()
	v.element = element
	v.is_alkahest = alkahest
	v.display_name = "Vial of Alkahest" if alkahest else "Vial of %s" % Elemental.display_name(element)
	return v

func _alchemist(aura: Dictionary[Elemental.Element, int], cell := Vector2i(0, 0)) -> Unit:
	var u: Unit = H.spawn_solo(self, _sm, PLAYER, cell)
	u.unit_instance.aura = aura
	var affinity: Array[Elemental.Element] = []
	for element in aura:
		affinity.append(element)
	u.unit_instance.affinity = affinity
	return u

# Sigils REPEAT as weight, which is what makes the "+1 per matching sigil" claim testable.
func _carving(power: int, sigils: Array) -> TransmutationData:
	var t := TransmutationData.new()
	t.power = power
	t.sigils.assign(sigils)
	t.targets = EquippableData.TargetMode.UNIT
	return t

# Resolve one cast against `board` and hand back the action, so every case below reads the same.
func _cast(attacker: Unit, carving: TransmutationData, board: BoardContext) -> AttackAction:
	var foe: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	var atk: AttackAction = AttackAction.create(attacker, attacker.movement.cell, foe, Vector2i(1, 0))
	atk.fired_attack = carving
	var plan: ResolvedPlan = ResolvedPlan.new()
	plan.attacks.append(atk)
	var no_reactions: Array[ElementalReaction] = []
	PlanResolver.resolve(plan, no_reactions, board)
	return atk

# --- the item itself ------------------------------------------------------------------------

func test_an_element_vial_grants_only_its_element() -> void:
	assert_array(_vial(FIRE).granted_elements()).is_equal([FIRE])

func test_an_alkahest_vial_grants_every_sigil_element() -> void:
	assert_array(_vial(Elemental.Element.NONE, true).granted_elements()) \
		.contains(Elemental.SIGIL_ELEMENTS)

# SIGIL_ELEMENTS is a const Array and therefore READ-ONLY, and that flag TRAVELS with assignment.
# Handing the const out directly would give the resolver a list it cannot union into, which fails
# nowhere near here.
func test_the_alkahest_grant_is_writable() -> void:
	var granted := _vial(Elemental.Element.NONE, true).granted_elements()
	granted.append(Elemental.Element.SHOCK)   # would push_error on a read-only array
	assert_array(granted).contains([Elemental.Element.SHOCK])

func test_a_vial_with_no_element_grants_nothing() -> void:
	assert_array(_vial(Elemental.Element.NONE).granted_elements()).is_empty()

# --- Use, and what it refuses ---------------------------------------------------------------

func test_using_a_vial_attunes_the_unit_and_empties_the_slot() -> void:
	var alch: Unit = _alchemist({ FIRE: 2 })
	alch.add_item(_vial(FIRE))
	var slot := alch.inventory.find(alch.inventory.filter(func(i): return i is VialData)[0])

	assert_str(alch.use_vial(slot)).is_equal("")
	assert_object(alch.attunement).is_not_null()
	assert_array(alch.attunement_elements()).is_equal([FIRE])
	assert_object(alch.inventory[slot]).is_null()

func test_a_second_vial_replaces_the_first() -> void:
	var alch: Unit = _alchemist({ FIRE: 2, WATER: 2 })
	alch.attunement = _vial(FIRE)
	alch.add_item(_vial(WATER))
	var slot: int = alch.inventory.find(alch.inventory.filter(func(i): return i is VialData)[0])

	assert_str(alch.use_vial(slot)).is_equal("")
	assert_array(alch.attunement_elements()).is_equal([WATER])

# The ONLY refusal in this ticket, and it is a kindness rather than a gate: it stops the player
# spending a scarce item on something they already have.
func test_using_a_vial_you_are_already_attuned_to_is_refused() -> void:
	var alch: Unit = _alchemist({ FIRE: 2 })
	alch.attunement = _vial(FIRE)
	assert_str(_vial(FIRE).use_block_reason(alch)).is_not_empty()

func test_an_element_vial_is_refused_over_an_alkahest_charge() -> void:
	var alch: Unit = _alchemist({ FIRE: 2 })
	alch.attunement = _vial(Elemental.Element.NONE, true)
	assert_str(_vial(FIRE).use_block_reason(alch)).is_not_empty()

# The other direction is an UPGRADE and must stay allowed -- alkahest covers what fire does and more.
func test_an_alkahest_vial_may_replace_an_element_charge() -> void:
	var alch: Unit = _alchemist({ FIRE: 2 })
	alch.attunement = _vial(FIRE)
	assert_str(_vial(Elemental.Element.NONE, true).use_block_reason(alch)).is_equal("")

func test_a_different_element_may_replace_a_charge_and_says_what_it_replaces() -> void:
	var alch: Unit = _alchemist({ FIRE: 2, WATER: 2 })
	alch.attunement = _vial(FIRE)
	var water := _vial(WATER)
	assert_str(water.use_block_reason(alch)).is_equal("")
	assert_str(water.use_replaces(alch)).is_equal(alch.attunement.display_name)

func test_a_vial_replaces_nothing_when_nothing_is_held() -> void:
	assert_str(_vial(FIRE).use_replaces(_alchemist({ FIRE: 2 }))).is_equal("")

# --- the payload ------------------------------------------------------------------------------

func test_a_charge_empowers_a_cast_away_from_any_source() -> void:
	var alch: Unit = _alchemist({ FIRE: 4 })
	var bare: AttackAction = _cast(alch, _carving(5, [FIRE]), _board())
	assert_int(bare.resolved.damage).is_equal(9)          # power 5 + fire aura 4

	alch.attunement = _vial(FIRE)
	var lit: AttackAction = _cast(alch, _carving(5, [FIRE]), _board())
	assert_int(lit.resolved.damage).is_equal(10)          # +1 effective aura

# Repeated sigils weight the bonus, exactly as they weight the real pool (#694's rule, unchanged --
# a vial grants what a source grants and never more).
func test_repeated_sigils_weight_the_charge() -> void:
	var alch: Unit = _alchemist({ FIRE: 4 })
	alch.attunement = _vial(FIRE)
	var atk: AttackAction = _cast(alch, _carving(5, [FIRE, FIRE]), _board())
	assert_int(atk.resolved.damage).is_equal(15)          # 5 + (4+1) + (4+1)

func test_an_alkahest_charge_empowers_any_element() -> void:
	var alch: Unit = _alchemist({ WATER: 3 })
	alch.attunement = _vial(Elemental.Element.NONE, true)
	var atk: AttackAction = _cast(alch, _carving(2, [WATER]), _board())
	assert_int(atk.resolved.damage).is_equal(6)           # 2 + (3+1)

func test_a_charge_in_the_wrong_element_changes_nothing() -> void:
	var alch: Unit = _alchemist({ FIRE: 4 })
	alch.attunement = _vial(WATER)
	var atk: AttackAction = _cast(alch, _carving(5, [FIRE]), _board())
	assert_int(atk.resolved.damage).is_equal(9)

# --- the DIFFERENTIAL burn --------------------------------------------------------------------

func test_the_burn_is_recorded_when_the_charge_paid() -> void:
	var alch: Unit = _alchemist({ FIRE: 4 })
	var vial := _vial(FIRE)
	alch.attunement = vial
	var atk: AttackAction = _cast(alch, _carving(5, [FIRE]), _board())
	assert_object(atk.resolved.burned_vial).is_same(vial)

# THE case the rule exists for: the terrain already granted fire, so the charge bought nothing and
# must not be spent. A player standing in the right place keeps their vial.
func test_standing_on_a_source_pays_instead_of_the_vial() -> void:
	var alch: Unit = _alchemist({ WATER: 4 })
	alch.attunement = _vial(WATER)
	var atk: AttackAction = _cast(alch, _carving(5, [WATER]),
			_board({ alch.movement.cell: Terrain.Kind.WATER }))
	assert_int(atk.resolved.damage).is_equal(10)          # empowered -- by the river, not the vial
	assert_object(atk.resolved.burned_vial).is_null()

func test_a_charge_no_sigil_matches_is_not_burned() -> void:
	var alch: Unit = _alchemist({ FIRE: 4 })
	alch.attunement = _vial(WATER)
	var atk: AttackAction = _cast(alch, _carving(5, [FIRE]), _board())
	assert_object(atk.resolved.burned_vial).is_null()

# A carving that deals no damage has its scaling suppressed, so the charge cannot change the answer
# and must not be spent. #695 is the ticket that gives these something to gain.
func test_a_no_damage_carving_does_not_burn_the_charge() -> void:
	var alch: Unit = _alchemist({ FIRE: 4 })
	alch.attunement = _vial(FIRE)
	var carving := _carving(5, [FIRE])
	carving.deals_no_damage = true
	var atk: AttackAction = _cast(alch, carving, _board())
	assert_object(atk.resolved.burned_vial).is_null()

# Partial credit still counts: the water half was already free, but FIRE was load-bearing, so the
# vial paid for something and is spent.
func test_a_multi_sigil_carving_burns_when_only_one_element_needed_it() -> void:
	var alch: Unit = _alchemist({ FIRE: 3, WATER: 3 })
	var vial := _vial(FIRE)
	alch.attunement = vial
	var atk: AttackAction = _cast(alch, _carving(2, [FIRE, WATER]),
			_board({ alch.movement.cell: Terrain.Kind.WATER }))
	assert_object(atk.resolved.burned_vial).is_same(vial)
	assert_int(atk.resolved.damage).is_equal(10)          # 2 + (3+1 fire, vial) + (3+1 water, river)

func test_an_unattuned_caster_records_no_burn() -> void:
	var alch: Unit = _alchemist({ FIRE: 4 })
	var atk: AttackAction = _cast(alch, _carving(5, [FIRE]), _board())
	assert_object(atk.resolved.burned_vial).is_null()

# --- the invariants: a charge is a DAMAGE term and nothing else (#694's three, re-asked) --------

# get_element_aura is what the anchor, the channel deficit, both wildcard pools and the equip gate
# all read. Keeping it blind to attunement is the whole of keeping materia out of every gate at
# once -- so this asserts the accessor, not each gate.
func test_a_charge_does_not_move_the_aura_accessor() -> void:
	var alch: Unit = _alchemist({ FIRE: 4 })
	alch.attunement = _vial(FIRE)
	assert_int(alch.get_element_aura(FIRE)).is_equal(4)

func test_a_charge_does_not_grant_an_element_the_caster_has_none_of() -> void:
	var alch: Unit = _alchemist({ FIRE: 4 })
	alch.attunement = _vial(WATER)
	assert_int(alch.get_element_aura(WATER)).is_equal(0)
