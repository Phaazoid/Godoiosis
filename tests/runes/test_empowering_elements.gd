# #699: TransmutationData.empowering_elements, the elements a materia source must offer to empower a
# carving. It composes the +1's set (a formless carving) and the form's checklist (a formed one, #695), and
# the aim's source outline reads it. So these cases pin what it answers, and that the +1 pays where it says.
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


# A formed carving (#695) is empowered by its form's checklist, which takes the +1's place: what fires
# the form is what the outline must point at. Left empty, the checklist is the delivered elements.
func test_a_formed_carving_is_empowered_by_what_its_form_requires() -> void:
	var fireball := _carving(FIREBALL)
	fireball.empowered = EmpoweredForm.new()
	assert_array(fireball.empowering_elements()).is_equal(fireball.form_requires())
	assert_array(fireball.empowering_elements()).is_equal([FIRE])

	fireball.empowered.requires.assign([FIRE, WATER])
	assert_array(fireball.empowering_elements()).is_equal([FIRE, WATER])
	# The form itself answers for its base, so an aim that holds the derived carving marks the same.
	assert_array(fireball.empowered_carving().empowering_elements()).is_equal([FIRE, WATER])


# Even damageless, a formed carving is empowered: the form may change what is not damage.
func test_a_damageless_formed_carving_is_empowered_by_its_checklist() -> void:
	var splash := _carving(SPLASH, true)
	splash.empowered = EmpoweredForm.new()
	splash.empowered.requires.assign([WATER])
	assert_array(splash.empowering_elements()).is_equal([WATER])
