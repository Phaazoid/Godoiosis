extends Object
class_name MultipartForm

# Builds a multipart/form-data request body (#131). Pure and static, LethalityRules' shape.
#
# It MUST build a PackedByteArray, never a String. A PNG contains bytes that are not valid UTF-8
# (0xFF is the usual one), and a String round-trip silently replaces them -- the .md and .tres
# parts still look perfect, so the corruption shows up only as a broken image at the far end.
#
# The boundary is the CALLER's, because the same string has to appear in the Content-Type header.
# Passing it in is what stops those two from drifting apart.

static func build(boundary: String, fields: Dictionary, files: Array[Dictionary]) -> PackedByteArray:
	var body := PackedByteArray()

	for field_name: String in fields:
		body.append_array(("--%s\r\n" % boundary).to_utf8_buffer())
		body.append_array(("Content-Disposition: form-data; name=\"%s\"\r\n\r\n" % field_name).to_utf8_buffer())
		body.append_array(str(fields[field_name]).to_utf8_buffer())
		body.append_array("\r\n".to_utf8_buffer())

	for file: Dictionary in files:
		var bytes: PackedByteArray = file["bytes"]
		body.append_array(("--%s\r\n" % boundary).to_utf8_buffer())
		body.append_array(("Content-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\n" % [file["field"], file["filename"]]).to_utf8_buffer())
		body.append_array(("Content-Type: %s\r\n\r\n" % file["mime"]).to_utf8_buffer())
		body.append_array(bytes)
		body.append_array("\r\n".to_utf8_buffer())

	body.append_array(("--%s--\r\n" % boundary).to_utf8_buffer())
	return body
