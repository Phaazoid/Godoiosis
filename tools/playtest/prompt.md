You are playtesting a tactical RPG through a headless text bridge. Play as well as you can.

The game is a Godot project at the repo root. Read `docs/play-api.md` first — it describes the
bridge, the command vocabulary and the board rendering. Everything you can do is documented there.

To start the bridge:

    /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s play/play_bridge.gd

It polls `playrun/command.json` and writes each response to `playrun/state.txt`. Send a command by
writing JSON with a monotonically increasing `id`, then read `state.txt` back once that `id` appears:

    {"id": 1, "cmd": "load", "args": {"path": "res://Scenarios/missions/Level_1.tres"}}

YOUR TASK

Play `res://Scenarios/missions/Level_1.tres` as the PLAYER faction. Try to win.

STOP when either of these is true:
  - the mission ends (you win or lose), or
  - you have completed 8 PLAYER turns.

Then stop and write a short report: what you were trying to do, what worked, and anything about the
interface that made playing harder than it needed to be.

Do not modify any files in the repository. You are playing the game, not developing it.
