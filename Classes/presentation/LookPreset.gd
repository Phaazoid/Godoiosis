extends Resource
class_name LookPreset

# A saved capture of the Moods tab's scene-mood knobs (#253 part 1): the named moods the dev
# tunes, saves and loads back, replacing the clipboard as the way a look survives a session.
#
# DUMB DATA on purpose. Capturing and applying both need LookKnobs.KNOBS -- the one authority on
# which property a knob names -- so that logic lives beside the table, not here. This file is
# what goes on disk and nothing more.
#
# It lives in presentation/ rather than dev/ because #253 part 2 hangs a reference to this type
# off ScenarioData, a shipping resource; a shipping resource pointing into Classes/dev/ is the
# wrong direction.
#
# `values` is keyed by LookKnobs.preset_key(knob) -- "<node>|<prop>", e.g. "Sun|light_energy" --
# NEVER by the property path itself. KNOBS answers "which property is Sun energy"; a preset
# carrying the path would be a second answer to that, so renaming a property would mean editing
# every preset file instead of one table row (Law #4).

@export var preset_name := ""
@export var values: Dictionary = {}   # LookKnobs.preset_key(knob) -> the captured value
