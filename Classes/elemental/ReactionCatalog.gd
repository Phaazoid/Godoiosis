extends Object
class_name ReactionCatalog

# All elemental reactions the resolver considers, authored as .tres data and edited
# in the Godot inspector (Resources/Reactions/). Mirrors WeaponCatalog's variant scan.
# Files are sorted so discovery order is deterministic (R2) — though E8 composition
# is order-independent anyway, so order never changes an outcome.
#
# The scan is CACHED (#1213), JobCatalog's shape for JobCatalog's reason: this is every resolve's
# default argument, and this scan plus TerrainReactionCatalog's measured 7.2 ms per call. Reaction files change
# between runs; anything that adds or removes one at runtime -- a tool, or a test -- calls refresh().

const REACTION_DIR := "res://Resources/Reactions/"

# How many times the folder was actually read -- the cache's one observable, since "faster" has no
# behaviour a case could see (#710 slice 2's law). docs/performance.md quotes it.
static var scans := 0

static var _cache: Array[ElementalReaction] = []
static var _scanned := false

# A COPY of the cached list: a caller appending to what it was handed must not change everyone's.
static func get_all() -> Array[ElementalReaction]:
	if not _scanned:
		_cache.assign(ResourceCatalog.load_all(REACTION_DIR, ElementalReaction))
		_scanned = true
		scans += 1
	return _cache.duplicate()

static func refresh() -> void:
	_scanned = false
