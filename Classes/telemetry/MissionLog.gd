extends Node
class_name MissionLog

# THE RECORDER (#53): one JSONL file per mission run, appended as the battle goes and sealed at the
# end. Built in game._build_collaborators with a back-ref -- the DevController/OrderExecutor
# pattern -- and it OWNS NO RULE: every line is a fact read off something that already decided it
# (a ResolvedPlan, a signal, a MissionController field), written down once. MissionSummary is the
# projection over it; TelemetryStore is the only file that knows a path.
#
# WHAT IT LISTENS TO vs WHAT IT IS TOLD. Turn starts, orders queued and cancelled, downs and deaths
# all ride signals that already exist, connected in _ready. Five things are explicit calls, because
# no signal carries them: begin() at MissionController._begin_turn (the one door every arrival
# takes), record_pass() at OrderExecutor's one resolved pass, record_turn_effects() at its
# end-of-turn burn (the one damage channel no plan and no signal holds), record_capture(), and
# seal() at the three named exits.
#
# THE FIRST turn_start IS WRITTEN BY begin(), not by the signal: TurnManager.turn_started fires
# only from end_turn, never from start_faction_turn, so a recorder riding the signal alone loses
# every mission's baseline (Fable, 2026-09-07). The signal covers turns 2..n, and its handler runs
# BEFORE game._on_turn_started's ticks -- connected first -- so a snapshot is the board as the
# previous turn left it, and a clock-expiry death lands in the next one.
#
# APPENDED AND FLUSHED PER LINE, so an unsealed file on disk is a complete log up to the moment the
# process died. That IS the quit record: Alt-F4, a crash, an F2 swap all leave one, and begin()
# seals any still-open run as INTERRUPTED before starting the next. The three named exits seal
# explicitly only so the outcome carries its right name -- a restart is a metric of its own.
#
# Enum values are written as NAMES, never ints; names survive reordering across builds. Every line
# carries seq, t_ms since mission start, and the round it happened in. A unit is named by its
# instance id (stable for the run, unique in the process) beside its display name: a node name
# can change under a reparent and a display name can be shared by two Brigands.
#
# Headless it records in memory and writes nothing (TelemetryStore.persistence_enabled), which is
# how the suite drives it. Events with no open run are DROPPED: after STAY at the end banner the
# board unlocks for inspection and the queue signals keep firing.

enum Ending { VICTORY, DEFEAT, ABANDONED, RESTARTED, INTERRUPTED }

var game   # the Game coordinator; set by game._ready()

# One id per process, so the runs of one sitting can be grouped offline.
static var session_id := ""

var _events: Array[Dictionary] = []
# The last order this stream recorded, by INSTANCE ID rather than by reference: a freed object
# compares == null as TRUE and a typed read of one dies outright, so an int is the only form of
# this that cannot dangle.
var _last_order_id := 0

var _file: FileAccess = null
var _run_id := ""
var _seq := 0
var _started_ms := 0
var _open := false
var _dev_touched := false   # a dev tool moved this board; see note_dev_intervention


func _ready() -> void:
	if session_id == "":
		session_id = TelemetryStore.new_id()
	game.turn_manager.turn_started.connect(_on_turn_started)
	game.squad_manager.squad_action_queued.connect(_on_order_queued)
	game.squad_manager.squad_action_cancelled.connect(_on_order_cancelled)
	# Every spawn makes a solo squad (tools/replay_battle.gd's trick), so the unit hooks attach here
	# without a second walk over the board -- reinforcements included.
	game.squad_manager.squad_created.connect(_on_squad_created)
	# THE PLAYER'S SQUAD DECISION (#53 slice 2). Squad Up and Join BOTH commit through
	# SquadManager.join_squad, and this signal is clean MID-RUN precisely because its other callers
	# -- the #763 staged rejoin and ScenarioManager's load rebuild -- both run BEFORE begin() opens
	# a run, so _record drops them for free.
	#
	# `squad_created` is NOT the twin of this and must never be used as one: create_squad has six
	# callers (spawn, deploy, leave, disband-per-member, the squad-up verb, the headless builder),
	# so it means "a solo squad now exists" and would log a leave as a squad-up.
	game.squad_manager.squad_member_joined.connect(_on_squad_joined)
	# The gear ACT, forwarded up from inventory_panel's one funnel.
	game.unit_info_panel.loadout_acted.connect(_on_loadout_acted)


func is_open() -> bool:
	return _open


func run_id() -> String:
	return _run_id


# A COPY, for the suite and the sweep: nothing outside may append.
func events() -> Array[Dictionary]:
	return _events.duplicate()


# ==============================================================================
#  Begin / seal
# ==============================================================================

# EVERY arrival records, and what would once have been EXCLUDED is FLAGGED instead (dev,
# 2026-09-08: *"instead of ignoring dev mode play, I think it should get a special flag, so that we
# know to separate it in the data"*). So a sandbox board is recorded with `sandbox: true` rather
# than dropped -- nothing is lost, and a query separates it with a WHERE clause.
#
# The cost is stated rather than hidden: a sandbox run has NO scenario, so it cannot be grouped by
# mission and every per-level query has to exclude it explicitly.
#
# A resume is flagged the same way -- it arrives mid-battle with no draw.
# `record_to_disk` false records the run IN MEMORY only -- no file, no board snapshot. That is the
# REPLAY driver's mode (#53 slice 4): a replay must be measured by this same recorder, so that its
# events and the recorded run's are like-for-like, while writing nothing that would look like a new
# playtest run. _record already appends to _events regardless of whether a file is open, which is
# what makes the mode cost one parameter rather than a second recorder.
func begin(record_to_disk := true) -> void:
	if _open:
		seal(Ending.INTERRUPTED)
	_events.clear()
	_seq = 0
	_last_order_id = 0
	_dev_touched = false
	_started_ms = Time.get_ticks_msec()
	_run_id = _stamp() + "_" + TelemetryStore.new_id().substr(0, 8)
	_open = true
	_file = TelemetryStore.open_run_file(_run_id) if record_to_disk else null
	# The REPLAY SEED, beside the events: the roster line below is the queryable denominator, this
	# is the machine-exact state. A declared duplication -- two questions, two answers.
	#
	# GATED HERE AS WELL AS INSIDE save_board, and the two guards answer different questions: that
	# one is CORRECTNESS (a headless run writes nothing), this one is COST -- capture_scenario walks
	# the whole board, and without it every mission start in the suite builds a snapshot that is
	# then discarded. Pacing.beat's headless escape, one layer up.
	if record_to_disk and TelemetryStore.persistence_enabled:
		TelemetryStore.save_board(_run_id, game.scenario_manager.capture_scenario("telemetry-" + _run_id))
	_record("mission_start", _mission_start_fields())
	_record("turn_start", _turn_fields(game.turn_manager.active_faction()))


func seal(ending: Ending, failed_by: MissionRules.LoseCondition = MissionRules.LoseCondition.NONE) -> void:
	if not _open:
		return
	_record("mission_end", {
		"outcome": Ending.keys()[ending],
		"failed_by": MissionRules.LoseCondition.keys()[failed_by],
		"seconds": (Time.get_ticks_msec() - _started_ms) / 1000.0,
		"dev_touched": _dev_touched,   # true = do not trust a replay of this run
		"units": _board_vitals(),
	})
	_record("summary", {"summary": MissionSummary.of(_events)})
	_open = false
	if _file != null:
		_file.close()
		_file = null


# ==============================================================================
#  The explicit hooks
# ==============================================================================

# The whole pass, read off the two things that hold it: the queue (moves and the side-channel
# verbs carry no outcome and are NOT on the plan) and the ResolvedPlan (every hit that lands).
func record_pass(squad: Squad, plan: ResolvedPlan) -> void:
	if not _open:
		return
	var orders: Array[Dictionary] = []
	for action: BaseAction in squad.action_queue:
		orders.append(_order(action))
	var hits: Array[Dictionary] = []
	for atk: AttackAction in plan.attacks:
		hits.append(_hit("attack", atk))
	for ctr: CounterAttackAction in plan.counters:
		hits.append(_hit("counter", ctr))
	for shot: AttackAction in plan.watch_shots:
		hits.append(_hit("watch_shot", shot))
	var effects: Array[Dictionary] = []
	for effect: ResolvedCellEffect in plan.cell_effects:
		effects.append({
			"cell": _cell(effect.cell),
			"added": _names(Terrain.TileState, effect.states_added),
			"removed": _names(Terrain.TileState, effect.states_removed),
		})
	_record("pass", {
		"squad": _squad_ref(squad),
		"faction": _faction_name(squad.leader),
		"orders": orders,
		"hits": hits,
		"cell_effects": effects,
	})


func record_turn_effects(faction: Team.Faction, hits: Array[TileHitAction]) -> void:
	if not _open:
		return
	var rows: Array[Dictionary] = []
	for hit: TileHitAction in hits:
		rows.append({
			"unit": _ref(hit.actor),
			"state": Terrain.TileState.keys()[hit.state],
			"damage": hit.resolved.damage,
			"lethality": ResolvedOutcome.Lethality.keys()[hit.resolved.lethality],
		})
	_record("turn_effects", {"faction": Team.Faction.keys()[faction], "hits": rows})


func record_capture(zone_name: String) -> void:
	_record("zone_captured", {"zone": zone_name})


# LEAVE and DISBAND, called from the menu arms that own those verbs (#53 slice 2). Deliberately NOT
# hooked inside SquadManager: leave_squad has four automatic callers there (the contact sweep, the
# leader reassign, the downed handling), and an ejection is a CONSEQUENCE a replay re-derives, not
# a decision it has to be told. Join needs no entry here -- it rides squad_member_joined.
func record_squad_verb(verb: String, unit: Unit) -> void:
	_record("squad_verb", {"verb": verb, "unit": _ref(unit), "squad": _squad_ref(unit.squad)})


# A DEV TOOL TOUCHED THIS BOARD, so a replay of this run must not be trusted (#53 slice 2). A FLAG
# rather than an event stream, deliberately: the goal is only that a replay can never diverge
# SILENTLY, and per-intervention recording is a declared deferral. Sticky for the rest of the run.
func note_dev_intervention() -> void:
	_dev_touched = true


# ==============================================================================
#  The signal side
# ==============================================================================

func _on_turn_started(faction: Team.Faction) -> void:
	_record("turn_start", _turn_fields(faction))


func _on_order_queued(squad: Squad, action: BaseAction) -> void:
	# A HOLD-POSITION FILLER IS NOT AN ORDER ANYBODY GAVE, and batch_id is the project's own answer
	# to that -- stamped only by queue_action, the Law #3 chokepoint, so 0 means a filler that
	# game.gd's own signal handler queued direct. Counting them would put one phantom order per
	# squadmate per plan into the churn metric this event exists FOR.
	#
	# Nothing is lost by dropping them here: the `pass` record writes the whole queue, fillers
	# included and flagged `hold`. This stream is what a PERSON authored.
	if action.batch_id == 0:
		return
	# ...AND THE SAME ORDER IS NOT TWO ORDERS. queue_group_move RE-EMITS this signal for the batch's
	# LAST member ("so listeners do their squad-level repaint exactly once") -- the same object that
	# already arrived through Squad.action_queued. That re-emit is deliberate and the repainting
	# listeners need it, so the dedupe belongs HERE, in the one listener that COUNTS rather than
	# redraws: without it the churn metric scores every group move as N+1 orders.
	if action.get_instance_id() == _last_order_id:
		return
	_last_order_id = action.get_instance_id()
	_record("order_queued", {
		"squad": _squad_ref(squad),
		"faction": _faction_name(action.actor),
		"order": _order(action),
		"during_pass": game.order_executor.executing_plan != null,
	})


func _on_order_cancelled(squad: Squad, unit: Unit, actiontype: BaseAction.ActionType) -> void:
	_record("order_cancelled", {
		"squad": _squad_ref(squad),
		"faction": _faction_name(unit),
		"unit": _ref(unit),
		"type": BaseAction.ActionType.keys()[actiontype],
		"during_pass": game.order_executor.executing_plan != null,
	})


func _on_squad_joined(squad: Squad, unit: Unit) -> void:
	_record("squad_verb", {"verb": "join", "unit": _ref(unit), "squad": _squad_ref(squad)})


func _on_loadout_acted(unit: Unit, verb: String, index: int) -> void:
	# The ACT, never the resulting state: a replay applies it through the same door the player used
	# (equip_weapon_from_inventory and friends), where a state blob would be a side-channel write.
	_record("gear", {"unit": _ref(unit), "verb": verb, "index": index})


func _on_squad_created(squad: Squad) -> void:
	var unit: Unit = squad.leader
	if unit == null:
		return
	if not unit.went_downed.is_connected(_on_unit_downed):
		unit.went_downed.connect(_on_unit_downed)
	if not unit.unit_died.is_connected(_on_unit_died):
		unit.unit_died.connect(_on_unit_died)


func _on_unit_downed(unit: Unit) -> void:
	_record("unit_downed", _vitals(unit))


func _on_unit_died(unit: Unit) -> void:
	_record("unit_died", _vitals(unit))


# ==============================================================================
#  The line
# ==============================================================================

func _record(kind: String, fields: Dictionary) -> void:
	if not _open:
		return
	var line := {
		"seq": _seq,
		"t_ms": Time.get_ticks_msec() - _started_ms,
		"round": game.mission_controller.rounds_elapsed() + 1,
		"event": kind,
	}
	_seq += 1
	line.merge(fields)
	_events.append(line)
	if _file != null:
		_file.store_line(JSON.stringify(line))
		_file.flush()


# ==============================================================================
#  Readers -- facts off the live board, each written once
# ==============================================================================

func _mission_start_fields() -> Dictionary:
	var sm: ScenarioManager = game.scenario_manager
	var mc: MissionController = game.mission_controller
	var path: String = sm.last_loaded_path
	var roster: Array[Dictionary] = []
	var deployed: Array[Unit] = game._all_units()
	for unit: Unit in deployed:
		roster.append(_roster_entry(unit, true))
	var reserve: Array[Node] = game.reserve_root.get_children()
	for node: Node in reserve:
		roster.append(_roster_entry(node as Unit, false))
	var loadout: Loadout = mc.loadout()
	var stash: Array[String] = []
	for item: Item in loadout.stash:
		if item != null:
			stash.append(item.display_name)
	var mods: Array[String] = []
	for mod: WeaponModData in loadout.available_mods:
		if mod != null:
			mods.append(mod.display_name)
	return {
		"run_id": _run_id,
		"install_id": TelemetryStore.install_id(),
		"session_id": session_id,
		"build": Build.version(),
		"checkout": Checkout.describe(),
		"dev_build": DevTools.enabled(),
		"dev_mode": game.dev_mode_enabled,
		"started_at": Time.get_datetime_string_from_system(true),
		"scenario": path,
		"scenario_name": path.get_file().get_basename(),
		# NO mission behind this board -- the sandbox, or a dev-tools load. Its own field rather
		# than an empty `scenario` read as one, so the separation is explicit at the query.
		"sandbox": path == "",
		"roster_name": sm.current_roster,
		"deployment_cap": sm.current_deployment_cap,
		"objectives": _names(MissionRules.Objective, mc.objectives),
		"lose_conditions": _names(MissionRules.LoseCondition, mc.lose_conditions),
		"round_limit": mc.round_limit,
		"resumed": mc.rounds_elapsed() > 0,
		"roster": roster,
		"stash": stash,
		"available_mods": mods,
	}


# Everything a unit brought: the denominator every usage metric needs.
func _roster_entry(unit: Unit, deployed: bool) -> Dictionary:
	var stats := {}
	for stat: Stats.Stat in Stats.Stat.values():
		stats[Stats.Stat.keys()[stat]] = unit.get_effective_stat(stat)
	# A NULL IS AN EMPTY SLOT, not a hole: `inventory` is fixed-size and add_item fills the first
	# null it finds, so skipping them is reading the store's own vocabulary.
	var items: Array[String] = []
	for item: Item in unit.inventory:
		if item != null:
			items.append(item.display_name)
	var entry := _ref(unit)
	entry.merge({
		"faction": _faction_name(unit),
		"deployed": deployed,
		"cell": _cell(unit.movement.cell) if deployed else null,
		"squad": _squad_ref(unit.squad),
		"jobs": unit.unit_instance.jobs.duplicate(),
		"weapon": _weapon(unit.equipped_weapon),
		"armor": unit.worn_armor.display_name if unit.worn_armor != null else null,
		"items": items,
		"stats": stats,
		"hp_max": unit.get_max_hp(),
		"will_max": unit.unit_instance.get_max_will(),
	})
	return entry


func _weapon(weapon: EquippableData) -> Variant:
	if weapon == null:
		return null
	if weapon is WeaponInstance:
		var inst := weapon as WeaponInstance
		var mods: Array[String] = []
		for space: Array in inst.spaces:
			for mod: WeaponModData in space:
				if mod != null:
					mods.append(mod.display_name)
		var has_template := inst.template != null
		return {
			"name": inst.template.display_name if has_template else inst.display_name,
			"family": WeaponData.WeaponType.keys()[inst.template.weapon_type] if has_template else "",
			"mods": mods,
		}
	return {"name": weapon.display_name, "family": "", "mods": []}


func _turn_fields(faction: Team.Faction) -> Dictionary:
	return {"faction": Team.Faction.keys()[faction], "units": _board_vitals()}


func _board_vitals() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var units: Array[Unit] = game._all_units()
	for unit: Unit in units:
		rows.append(_vitals(unit))
	return rows


func _vitals(unit: Unit) -> Dictionary:
	var row := _ref(unit)
	row.merge({
		"faction": _faction_name(unit),
		"hp": unit.get_current_hp(),
		"hp_max": unit.get_max_hp(),
		"will": unit.unit_instance.get_current_will(),
		"will_max": unit.unit_instance.get_max_will(),
		"state": Unit.LifecycleState.keys()[unit.lifecycle_state],
		"crisis": unit.in_crisis,
		"states": _names(Elemental.State, unit.element_states),
		"cell": _cell(unit.movement.cell),
		"squad": _squad_ref(unit.squad),
	})
	return row


func _order(action: BaseAction) -> Dictionary:
	var row := {
		"unit": _ref(action.actor),
		"type": BaseAction.ActionType.keys()[action.action_type],
		"batch": action.batch_id,
	}
	match action.action_type:
		BaseAction.ActionType.MOVE:
			var move := action as MoveAction
			row["to"] = _cell(move.destination)
			row["hold"] = move.is_hold_position
		BaseAction.ActionType.ATTACK:
			# NO `target`, deliberately: AttackAction.declare passes null and the victims are the
			# RESOLVER's answer (create_volley, at pass time). A queued attack is an aim at a CELL,
			# so the cell is its identity here and who it hit is in the `pass` record.
			var atk := action as AttackAction
			row["at"] = _cell(atk.target_cell)
			row["attack"] = _attack_name(atk.fired_attack)
		BaseAction.ActionType.RESCUE:
			# The HAUL is a cell the PLAYER picked (#116), so it is a decision, not a derivation --
			# without it a replay puts the body somewhere nobody chose. NO_CELL means "no haul", and
			# it serializes as null rather than as a cell that looks real.
			var rescue := action as RescueAction
			row["target"] = _ref(rescue.target)
			row["haul_to"] = _cell(rescue.haul_to) if rescue.haul_to != GridUtils.NO_CELL else null
		BaseAction.ActionType.GUARD:
			row["target"] = _ref((action as GuardAction).target)
		BaseAction.ActionType.INTIMIDATE:
			row["target"] = _ref((action as IntimidateAction).target)
		BaseAction.ActionType.CAPTURE:
			row["zone"] = (action as CaptureAction).zone_name
		BaseAction.ActionType.OVERWATCH:
			var watch := action as OverwatchAction
			row["at"] = _cell(watch.target_cell)
			row["attack"] = _attack_name(watch.fired_attack)
	return row


func _hit(kind: String, atk: AttackAction) -> Dictionary:
	var row := {
		"kind": kind,
		"actor": _ref(atk.actor),
		"target": _ref(atk.target),
		"at": _cell(atk.target_cell),
		"attack": _attack_name(atk.fired_attack),
		"secondary": atk.is_secondary_hit,
	}
	var r: ResolvedOutcome = atk.resolved
	if r == null:
		return row
	var reactions: Array[String] = []
	for reaction: ElementalReaction in r.fired_reactions:
		reactions.append(reaction.popup if reaction.popup != "" else reaction.resource_path.get_file())
	row.merge({
		"damage": r.damage,
		"heal": r.heal_amount,
		"dmg_kind": AttackData.Kind.keys()[r.kind],
		"mitigation": r.mitigation,
		"elements": _names(Elemental.Element, r.elements),
		"reactions": reactions,
		"lethality": ResolvedOutcome.Lethality.keys()[r.lethality],
		"hp_before": r.hp_before,
		"hp_after": r.target_hp_after,
		"knockback": r.knockback_applied,
		"removed": r.removed,
		"fall": r.fall_damage,
		"skipped": r.skipped,
		"blocked_for": _ref(atk.blocked_for) if atk.blocked_for != null else null,
	})
	return row


static func _attack_name(attack: AttackData) -> String:
	return attack.display_name if attack != null else ""


static func _ref(unit: Unit) -> Dictionary:
	if unit == null or not is_instance_valid(unit):
		return {"id": 0, "name": ""}
	return {"id": unit.get_instance_id(), "name": unit.get_unit_name()}


static func _squad_ref(squad: Squad) -> Variant:
	if squad == null or not is_instance_valid(squad) or squad.leader == null:
		return null
	var members: Array[int] = []
	for member: Unit in squad.get_members():
		if member != null and is_instance_valid(member):
			members.append(member.get_instance_id())
	return {"leader": squad.leader.get_instance_id(), "members": members}


static func _cell(cell: Vector2i) -> Array[int]:
	return [cell.x, cell.y]


static func _faction_name(unit: Unit) -> String:
	if unit == null or not is_instance_valid(unit):
		return ""
	return Team.Faction.keys()[unit.get_faction()]


# Enum VALUES to their NAMES. Every enum written here is contiguous from 0, so the value indexes
# the key list directly -- PlayerSettings' own idiom.
static func _names(enum_type: Dictionary, values: Array) -> Array[String]:
	var keys: Array = enum_type.keys()
	var out: Array[String] = []
	for value in values:
		out.append(str(keys[int(value)]))
	return out


static func _stamp() -> String:
	return Time.get_datetime_string_from_system(true).replace(":", "-").replace("T", "_")
