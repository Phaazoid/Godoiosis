# The update check (#1060) at its two pure seams: which of two versions is newer, and what a
# server reply turns into. Both are static and total, which is the point of them being static --
# every case here runs without a network, and the suite can never reach the real endpoint.
#
# WHAT IS DELIBERATELY NOT COVERED: the five lines of HTTPRequest wiring in _fetch. Uploader's
# transport is untested for the same reason and this does not pretend otherwise -- read_payload is
# handed exactly what request_completed produces, so everything downstream of the wire is pinned.
extends GdUnitTestSuite


func _body(text: String) -> PackedByteArray:
	return text.to_utf8_buffer()


# THE CASE A STRING COMPARE GETS BACKWARDS, first because it is the whole reason this is not one:
# "0.188.10" sorts before "0.188.9" as text, so the release that most needs a nag is the one a
# lexical compare would stay silent for.
func test_ten_is_newer_than_nine() -> void:
	assert_bool(VersionCheck.is_newer("0.188.10", "0.188.9")).is_true()
	assert_bool(VersionCheck.is_newer("0.188.9", "0.188.10")).is_false()


func test_newer_across_each_segment() -> void:
	assert_bool(VersionCheck.is_newer("1.0.0", "0.190.5")).is_true()
	assert_bool(VersionCheck.is_newer("0.191.0", "0.190.5")).is_true()
	assert_bool(VersionCheck.is_newer("0.190.6", "0.190.5")).is_true()
	assert_bool(VersionCheck.is_newer("0.190.5", "0.190.5")).is_false()
	assert_bool(VersionCheck.is_newer("0.190.4", "0.190.5")).is_false()


# Zero-filled rather than compared by length, so a shorter version is not automatically older.
func test_missing_segments_are_zero() -> void:
	assert_bool(VersionCheck.is_newer("0.190", "0.190.0")).is_false()
	assert_bool(VersionCheck.is_newer("0.190.0", "0.190")).is_false()
	assert_bool(VersionCheck.is_newer("0.190.1", "0.190")).is_true()
	assert_bool(VersionCheck.is_newer("0.191", "0.190.9")).is_true()


# An unreadable version on either side is never a reason to tell somebody they are out of date.
# "dev" is Build.version()'s own fallback, so this is the editor's normal answer, not a freak case.
func test_unreadable_versions_never_nag() -> void:
	assert_bool(VersionCheck.is_newer("0.191.0", "dev")).is_false()
	assert_bool(VersionCheck.is_newer("dev", "0.190.0")).is_false()
	assert_bool(VersionCheck.is_newer("0.191.0", "")).is_false()
	assert_bool(VersionCheck.is_newer("", "0.190.0")).is_false()
	assert_bool(VersionCheck.is_newer("v0.191.0", "0.190.0")).is_false()
	assert_bool(VersionCheck.is_newer("0.191.0-beta", "0.190.0")).is_false()


func test_payload_reports_a_newer_build() -> void:
	var out := VersionCheck.read_payload(
		200, _body('{"version":"0.191.0","url":"https://example.com/game"}'), "0.190.0")
	assert_dict(out).contains_key_value("version", "0.191.0")
	assert_dict(out).contains_key_value("url", "https://example.com/game")


func test_payload_stays_quiet_when_current() -> void:
	var out := VersionCheck.read_payload(
		200, _body('{"version":"0.190.0","url":"https://example.com/game"}'), "0.190.0")
	assert_dict(out).is_empty()


# Anything but 200 means stay quiet -- including the 404 the Worker answers with before the first
# release has ever been announced.
func test_non_200_stays_quiet() -> void:
	var payload := _body('{"version":"0.191.0","url":"https://example.com/game"}')
	assert_dict(VersionCheck.read_payload(404, payload, "0.190.0")).is_empty()
	assert_dict(VersionCheck.read_payload(500, payload, "0.190.0")).is_empty()


func test_malformed_payloads_stay_quiet() -> void:
	assert_dict(VersionCheck.read_payload(200, _body("not json"), "0.190.0")).is_empty()
	assert_dict(VersionCheck.read_payload(200, _body("[1,2,3]"), "0.190.0")).is_empty()
	assert_dict(VersionCheck.read_payload(200, _body("{}"), "0.190.0")).is_empty()
	assert_dict(VersionCheck.read_payload(
		200, _body('{"version":"0.191.0"}'), "0.190.0")).is_empty()
	assert_dict(VersionCheck.read_payload(
		200, _body('{"url":"https://example.com/g"}'), "0.190.0")).is_empty()


# THE URL IS NOT TRUSTED, because it ends up at OS.shell_open. A payload carrying anything but an
# https:// address is dropped entirely rather than shown with a dead link -- and dropping it is
# what keeps a shell call from ever seeing a scheme somebody else chose.
func test_a_url_that_is_not_https_is_refused() -> void:
	for bad in ["http://example.com/g", "file:///C:/Windows/System32/cmd.exe",
			"javascript:alert(1)", "example.com/g", ""]:
		var out := VersionCheck.read_payload(
			200, _body('{"version":"0.191.0","url":"%s"}' % bad), "0.190.0")
		assert_dict(out).is_empty()


# The guard that keeps 89 Main.tscn suites from making a real request. If this ever comes back
# true headless, every one of them starts talking to the network on a green run.
func test_disabled_headless() -> void:
	if DisplayServer.get_name() == "headless":
		assert_bool(VersionCheck.enabled).is_false()
		assert_bool(UpdateBanner.enabled).is_false()
