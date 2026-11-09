# #699: TransmutationData.empowering_elements, the elements a materia source must offer to empower a
# carving. Two readers share it: base_damage's +1 and the aim's source outline. So these cases pin both:
# what it answers, and that the +1 pays exactly where it says.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const FIRE := Elemental.Element.FIRE
const WATER := Elemental.Element.WATER

# Recipes that make their own material out of the air (test_vial_empowerment's), one element each.
const FIREBALL := "Break(F, A) + Push(F2)"
const SPLASH := "Break(A, W) + Push(W2)"


func _carving(recipe: String, damageless := false) -> TransmutationData:
	var t := TransmutationData.new()
	t.power = 3
	t.recipe = recipe
	t.deals_no_damage = damageless
	return t


func _wielder() -> UnitState:
	var u: Unit = H.spawn_solo(self, H.make_manager(self), Team.Faction.PLAYER, Vector2i(0, 0))
	return u.state


func _asked(elements: Array) -> Array[Elemental.Element]:
	var out: Array[Elemental.Element] = []
	out.assign(elements)
	return out


func test_a_damaging_carving_is_empowered_by_what_its_hit_delivers() -> void:
	var fireball := _carving(FIREBALL)
	assert_array(fireball.empowering_elements()).is_equal(fireball.damage_elements())
	assert_array(fireball.empowering_elements()).is_equal([FIRE])


# A utility carving never takes the +1, so no source empowers it and the aim outlines nothing.
func test_a_damageless_carving_is_empowered_by_nothing() -> void:
	assert_array(_carving(SPLASH, true).empowering_elements()).is_empty()


# The +1 pays in exactly the elements empowering_elements names, and in no other.
func test_the_plus_one_pays_exactly_in_the_empowering_elements() -> void:
	var fireball := _carving(FIREBALL)
	var wielder := _wielder()
	var bare := fireball.base_damage(wielder)
	assert_int(fireball.base_damage(wielder, _asked(fireball.empowering_elements()))).is_equal(bare + 1)
	assert_int(fireball.base_damage(wielder, _asked([WATER]))).is_equal(bare)
