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


func _ready() -> void:
	var squads: SquadManager = game.squad_manager
	squads.squad_member_joined.connect(_on_joined)
	squads.squad_member_left.connect(_on_left)


# The board is the player's now: take what stands as the baseline, and play whatever changes next.
func arm() -> void:
	_links = _current_links()
	_causes.clear()
	end_pass()
	_live = true


# A board is going away (ScenarioManager.clear_board): nothing it held may play on the next one.
func reset() -> void:
	_live = false
	_links.clear()
	_causes.clear()
	end_pass()
	var overlays: OverlayManager = game.overlay_manager
	overlays.clear_tether_moments()


func is_live() -> bool:
	return _live


func _on_joined(_squad: Squad, _unit: Unit) -> void:
	flush()


func _on_left(_squad: Squad, unit: Unit, cause: SquadManager.LeaveCause) -> void:
	_causes[unit.get_instance_id()] = cause
	if not _flush_queued:
		_flush_queued = true
		flush.call_deferred()


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


# What an ended link plays, by why it ended: the MEMBER's reason if the member left, else the
# leader's.
func _exit_for(member_id: int, leader_id: int) -> int:
	var cause: int = _causes.get(member_id, _causes.get(leader_id, -1))
	return _exit_moment(cause)


# A voluntary exit reels in and a forced or downed one BREAKS (#367 part 2B); a death or an undeploy
# is silent (a death's own effect is #1104). -1 is nothing.
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
	if not _live or outcome == null or outcome.relinks.is_empty():
		return 0.0
	var live := _current_links()
	var links: Array[Dictionary] = []
	var exit_seconds := 0.0
	var shown := 0.0
	for relink in outcome.relinks:
		if not relink.ends or not is_instance_valid(relink.member) or not is_instance_valid(relink.leader):
			continue
		var member_id := relink.member.get_instance_id()
		var leader_id := relink.leader.get_instance_id()
		# Already gone: a KILL settles mid-blow (handle_unit_death), and the ordinary flush plays it.
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
		return 0.0
	var overlays: OverlayManager = game.overlay_manager
	var board: BoardContext = game._board()
	overlays.play_tether_moments(links, board)
	return shown


# The pass is over: what it foretold has been settled (or never happened, and must not swallow a
# later, real change to the same link).
func end_pass() -> void:
	_foretold_ends.clear()
	_foretold_begins.clear()


static func _consume(ledger: Dictionary[int, int], member_id: int, leader_id: int) -> bool:
	if ledger.get(member_id, 0) != leader_id:
		return false
	ledger.erase(member_id)
	return true


# One moment's link, strung between where the board draws the two bodies -- the anchor the standing
# tethers use -- and whose squad it was, so an enemy's moment wears the enemy colour (#1109). Empty
# when either body is gone.
func _link(member_id: int, leader_id: int, moment: int, delay: float) -> Dictionary:
	var member := instance_from_id(member_id) as Unit
	var leader := instance_from_id(leader_id) as Unit
	if member == null or leader == null or member.is_queued_for_deletion() \
			or leader.is_queued_for_deletion():
		return {}
	return {"from": member.get_projected_destination(), "to": leader.get_projected_destination(),
			"moment": moment, "delay": delay, "hostile": SquadLines2D.is_hostile(leader.get_faction())}


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
