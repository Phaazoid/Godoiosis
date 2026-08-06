# Guard for Classes/net/MultipartForm (#131). This is a WIRE FORMAT, so the tests restate it
# deliberately -- the contract is what Discord's parser accepts, not what our builder happens to
# emit, and a test that only re-called the builder would agree with any bug.
#
# The bug worth falsifying: assembling the body as a String instead of a PackedByteArray. That
# looks correct on the .md and .tres parts and silently destroys the PNG, because a byte like
# 0xFF is not valid UTF-8 and gets replaced on the way through. test_binary_payload_survives_
# verbatim is the one that catches it; swap the implementation to String concatenation and it
# fails while every structural test below still passes.
#
# Pure static calls -- no nodes built -- so this stays orphan-clean.
extends GdUnitTestSuite

const B := "testboundary"

func _file(field: String, filename: String, mime: String, bytes: PackedByteArray) -> Dictionary:
	return {"field": field, "filename": filename, "mime": mime, "bytes": bytes}

# HTTP headers are CRLF-delimited. A bare \n parses on some servers and not on Discord's, which
# is the kind of failure that looks like a network problem from the game's side.
func test_every_line_break_in_the_envelope_is_crlf() -> void:
	var body := MultipartForm.build(B, {"note": "hi"}, [] as Array[Dictionary])
	var text := body.get_string_from_utf8()
	assert_int(text.count("\r\n")).is_greater(0)
	assert_int(text.count("\n")).is_equal(text.count("\r\n"))

func test_a_plain_field_renders_as_a_named_part() -> void:
	var body := MultipartForm.build(B, {"payload_json": "{\"content\":\"x\"}"}, [] as Array[Dictionary])
	var text := body.get_string_from_utf8()
	assert_str(text).contains("--testboundary\r\n")
	assert_str(text).contains("Content-Disposition: form-data; name=\"payload_json\"\r\n\r\n")
	assert_str(text).contains("{\"content\":\"x\"}")

func test_a_file_part_carries_filename_and_mime() -> void:
	var files: Array[Dictionary] = [_file("files[0]", "report.md", "text/markdown", "# hi".to_utf8_buffer())]
	var body := MultipartForm.build(B, {}, files)
	var text := body.get_string_from_utf8()
	assert_str(text).contains("Content-Disposition: form-data; name=\"files[0]\"; filename=\"report.md\"\r\n")
	assert_str(text).contains("Content-Type: text/markdown\r\n\r\n")
	assert_str(text).contains("# hi")

# The trailing "--" is what tells the parser the body ended. Without it Discord waits, then 400s.
func test_the_body_closes_with_the_terminating_boundary() -> void:
	var body := MultipartForm.build(B, {"a": "1"}, [] as Array[Dictionary])
	assert_str(body.get_string_from_utf8()).ends_with("--testboundary--\r\n")

func test_fields_and_files_are_both_present_in_one_body() -> void:
	var files: Array[Dictionary] = [
		_file("files[0]", "a.txt", "text/plain", "AAA".to_utf8_buffer()),
		_file("files[1]", "b.txt", "text/plain", "BBB".to_utf8_buffer()),
	]
	var text := MultipartForm.build(B, {"payload_json": "{}"}, files).get_string_from_utf8()
	# Three opening boundaries plus the terminator, which repeats the boundary a fourth time.
	assert_int(text.count("--testboundary")).is_equal(4)
	assert_str(text).contains("filename=\"a.txt\"")
	assert_str(text).contains("filename=\"b.txt\"")
	assert_str(text).contains("AAA")
	assert_str(text).contains("BBB")

# THE test. A PNG is arbitrary bytes: NUL, 0xFF, and CRLF sequences all occur inside one, and none
# of them may be touched or re-encoded on the way into the body.
func test_binary_payload_survives_verbatim() -> void:
	var payload := PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x00, 0x0D, 0x0A, 0xFF, 0xFE, 0x01])
	var files: Array[Dictionary] = [_file("files[0]", "board.png", "image/png", payload)]
	var body := MultipartForm.build(B, {}, files)

	var header := "--%s\r\nContent-Disposition: form-data; name=\"files[0]\"; filename=\"board.png\"\r\nContent-Type: image/png\r\n\r\n" % B
	var expected := header.to_utf8_buffer()
	expected.append_array(payload)
	expected.append_array(("\r\n--%s--\r\n" % B).to_utf8_buffer())

	# Size first: it gives a readable failure when the payload was re-encoded rather than copied.
	assert_int(body.size()).is_equal(expected.size())
	assert_bool(body == expected).is_true()

func test_an_empty_form_is_still_a_valid_terminated_body() -> void:
	var body := MultipartForm.build(B, {}, [] as Array[Dictionary])
	assert_str(body.get_string_from_utf8()).is_equal("--testboundary--\r\n")
