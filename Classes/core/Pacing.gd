extends Object
class_name Pacing

# How long turn playback PAUSES so a human can read it (#118). A tuning table in the shape of
# UiLayers -- five numbers, one reader each, named beside each other so they can be tuned as a set
# instead of hunted across four files. Not a system: nothing here decides anything.
#
# Execution is pure playback of an already-resolved plan (R3), so a beat changes only WHEN frames
# land -- never what the queue claimed or what the resolver computed (Law #2).
#
# Every pause routes through beat(), which is where the headless escape lives. That escape is a
# safety property, not a convenience: OrderExecutor.execute_orders is awaited directly by the
# suite, so a literal timer at an await site would put real wall clock on every case that resolves
# a plan.

const AI_SQUAD_PAN := 0.7     # camera glide from squad to squad -- CameraController.pan_to
const AI_PLAN_READ := 0.6     # AI squad's plan is drawn; hold before it resolves -- AIController
const AI_ACTION := 0.45       # between sequential actions in an AI pass -- OrderExecutor
const PLAYER_ACTION := 0.0    # the same gap on the player's own Execute -- deliberately none (dev, 2026-08-10)
const TURN_HANDOFF := 1.0     # hold at every faction turn start -- game.start_faction_turn

static func beat(host: Node, seconds: float) -> void:
	if seconds <= 0.0 or DisplayServer.get_name() == "headless":
		return
	await host.get_tree().create_timer(seconds).timeout
