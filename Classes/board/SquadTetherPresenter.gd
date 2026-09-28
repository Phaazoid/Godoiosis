extends Node
class_name SquadTetherPresenter

# Turns squad MEMBERSHIP CHANGES into tether moments (#367): a join draws the tether in, a voluntary
# leave reels it into the leader, a forced one breaks it, and when leadership passes the old links go
# and the new leader's draw in after them. A game collaborator on the HoverPresenter pattern. It
# decides WHICH moments play; OverlayManager holds them while they do, and SquadLines2D says what they
# look like. A pass's forced exits play at the BLOW rather than at the settle -- see foretell.
#
# It DIFFS rather than reacting per signal, because one call can change membership several times -- a
# leader leaving picks a new leader and may eject members out of the new range -- and handling each
# signal alone would draw a tether to the new leader and then end it in the same frame. So it keeps a
# BASELINE of every member -> leader link (a presentation copy, like UnitMirror's last HP: it advances
# on every flush whether or not anything plays, so it cannot go stale) and asks, once the operation is
# over, which links ended, which began, and why each one ended.
#
# A JOIN flushes at once: join_squad emits last, and Squad Up redraws the squad's tethers in the same
# frame right after, so flushing first is what holds the recruit's tether back from its first frame. A
# LEAVE flushes deferred, because a disband loops and a leader's leave cascades.
#
# LOADING IS INERT: arm() takes the baseline silently, and MissionController calls it where every load
# lands, so a mission's own joins never play.

var game   # the Game coordinator; set by game._build_collaborators

var _live := false
var _links: Dictionary[int, int] = {}   # member instance id -> leader instance id
var _causes: Dictionary[int, int] = {}   # unit instance id -> SquadManager.LeaveCause, this operation
var _flush_queued := false
# Links a pass has already played AT THE BLOW (foretell), which the settle's flush must not play
# again: member id -> the leader it left, and member id -> the leader it joined. Cleared by end_pass.
var _foretold_ends: Dictionary[int, int] = {}
var _foretold_begins: Dictionary[int, int] = {}
# A DEATH (#1104), taken at the death itself because the body is freed before anything asks again:
# unit id -> which look it plays, and unit id -> {"cell", "faction"} where it fell. Every link the death
# ends reads the same look. Cleared with the baseline (arm, reset, end_pass).
var _looks: Dictionary[int, int] = {}
var _gone: Dictionary[int, Dictionary] = {}
# How many deaths the board has seen and the last look, which the derived pick reads (death_look).
var _death_count := 0
var _last_look := -1
# How long this pass's deaths since the last blow was foretold need seen -- what that blow waits for.
var _death_seconds := 0.0


func _ready() -> void:
	var squads: SquadManager = game.squad_manager
	squads.squad_member_joined.connect(_on_joined)
	squads.squad_member_left.connect(_on_left)


# The board is the player's now: take what stands as the baseline, and play whatever changes next.
func arm() -> void:
	_links = _current_links()
	_causes.clear()
	end_pass()
	_death_count = 0
	_last_look = -1
	_live = true


# A board is going away (ScenarioManager.clear_board): nothing it held may play on the next one.
func reset() -> void:
	_live = false
	_links.clear()
	_causes.clear()
	end_pass()
	_death_count = 0
	_last_look = -1
	var overlays: OverlayManager = game.overlay_manager
	overlays.clear_tether_moments()


func is_live() -> bool:
	return _live


func _on_joined(_squad: Squad, _unit: Unit) -> void:
	flush()


func _on_left(_squad: Squad, unit: Unit, cause: SquadManager.LeaveCause) -> void:
	_causes[unit.get_instance_id()] = cause
	if cause == SquadManager.LeaveCause.DEATH:
		_note_death(unit)
	if not _flush_queued:
		_flush_queued = true
		flush.call_deferred()


# A death, taken NOW (#1104): this signal fires inside Unit.die(), before the body is freed, and the
# deferred flush finds it gone. So where it fell, whose side it was and which look it plays are read
# here -- and, while a pass is running, how long the blow that killed it has to wait for what it plays.
# A body with no tether plays nothing and is not counted, so the looks it did not spend stay unspent.
func _note_death(unit: Unit) -> void:
	var id := unit.get_instance_id()
	var led := 0
	for member_id: int in _links:
		if _links[member_id] == id:
			led += 1
	if not _live or (not _links.has(id) and led == 0):
		return
	var cell := unit.movement.cell
	var look := SquadLines2D.death_look(cell, _death_count, _last_look)
	_death_count += 1
	_last_look = look
	_looks[id] = look
	_gone[id] = {"cell": cell, "faction": unit.get_faction()}
	var executor: OrderExecutor = game.order_executor
	if executor == null or executor.executing_plan == null:
		return
	# A leader leaving two or more members hands them to a successor, whose links draw in after it.
	var seconds := SquadLines2D.shown_seconds(look)
	if led >= 2:
		seconds = SquadLines2D.moment_seconds(look) + SquadLines2D.shown_seconds(SquadLines2D.Moment.DRAW_IN)
	_death_seconds = maxf(_death_seconds, seconds)


# Settle the operation: diff the links against the baseline, play what changed, advance the baseline.
# Public so a case can settle a leave without waiting for the deferred call.
func flush() -> void:
	_flush_queued = false
	var now := _current_links()
	if _live:
		_play(now)
	_links = now
	_causes.clear()


func _play(now: Dictionary[int, int]) -> void:
	var links: Array[Dictionary] = []
	var exit_seconds := 0.0
	for member_id: int in _links:
		var leader_id: int = _links[member_id]
		if now.get(member_id, 0) == leader_id:
			continue
		if _consume(_foretold_ends, member_id, leader_id):
			continue
		var moment := _exit_for(member_id, leader_id)
		if moment < 0:
			continue
		var link := _link(member_id, leader_id, moment, 0.0)
		if not link.is_empty():
			links.append(link)
			exit_seconds = maxf(exit_seconds, SquadLines2D.moment_seconds(moment))
	# The dev's "then": a link that begins in the same operation as one that ends waits for it.
	for member_id: int in now:
		var leader_id: int = now[member_id]
		if _links.get(member_id, 0) == leader_id:
			continue
		if _consume(_foretold_begins, member_id, leader_id):
			continue
		var link := _link(member_id, leader_id, SquadLines2D.Moment.DRAW_IN, exit_seconds)
		if not link.is_empty():
			links.append(link)
	if links.is_empty():
		return
	var overlays: OverlayManager = game.overlay_manager
	var board: BoardContext = game._board()
	overlays.play_tether_moments(links, board)


# What an ended link plays, by why it ended. A DEATH at either end wins, with the look it was given
# when it happened (_note_death): the link ended as that body fell, so a leader's every link plays the
# same one -- a member its successor could not hold, and so ejected, included (#1104). Otherwise the
# MEMBER's reason if the member left, else the leader's.
func _exit_for(member_id: int, leader_id: int) -> int:
	for id: int in [member_id, leader_id]:
		if _causes.get(id, -1) == SquadManager.LeaveCause.DEATH:
			return _looks.get(id, -1)
	var cause: int = _causes.get(member_id, _causes.get(leader_id, -1))
	return _exit_moment(cause)


# A voluntary exit reels in and a forced or downed one BREAKS (#367 part 2B); an undeploy is silent,
# and a death is not asked here -- its look was picked when it happened (#1104). -1 is nothing.
static func _exit_moment(cause: int) -> int:
	match cause:
		SquadManager.LeaveCause.VOLUNTARY:
			return SquadLines2D.Moment.REEL_IN
		SquadManager.LeaveCause.FORCED, SquadManager.LeaveCause.DOWNED:
			return SquadLines2D.Moment.BREAK
	return -1


# --- At the blow (#367 part 2B) -----------------------------------------------------------------
# A pass's forced exits settle only once it is over, but the fight that causes them plays long
# before: so the executor hands each blow's outcome here as it lands, and the links the forecast says
# it ends and begins play NOW, in the zoom (the dev's "at the blow"). The settle's flush then finds
# them in the ledger and plays nothing twice. Returns how long those moments need to be seen.
func foretell(outcome: ResolvedOutcome) -> float:
	# A KILL settles mid-blow and its look plays from the flush (_note_death), but the blow still waits
	# for it, as it would for a break (#1104).
	var deaths := _death_seconds
	_death_seconds = 0.0
	if not _live or outcome == null or outcome.relinks.is_empty():
		return deaths
	var live := _current_links()
	var links: Array[Dictionary] = []
	var exit_seconds := 0.0
	var shown := deaths
	for relink in outcome.relinks:
		if not relink.ends or relink.cause == SquadManager.LeaveCause.DEATH \
				or not is_instance_valid(relink.member) or not is_instance_valid(relink.leader):
			continue
		var member_id := relink.member.get_instance_id()
		var leader_id := relink.leader.get_instance_id()
		# Already gone: something settled it before this blow was foretold, and the flush plays it.
		if live.get(member_id, 0) != leader_id:
			continue
		_foretold_ends[member_id] = leader_id
		var moment := _exit_moment(relink.cause)
		if moment < 0:
			continue
		var link := _link(member_id, leader_id, moment, 0.0)
		if not link.is_empty():
			links.append(link)
			exit_seconds = maxf(exit_seconds, SquadLines2D.moment_seconds(moment))
			shown = maxf(shown, SquadLines2D.shown_seconds(moment))
	for relink in outcome.relinks:
		if relink.ends or not is_instance_valid(relink.member) or not is_instance_valid(relink.leader):
			continue
		var member_id := relink.member.get_instance_id()
		var leader_id := relink.leader.get_instance_id()
		if live.get(member_id, 0) == leader_id:
			continue
		_foretold_begins[member_id] = leader_id
		var link := _link(member_id, leader_id, SquadLines2D.Moment.DRAW_IN, exit_seconds)
		if not link.is_empty():
			links.append(link)
			shown = maxf(shown, exit_seconds + SquadLines2D.shown_seconds(SquadLines2D.Moment.DRAW_IN))
	if links.is_empty():
		return deaths
	var overlays: OverlayManager = game.overlay_manager
	var board: BoardContext = game._board()
	overlays.play_tether_moments(links, board)
	return shown


# The pass is over: what it foretold has been settled (or never happened, and must not swallow a
# later, real change to the same link), and its deaths have played.
func end_pass() -> void:
	_foretold_ends.clear()
	_foretold_begins.clear()
	_looks.clear()
	_gone.clear()
	_death_seconds = 0.0


static func _consume(ledger: Dictionary[int, int], member_id: int, leader_id: int) -> bool:
	if ledger.get(member_id, 0) != leader_id:
		return false
	ledger.erase(member_id)
	return true


# One moment's link, strung between where the board draws the two bodies -- the anchor the standing
# tethers use -- and whose squad it was, so an enemy's moment wears the enemy colour (#1109). A body a
# death took answers from where it fell (#1104); any other body that is gone leaves the link empty. A
# death's link also says which end died, and names the one left to flash when a PULSE reaches it.
func _link(member_id: int, leader_id: int, moment: int, delay: float) -> Dictionary:
	var member := _end(member_id)
	var leader := _end(leader_id)
	if member.is_empty() or leader.is_empty():
		return {}
	var faction: Team.Faction = leader["faction"]
	var link := {"from": member["cell"], "to": leader["cell"], "moment": moment, "delay": delay,
			"hostile": SquadLines2D.is_hostile(faction)}
	if SquadLines2D.DEATH_LOOKS.has(moment):
		var leader_died: bool = _causes.get(member_id, -1) != SquadManager.LeaveCause.DEATH
		link["leader_died"] = leader_died
		var survivor := member_id if leader_died else leader_id
		if not _gone.has(survivor):
			link["survivor"] = survivor
	return link


# Where one end of a link stands and whose it is: a body on the board, or one a death took.
func _end(id: int) -> Dictionary:
	var unit := instance_from_id(id) as Unit
	if unit != null and not unit.is_queued_for_deletion():
		return {"cell": unit.get_projected_destination(), "faction": unit.get_faction()}
	return _gone.get(id, {})


# Every member -> leader link on the board: a squad with squadmates, each member but its leader.
func _current_links() -> Dictionary[int, int]:
	var links: Dictionary[int, int] = {}
	var squads: SquadManager = game.squad_manager
	for squad: Squad in squads.squads:
		if not is_instance_valid(squad) or not squad.has_squadmates():
			continue
		var leader := squad.get_leader()
		if leader == null or not is_instance_valid(leader):
			continue
		for member: Unit in squad.get_members():
			if member != leader and is_instance_valid(member):
				links[member.get_instance_id()] = leader.get_instance_id()
	return links
