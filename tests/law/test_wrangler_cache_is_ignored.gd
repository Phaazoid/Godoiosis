# The wrangler cache must be unreachable by `git add -A` FROM ANYWHERE, because
# .wrangler/cache/wrangler-account.json holds the Cloudflare account id and the owner's email.
#
# WHY THIS EXISTS: the rule has been broken twice, both times by the pattern being PATH-COUPLED and
# neither time by anybody touching it.
#   * #53 slice 5 renamed report-worker -> intake-worker and missed this line, so the cache came
#     back untracked -- one `git add -A` from being published.
#   * #1060 broke it again with no rename at all: wrangler writes .wrangler/cache into the CURRENT
#     directory rather than beside --config, so announcing a release from the repo root created a
#     second cache at a path the anchored rule did not cover.
#
# Nothing else in the suite reads .gitignore, so both failures were invisible to a green run --
# test_boot_scene's situation exactly, and its justification for asserting on a repo file.
#
# It pins the SHAPE rather than gitignore semantics: a leading-slash-free, directory-suffixed
# pattern matches at every depth, and re-anchoring it to any path is the one edit that reintroduces
# both bugs. Reimplementing gitignore matching here would be a second answer to what git already
# decides.
extends GdUnitTestSuite

const GITIGNORE := "res://.gitignore"
const PATTERN := ".wrangler/"


func _lines() -> PackedStringArray:
	var file := FileAccess.open(GITIGNORE, FileAccess.READ)
	assert_object(file).override_failure_message(
			"cannot open %s — it moved, or the test is running outside the repo" % GITIGNORE
			).is_not_null()
	return file.get_as_text().split("\n")


func test_the_wrangler_cache_is_ignored_at_any_depth() -> void:
	var found := false
	for raw in _lines():
		if raw.strip_edges() == PATTERN:
			found = true
			break
	assert_bool(found).override_failure_message(
			("%s has no bare '%s' line. wrangler-account.json carries the Cloudflare account id and " +
			"owner email; without an UNANCHORED rule a cache written from a different working " +
			"directory is committable. See the comment above that line.") % [GITIGNORE, PATTERN]
			).is_true()


# The other half, and the one that actually regresses: a path-coupled spelling coming back. It is
# legal, looks tidier, and is exactly what failed twice.
func test_no_path_anchored_wrangler_rule_has_come_back() -> void:
	var anchored: Array[String] = []
	for raw in _lines():
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		if line.ends_with(PATTERN) and line != PATTERN:
			anchored.append(line)
	assert_array(anchored).override_failure_message(
			("%s carries a path-coupled wrangler rule: %s. That spelling only covers one folder, " +
			"which is how this broke in #53 and again in #1060 -- use the bare '%s'.")
			% [GITIGNORE, str(anchored), PATTERN]
			).is_empty()
