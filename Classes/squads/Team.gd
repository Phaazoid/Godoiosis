extends Resource
class_name Team


enum Faction {
	PLAYER,
	ENEMY,
	NEUTRAL,
	ALLY,
	OTHER	
}

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
