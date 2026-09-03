extends AIWeaponRoutine
class_name SpringspearWeaponRoutine

# Springspear (#726): the spearman saves the spring for a line or a kill. Spring outdamages Stab by
# two and the score takes the two every time -- but on this family a spent spring gates EVERY
# attack (Stab requires readiness too), so firing it costs the whole next turn (a Spring Load) and
# the enemy turn's counter besides. Over two turns Stab-Stab beats Spring-then-reload, unless the
# line catches more than one or the extra power fells somebody.
#
# DEFERRED, never deleted, and member-local (AITactics._best_candidate_for): a Spring that is this
# member's only candidate is still taken, because the alternative is not attacking (#711).
#
# "Fells" is the MARGINAL removal term the caller already computed, never _plan_removes on the
# hypothetical, which reads true when a squadmate's queued swing already fells the target.

static var SPRING_LINE_MINIMUM := 2   # playtest-tunable: enemies a Spring must catch to be worth the disarm


func defers_candidate(unit: Unit, candidate: AttackAction, plan: ResolvedPlan, score: Vector3i) -> bool:
	if not _disarms(unit, candidate.fired_attack):
		return false
	if score.x > 0:
		return false
	return _enemy_victims_of(unit, candidate, plan) < SPRING_LINE_MINIMUM


# Does firing this leave the member with nothing fireable? Read off the CONTENT rather than assumed
# of the family: a consumed spring, and no other selectable attack that fires without one. If Stab
# ever stops requiring readiness, Spring stops disarming and this rule stands down on its own.
func _disarms(unit: Unit, attack: AttackData) -> bool:
	var spender := attack as WeaponAttackData
	if spender == null or not spender.consumes_readiness:
		return false
	for other in unit.get_selectable_attacks():
		if other == attack:
			continue
		var other_weapon_attack := other as WeaponAttackData
		if other_weapon_attack != null and not other_weapon_attack.requires_readiness:
			return false
	return true


# Rows of the candidate's OWN volley (source_aim back-links every derived row to the order that
# produced it) that land on somebody hostile.
func _enemy_victims_of(unit: Unit, candidate: AttackAction, plan: ResolvedPlan) -> int:
	var count := 0
	for row in plan.attacks:
		if row.source_aim != candidate or row.target == null or not is_instance_valid(row.target):
			continue
		if Team.is_enemy(unit.get_faction(), row.target.get_faction()):
			count += 1
	return count
