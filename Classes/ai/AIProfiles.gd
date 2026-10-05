extends Object
class_name AIProfiles

# "Which AI profile does this unit play, and what does this NAME point at?" (#1230). A unit carries
# a profile by FILE NAME (Unit.ai_profile, authored on ScenarioUnitEntry), never by reference -- the
# look_preset / roster rule: a dangling ext_resource kills the whole scenario load, and a Resource
# field risks embedding. The filename IS the identity, as it is for a look preset or a roster.
#
# An unassigned unit ("") plays Hard, and so does a name that no longer resolves -- BoardLint
# reports the second as BLOCKS, since substituting Hard hands the player a different mission.

const PROFILE_DIR := "res://Resources/AIProfiles/"
const DEFAULT_NAME := "Hard"
# The shipped bands, listed first wherever a profile is picked; anything else in the folder is a
# bespoke profile (a boss).
const BANDS: Array[String] = ["Easy", "Medium", "Hard"]

# How many times the folder was actually read -- the cache's one observable (#1213's shape).
static var scans := 0

static var _cache := {}   # name -> AIProfile
static var _scanned := false

# Test fixtures, consulted before disk. The key "" sets what an unassigned unit plays. Every AI
# suite declares one (tests/law/test_ai_suites_declare_a_profile.gd), so a retune of the shipped
# bands can never redden a case that is about something else.
static var _fixtures := {}


# Every profile in the folder, the bands first in their own order, the rest sorted. The dropdown's
# source and the lint's, so a name the editor offers is always a name the lint accepts.
static func names() -> Array[String]:
	_scan()
	var out: Array[String] = []
	for band in BANDS:
		if _cache.has(band):
			out.append(band)
	var rest: Array[String] = []
	for name: String in _cache:
		if not BANDS.has(name):
			rest.append(name)
	rest.sort()
	out.append_array(rest)
	return out


# The profile `name` points at, or null when it names nothing ("" included). Fixtures first.
static func resolve(name: String) -> AIProfile:
	if _fixtures.has(name):
		return _fixtures[name]
	if name == "":
		return null
	_scan()
	return _cache.get(name, null)


# What `unit` plays: its named profile, else what an unassigned unit plays (a test's "" fixture,
# else Hard). A name that resolves to nothing plays the same as no name.
static func of(unit: Unit) -> AIProfile:
	var profile := resolve(unit.ai_profile)
	if profile == null:
		profile = resolve("")
	if profile == null:
		_scan()
		profile = _cache.get(DEFAULT_NAME, null)
	return profile if profile != null else AIProfile.new()


static func use_fixtures(fixtures: Dictionary) -> void:
	_fixtures = fixtures.duplicate()


static func clear_fixtures() -> void:
	_fixtures = {}


static func refresh() -> void:
	_scanned = false


static func _scan() -> void:
	if _scanned:
		return
	_cache = {}
	for file: String in ResourceDir.files_with_extension(PROFILE_DIR, ".tres"):
		var profile := load(PROFILE_DIR + file) as AIProfile
		if profile != null:
			_cache[file.trim_suffix(".tres")] = profile
	_scanned = true
	scans += 1
