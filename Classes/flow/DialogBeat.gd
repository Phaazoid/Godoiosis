class_name DialogBeat
extends Resource

# One authored dialog moment in a scenario (#182): WHEN it fires (trigger) and WHAT plays (a
# Dialogic timeline). Authored on ScenarioData.dialog_beats -- board content, not code, the
# ai_factions precedent (#150). Fired-state lives in DialogDirector, never here: beats are
# shared resources and must stay replayable across restarts.

enum Trigger {
	MISSION_START,   # a fresh mission begins -- never a resume (see DialogDirector.disarm)
	TURN_START,      # the player's Nth turn begins; N is `turn` below
	SQUAD_FORMED,    # the player forms any squad
}

@export var trigger := Trigger.MISSION_START
@export var turn := 1   # TURN_START only: which player turn fires this (1-based)
@export var timeline: DialogicTimeline
