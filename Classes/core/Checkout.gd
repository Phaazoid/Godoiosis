extends Object
class_name Checkout

# The ONE reader of WHICH CHECKOUT this build came from (#295): "branch @ shortsha", read out of
# git's own files at runtime. A different question from Build.version() (#134), which reads
# project.godot -- a branch's version is deliberately BEHIND main (CLAUDE.md's version-bump rule),
# so it names a release and can never identify a working tree. Two questions, two answers, one
# reader each: Law #4 is broken by a second reader of either fact, not by the second fact existing.
# Every surface that says which checkout is running (battle3d's overlay line, BugReporter's
# report.md and its Discord summary) comes through describe().
#
# Dev-only by construction -- a player has no branch -- so the DevTools gate lives HERE rather than
# at each call site, and describe() answers "" for a build that cannot have a checkout. Each
# surface omits the fact on "" and RENDERS it otherwise; what it must never do is stamp a blank,
# because an absent readout is the state this whole feature exists to make unmistakable.
#
# Resolved ONCE per process. The answer names the checkout the running build was LOADED from, which
# is the fact the issue is about: an agent moving the tree mid-session does not change the code
# already in memory, and a report filed afterwards must not claim a branch that never ran.

const UNKNOWN := "unknown"
const DETACHED := "detached"
const SHORT_SHA := 7

const HEAD_REF := "ref: "
const GITDIR := "gitdir: "
const HEADS := "refs/heads/"

static var _memo := ""

# The one production entry.
static func describe() -> String:
	if not DevTools.enabled():
		return ""
	if _memo == "":
		_memo = describe_at(ProjectSettings.globalize_path("res://"))
	return _memo


# The resolution itself, parameterised by project root so a fixture tree can be pointed at it --
# the worktree and packed-ref branches below are unreachable from the repo the tests run in.
# Uncached and ungated on purpose: describe() owns both.
static func describe_at(root: String) -> String:
	var git := _git_dir(root)
	if git == "":
		return UNKNOWN
	var head := _first_line(git.path_join("HEAD"))
	if head.begins_with(HEAD_REF):
		var ref := head.substr(HEAD_REF.length()).strip_edges()
		var sha := _resolve_ref(_common_dir(git), ref)
		return "%s @ %s" % [ref.trim_prefix(HEADS), _short(sha) if _is_sha(sha) else UNKNOWN]
	if _is_sha(head):
		return "%s @ %s" % [DETACHED, _short(head)]
	return UNKNOWN


# A worktree's .git is a FILE holding "gitdir: <path>", not a directory. That is not an edge case
# here -- every parallel-agent checkout under C:\Iosis\worktrees\ is exactly this shape, and only
# the dev's own Godoiosis has a real .git directory.
static func _git_dir(root: String) -> String:
	var git := root.path_join(".git")
	if DirAccess.dir_exists_absolute(git):
		return git
	var line := _first_line(git)
	if not line.begins_with(GITDIR):
		return ""
	return _absolute(root, line.substr(GITDIR.length()).strip_edges())


# Worktree refs are SHARED: HEAD is per-worktree, but refs/heads/* and packed-refs live in the
# common dir that the "commondir" file points at. Absent = a plain checkout, where they are here.
static func _common_dir(git: String) -> String:
	var line := _first_line(git.path_join("commondir"))
	return git if line == "" else _absolute(git, line)


static func _absolute(base: String, path: String) -> String:
	return path.simplify_path() if path.is_absolute_path() else base.path_join(path).simplify_path()


# Loose beats packed -- git's own precedence, and the dev's own tree has BOTH a loose
# refs/heads/main and a stale packed one, so reading packed-refs first reports a SHA from days ago.
static func _resolve_ref(common: String, ref: String) -> String:
	var loose := _first_line(common.path_join(ref))
	if loose != "":
		return loose
	for line: String in _lines(common.path_join("packed-refs")):
		if line.begins_with("#") or line.begins_with("^"):
			continue
		var parts := line.split(" ", false, 1)
		if parts.size() == 2 and parts[1].strip_edges() == ref:
			return parts[0]
	return ""


static func _first_line(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	return "" if file == null else file.get_line().strip_edges()


static func _lines(path: String) -> PackedStringArray:
	if not FileAccess.file_exists(path):
		return PackedStringArray()
	var file := FileAccess.open(path, FileAccess.READ)
	return PackedStringArray() if file == null else file.get_as_text().split("\n")


static func _short(sha: String) -> String:
	return sha.strip_edges().substr(0, SHORT_SHA)


# Guards every path that prints a SHA: a symref, a truncated file or a stray line must degrade to
# UNKNOWN rather than put garbage on screen under a label the dev is meant to trust.
static func _is_sha(text: String) -> bool:
	return text.length() >= SHORT_SHA and text.is_valid_hex_number(false)
