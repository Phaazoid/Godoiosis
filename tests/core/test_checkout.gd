# Guard for Classes/core/Checkout (#295) -- "which checkout is this build from?".
#
# Two halves, because neither alone is enough:
#
# 1. The REAL repo, through describe(). That is the only case that proves the thing actually
#    resolves against git's files rather than the shape of a fixture I wrote. It is deliberately
#    asserted as "not UNKNOWN, and shaped like branch @ sha" rather than pinned to a value --
#    same convention as the Build.version() cases in tests/dev/test_bug_report_text.gd: the
#    WIRING is the invariant, the branch name and SHA are content and move every commit.
#
# 2. FIXTURE trees under user://, through describe_at(). The three interesting shapes are all
#    unreachable from whichever checkout the suite happens to be running in: locally .git is a
#    worktree FILE and the ref is loose; in CI .git is a directory and HEAD is detached at a
#    merge commit. A fixture is the only way to cover the ones the run does not happen to be.
#    describe_at() exists for exactly this and is the same code path describe() calls.
#
# Pure static calls -- no nodes built -- so this stays orphan-clean.
extends GdUnitTestSuite

const SHA := "ffb2e397d27b09b5e0ed3ec487cf7f61be2efc5f"
const OTHER_SHA := "0cbc385a1b2c3d4e5f60718293a4b5c6d7e8f901"

var _root := ""


func before_test() -> void:
	_root = ProjectSettings.globalize_path("user://").path_join("checkout_fixture")
	_wipe()
	# Prove the wipe rather than trusting it. A leaked tree does not fail loudly -- it makes the
	# next case assert against the PREVIOUS case's fixture, which is how the hidden-file difference
	# below reached CI looking like an unrelated null.
	assert_bool(DirAccess.dir_exists_absolute(_root)).is_false()
	DirAccess.make_dir_recursive_absolute(_root)


func after_test() -> void:
	_wipe()


# ---- the real repo (the only case that touches git) ----

func test_the_running_checkout_resolves_against_real_git_files() -> void:
	# Not vacuous: the gate is what makes describe() answer at all, and without this assertion a
	# suite running outside a dev build would pass on "" forever.
	assert_bool(DevTools.enabled()).is_true()

	var stamp := Checkout.describe()
	# The whole point of the feature: UNKNOWN means git was there and could not be read, which is
	# the failure this case exists to catch. It holds in all three shapes the suite ever runs in --
	# this worktree (.git is a file, loose ref), a plain clone, and CI's detached merge commit.
	assert_str(stamp).is_not_equal(Checkout.UNKNOWN)
	assert_str(stamp).contains(" @ ")

	var sha: String = stamp.split(" @ ")[1]
	# The LITERAL 7, not Checkout.SHORT_SHA: a guard that reads the same constant it checks is
	# circular, and this one is the reason the readout is glanceable rather than a wall of hex.
	assert_int(sha.length()).is_equal(7)
	assert_bool(sha.is_valid_hex_number(false)).is_true()


func test_the_answer_is_stable_within_the_process() -> void:
	# It names the build that was LOADED, so two surfaces asking at different moments (the overlay
	# at _ready, a report filed minutes later) can never disagree.
	assert_str(Checkout.describe()).is_equal(Checkout.describe())


# ---- fixture trees: the shapes this run is not in ----

func test_a_plain_checkout_reads_a_loose_ref() -> void:
	_dir(".git")
	_write(".git/HEAD", "ref: refs/heads/main\n")
	_write(".git/refs/heads/main", SHA + "\n")

	assert_str(Checkout.describe_at(_root)).is_equal("main @ ffb2e39")


func test_a_worktree_follows_the_gitdir_file_and_the_shared_common_dir() -> void:
	# The shape EVERY parallel-agent checkout is in: .git is a file, HEAD lives in the pointed-at
	# gitdir, and refs/heads/* live two levels up in the common dir. A naive read of
	# <root>/.git/HEAD finds nothing here, which is the bug this case forbids.
	_write(".git", "gitdir: %s\n" % _root.path_join("main/.git/worktrees/slug"))
	_dir("main/.git/worktrees/slug")
	_write("main/.git/worktrees/slug/HEAD", "ref: refs/heads/feature/295-build-readout\n")
	_write("main/.git/worktrees/slug/commondir", "../..\n")
	_write("main/.git/refs/heads/feature/295-build-readout", SHA + "\n")

	assert_str(Checkout.describe_at(_root)).is_equal("feature/295-build-readout @ ffb2e39")


func test_a_packed_ref_resolves_when_no_loose_file_exists() -> void:
	_dir(".git")
	_write(".git/HEAD", "ref: refs/heads/main\n")
	_write(".git/packed-refs",
		"# pack-refs with: peeled fully-peeled sorted \n"
		+ "%s refs/heads/main\n" % SHA
		+ "%s refs/remotes/origin/main\n" % SHA)

	assert_str(Checkout.describe_at(_root)).is_equal("main @ ffb2e39")


func test_a_loose_ref_beats_a_stale_packed_one() -> void:
	# git's own precedence, and not hypothetical: the dev's tree carries a loose refs/heads/main
	# AND a packed entry days behind it, so reading packed-refs first reports the wrong build.
	_dir(".git")
	_write(".git/HEAD", "ref: refs/heads/main\n")
	_write(".git/refs/heads/main", SHA + "\n")
	_write(".git/packed-refs", "%s refs/heads/main\n" % OTHER_SHA)

	assert_str(Checkout.describe_at(_root)).is_equal("main @ ffb2e39")


func test_a_detached_head_says_so_rather_than_naming_a_branch() -> void:
	# CI's own shape on a pull_request: actions/checkout lands on the merge commit, not a branch.
	_dir(".git")
	_write(".git/HEAD", SHA + "\n")

	assert_str(Checkout.describe_at(_root)).is_equal("detached @ ffb2e39")


# ---- degrading VISIBLY, which is the whole contract ----

func test_no_git_at_all_says_unknown_rather_than_going_blank() -> void:
	# An exported devtools build is exactly this: dev tools on, no repo underneath. A blank readout
	# would be indistinguishable from a working one showing nothing, which is the failure mode the
	# feature exists to remove.
	assert_str(Checkout.describe_at(_root)).is_equal(Checkout.UNKNOWN)


func test_an_unresolvable_ref_still_names_the_branch() -> void:
	# Half an answer beats none: the branch is the half that identifies the work.
	_dir(".git")
	_write(".git/HEAD", "ref: refs/heads/main\n")

	assert_str(Checkout.describe_at(_root)).is_equal("main @ %s" % Checkout.UNKNOWN)


func test_a_ref_holding_something_that_is_not_a_sha_never_reaches_the_screen() -> void:
	# A symref or a truncated file must not be printed under a label the dev is meant to trust.
	_dir(".git")
	_write(".git/HEAD", "ref: refs/heads/main\n")
	_write(".git/refs/heads/main", "ref: refs/heads/other\n")

	assert_str(Checkout.describe_at(_root)).is_equal("main @ %s" % Checkout.UNKNOWN)


func test_a_gitdir_file_pointing_nowhere_says_unknown() -> void:
	_write(".git", "gitdir: %s\n" % _root.path_join("gone/.git/worktrees/slug"))

	assert_str(Checkout.describe_at(_root)).is_equal(Checkout.UNKNOWN)


# ---- fixture plumbing ----

func _dir(relative: String) -> void:
	DirAccess.make_dir_recursive_absolute(_root.path_join(relative))


func _write(relative: String, text: String) -> void:
	var path := _root.path_join(relative)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_object(file).is_not_null()
	if file == null:
		return
	file.store_string(text)
	file.close()


func _wipe() -> void:
	_wipe_at(_root)


func _wipe_at(dir: String) -> void:
	var access := DirAccess.open(dir)
	if access == null:
		return
	# EVERY fixture path here starts with a dot, and hidden is a PLATFORM question: ".git" is hidden
	# on Linux and not on Windows, so without this the wipe silently no-ops on CI and each case
	# inherits the previous one's tree. Found by CI reddening a case that is green on Windows.
	access.include_hidden = true
	for file: String in access.get_files():
		DirAccess.remove_absolute(dir.path_join(file))
	for sub: String in access.get_directories():
		_wipe_at(dir.path_join(sub))
	DirAccess.remove_absolute(dir)
