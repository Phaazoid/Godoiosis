extends Object
class_name Build

# The ONE reader of the build version (#134). The store is project.godot's
# "application/config/version" -- Godot's own field, typed exactly once -- and the rationale lives
# here because project.godot cannot carry comments (Godot strips them on rewrite; see the
# ResourceDir note in CLAUDE.md). Every surface that says which build this is (the in-game corner
# stamp, MissionSelectScreen, BugReporter's report.md and its Discord summary line) comes through
# this function. Law #4: never declare a second version constant in code.

static func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "dev"))
