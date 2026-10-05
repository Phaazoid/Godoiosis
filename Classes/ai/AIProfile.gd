extends Resource
class_name AIProfile

# How WELL an AI-controlled unit plays (#1230): one switch or notch per behaviour the archetypes
# already have. The archetype says what a squad WANTS (who it chases, where it stands, which actions
# it will ever take); a profile says how sharply it goes about it. Per UNIT, never per squad, because
# units join and leave squads -- and where a squad decides once for everyone (who to fight, where to
# go), its LEADER's profile decides.
#
# Three shipped bands live in Resources/AIProfiles/ (Easy, Medium, Hard); a bespoke unit (a boss) is
# another file beside them, and a unit names its profile by FILE NAME (AIProfiles). The class
# defaults ARE the full AI -- the Hard column -- so a file stores only where it differs, and the AI
# suites declare AIProfile.new() as their profile rather than reading the tuned bands.
#
# Adding a knob: its default lands in every band at once, because a .tres omits a default. Decide its
# value in each band file in the same diff (CLAUDE.md's embedded-content sweep).

# What the unit refuses to do to its own side with its own attack.
enum FriendlyFire {
	NEVER_DOWNS,   ## refuses a candidate that downs or kills a unit of its own side
	NEVER_KILLS,   ## may down one, never kill one
}

# How far the unit goes looking for an opportunity it can reach this turn (#760's seek).
enum Seek {
	KILLS_AND_SPLITS,   ## a mission kill, a removal, or knocking someone out of their squad
	KILLS,              ## a mission kill or a removal only
	NONE,               ## never leaves its usual cell to look
}

## With somebody in reach, takes the best exchange (a target that cannot answer it). Off: the
## closest. Read off the squad's LEADER.
@export var picks_best_trade := true
## A kill that ends the mission outranks everything (ruling 2 on #117).
@export var goes_for_mission_kill := true
## What its own attack may do to its own side.
@export var friendly_fire: FriendlyFire = FriendlyFire.NEVER_DOWNS
## Damage taken from the counters it draws is the last tie-break.
@export var weighs_counters := true
## Values knocking an enemy out of its squad, and avoids having its own split.
@export var values_splits := true
## One step of lookahead, so a member opens a set-up (a soak) for a squadmate's follow-up.
@export var sets_up_combos := true
## A healer stabilises a downed ally nobody can rescue this turn (ruling 16).
@export var stabilises_bodies := true
## How far it goes looking for an opportunity.
@export var seeks: Seek = Seek.KILLS_AND_SPLITS
## A member with nobody to hit walks over to rescue a downed squadmate (ruling 12).
@export var rescue_walk := true
## A unit with nothing to fire backs off out of reach (ruling 5).
@export var backs_off_when_dry := true
## Won't end a move on fire or in a hostile watch while a safe cell offers the same, unless the
## hazard cell offers a kill (rulings 15 and 19).
@export var avoids_hazards := true
## Its moves take the route that wakes the fewest of your watches (#920). Off: the shortest.
@export var routes_around_watches := true
## A hit that would set off an armed unit's Crisis is priced as the damage it really does, never a
## removal.
@export var sees_crisis := true
## Taking a limb ranks above damage, and a counter that would take one of its own counts against it.
@export var values_limbs := true
## A loose unit rejoins its old squad, or the nearest with room, and walks back when idle.
@export var regroups := true
## Loose units may form a new squad together.
@export var squads_up := true
## A regrouping unit may join a squad of another archetype (and takes that squad's archetype).
@export var joins_any_archetype := false
