extends Resource
class_name Team


enum Faction {
	PLAYER,
	ENEMY,
	NEUTRAL,
	ALLY,
	OTHER	
}

# Every declared faction, in enum-declaration order. The one place the turn rotation reads from —
# add a member to the Faction enum above and it joins the cycle automatically.
static func all_factions() -> Array[Team.Faction]:
	var result: Array[Team.Faction] = []
	for f in Faction.values():
		result.append(f)
	return result

#Hardcoded for now, can change if we ever add more complicated team stuff
static func is_enemy(a: Team.Faction, b: Team.Faction) -> bool:
	if a == b:
		return false
	match a:
		Team.Faction.PLAYER:
			return b == Faction.ENEMY
		Team.Faction.ENEMY:
			return b == Faction.PLAYER or b == Faction.ALLY
		Team.Faction.ALLY:
			return b == Faction.ENEMY
		_:
			return false
			
static func faction_name(f: Faction) -> String:
	var raw: String = Faction.keys()[f]
	return raw.substr(0, 1) + raw.substr(1).to_lower()
	
