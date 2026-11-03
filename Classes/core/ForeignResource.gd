extends RefCounted
class_name ForeignResource

# MAY THIS FILE BE HANDED TO GODOT'S LOADER? (#1555) The one answer, asked before any file from
# outside the project is loaded: a pulled telemetry run, a save slot, a path a Play API driver names,
# or a name on a board that composes into a path. Godot's text-resource loader runs code WHILE it
# parses (an embedded GDScript, an inline Object(), a Resource("any/path")), so the check has to read
# the file before the loader does, and nothing about the file can be trusted while it reads.
#
# FAIL CLOSED. This mirrors the 4.7.1 tokenizer (core/variant/variant_parser.cpp: get_token, the
# property-name reader in parse_tag_assign_eof, _parse_tag) for the subset ResourceSaver writes, and
# refuses everything else -- comments, escapes in a tag, quoted property names, any byte the saver
# never puts outside a string. A string boundary that disagreed with the engine's would hide what
# follows it, so anything that could move one is refused rather than interpreted. Re-check this
# against the engine's tokenizer after a Godot upgrade.
#
# Not ContentRepair._dangling's reader: that one asks whether a reference RESOLVES, with a substring
# match a quoted "]" or an escape defeats. This asks a different question and cannot share it.

# Embedded objects may only be plain Resources (a project script makes them what they are).
const EMBEDDED_TYPES: Array[String] = ["Resource"]
# Every script a foreign file may name lives here; all committed content's scripts do.
const SCRIPT_ROOT := "res://Classes/"
# ...plus each script outside it that a field of ours is typed as (DialogBeat.timeline).
const EMBEDDED_SCRIPTS: Array[String] = ["res://addons/dialogic/Resources/timeline.gd"]
const SCRIPT_EXTENSIONS: Array[String] = ["gd", "gdc", "cs"]
const TAGS: Array[String] = ["gd_resource", "ext_resource", "sub_resource", "resource"]
# Which section each may follow (resource_format_text.cpp's load(): anything else is never read, so
# a line reader would be the only one to see it).
const SECTION_ORDER := {
	"ext_resource": ["gd_resource", "ext_resource"],
	"sub_resource": ["gd_resource", "ext_resource", "sub_resource"],
	"resource": ["gd_resource", "ext_resource", "sub_resource"],
}
const CONSTANTS: Array[String] = ["true", "false", "null", "nil", "inf", "-inf", "inf_neg", "nan"]
# parse_value's value constructors, minus every one that instantiates, loads or references an
# object: Object, Resource(...), RID, Signal, Callable, and whatever a later engine adds.
const CONSTRUCTORS: Array[String] = ["Vector2", "Vector2i", "Rect2", "Rect2i", "Vector3", "Vector3i",
	"Vector4", "Vector4i", "Transform2D", "Plane", "Quaternion", "AABB", "Basis", "Transform3D",
	"Projection", "Color", "NodePath", "PackedByteArray", "PackedInt32Array", "PackedInt64Array",
	"PackedFloat32Array", "PackedFloat64Array", "PackedStringArray", "PackedVector2Array",
	"PackedVector3Array", "PackedVector4Array", "PackedColorArray"]
const KEY_PUNCTUATION := "_/:.-"

enum Tok { EOF, STRING, STRING_NAME, NUMBER, IDENT, COLOR, PUNCT }

# Byte -> its one-character token text, "" for a byte that is not punctuation. Built once: a board is
# mostly small tokens, and a String per token was most of the check's cost.
static var _punct := _punct_table()

var _b: PackedByteArray
var _pos := 0
var _line := 1
var _why := ""
# The current token.
var _type := Tok.EOF
var _text := ""          # an identifier's name, a punctuation char, or a string's content
var _escaped := false    # a string held a backslash escape
var _tok_line := 1
var _ext := {}           # ext_resource id -> the path the loader would use
var _sections := 0
var _section := ""       # the tag of the section being read
var _next_backslash := 0 # where the next "\" is; -1 once there are none left


# "" when the file may be loaded; otherwise why not, for a person. A path inside the project is the
# project's own content and is not read; every other path is read in full, and one that cannot be
# read is refused.
static func refusal(path: String) -> String:
	if inside_project(path):
		return ""
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return "it is empty or cannot be read"
	return refusal_of(bytes)


static func refusal_of(bytes: PackedByteArray) -> String:
	var reader := ForeignResource.new()
	reader._b = bytes
	reader._parse_file()
	return reader._why


# A literal res:// path that cannot climb out of the project. Godot resolves res://../ against the
# folder on disk, so the climb is a real escape, not a malformed path.
static func inside_project(path: String) -> bool:
	if not path.begins_with("res://"):
		return false
	var rest := path.substr(6)
	return not (rest.begins_with("/") or rest.contains("//") or rest.contains("..")
		or rest.contains("\\") or rest.contains(":"))


# ==============================================================================
#  The file: tags and properties
# ==============================================================================

func _parse_file() -> void:
	if _b.find(0) != -1:
		_fail("it contains a NUL byte")
		return
	while _why == "":
		_skip_space()
		if _pos >= _b.size():
			if _sections == 0:
				_fail("it holds no resource")
			return
		if _b[_pos] == 0x5B:   # "["
			_pos += 1
			_parse_tag()
		elif _sections == 0:
			_fail("it does not start with a resource header")
		elif _section == "sub_resource" or _section == "resource":
			_parse_property()
		else:
			_fail("a property where the loader expects a section")


func _parse_tag() -> void:
	_next()
	if _type != Tok.IDENT or not TAGS.has(_text):
		_fail("an unknown section [%s" % _text)
		return
	var tag := _text
	if _sections == 0 and tag != "gd_resource":
		_fail("it is not a resource file")
		return
	# The loader's order: one header, ext_resources, sub_resources, then [resource] and nothing after.
	var after: Array = SECTION_ORDER.get(tag, [])
	if _sections > 0 and not after.has(_section):
		_fail("a [%s] section out of order" % tag)
		return
	_section = tag
	_sections += 1
	var fields := {}
	while _why == "":
		_next()
		if _type == Tok.PUNCT and _text == "]":
			break
		if _type != Tok.IDENT:
			_fail("a malformed [%s] section" % tag)
			return
		var attr := _text
		_next()
		if _type != Tok.PUNCT or _text != "=":
			_fail("a malformed [%s] section" % tag)
			return
		_next()
		if _type == Tok.NUMBER and (attr == "format" or attr == "load_steps"):
			continue
		if _type != Tok.STRING or _escaped:
			_fail("[%s] %s is not a plain string" % [tag, attr])
			return
		fields[attr] = _text
		if attr == "path" or attr == "uid":
			_check_reference(tag, attr, _text)
	if _why != "":
		return
	if tag == "gd_resource" or tag == "sub_resource":
		var type := str(fields.get("type", ""))
		if not EMBEDDED_TYPES.has(type):
			_fail("it embeds a %s" % (type if type != "" else "typeless object"))
	elif tag == "ext_resource":
		_record_ext(fields)


# One path or uid attribute of a section. Every one is checked as it is read, so a second `path=`
# (the loader keeps the last) cannot slip past behind a good first one.
func _check_reference(tag: String, attr: String, value: String) -> void:
	if tag != "ext_resource":
		return
	if attr == "path":
		_check_path(value)
		return
	var uid := ResourceUID.text_to_id(value)
	if uid != ResourceUID.INVALID_ID and ResourceUID.has_id(uid):
		_check_path(ResourceUID.get_id_path(uid))   # the loader prefers this over path=


func _check_path(path: String) -> void:
	if not inside_project(path):
		_fail("it references a file outside the project (%s)" % path)
	elif SCRIPT_EXTENSIONS.has(path.get_extension()) and not _is_own_script(path):
		_fail("it references a script outside %s (%s)" % [SCRIPT_ROOT, path])


static func _is_own_script(path: String) -> bool:
	return path.begins_with(SCRIPT_ROOT) or EMBEDDED_SCRIPTS.has(path)


func _record_ext(fields: Dictionary) -> void:
	var path := str(fields.get("path", ""))
	var uid := ResourceUID.text_to_id(str(fields.get("uid", "")))
	if uid != ResourceUID.INVALID_ID and ResourceUID.has_id(uid):
		path = ResourceUID.get_id_path(uid)
	if str(fields.get("type", "")) == "Script" and not _is_own_script(path):
		_fail("it references a script outside %s (%s)" % [SCRIPT_ROOT, path])
	_ext[str(fields.get("id", ""))] = path


# A property line. The engine reads its NAME a character at a time, skipping whitespace inside it,
# so this does too; then one value.
func _parse_property() -> void:
	_tok_line = _line
	var key := ""
	while true:
		if _pos >= _b.size():
			_fail("a property with no value")
			return
		var c := _b[_pos]
		_pos += 1
		if c == 0x3D:   # "="
			break
		if c == 0x0A:
			_line += 1
		elif c == 0x09 or c == 0x0D or c == 0x20:
			pass
		elif _is_alnum(c) or KEY_PUNCTUATION.contains(char(c)):
			key += char(c)
		else:
			_fail("a property name the saver never writes")
			return
	if key == "":
		_fail("a property with no name")
		return
	if key == "resource_path":
		_fail("it sets resource_path")
		return
	_next()
	var value := _parse_value()
	if _why == "" and key == "script":
		var path := str(_ext.get(value.get("ext", ""), ""))
		if not (_is_own_script(path) and path.get_extension() == "gd"):
			_fail("it attaches a script that is not one of the project's own")


# ==============================================================================
#  Values
# ==============================================================================

# One value starting at the current token. Returns {"ext": id} for an ExtResource, else {}.
func _parse_value() -> Dictionary:
	if _why != "":
		return {}
	match _type:
		Tok.STRING, Tok.STRING_NAME, Tok.NUMBER, Tok.COLOR:
			return {}
		Tok.PUNCT:
			if _text == "[":
				_parse_list("]")
				return {}
			if _text == "{":
				_parse_dictionary()
				return {}
		Tok.IDENT:
			return _parse_identifier()
	_fail("an unexpected %s" % ("end of file" if _type == Tok.EOF else "'%s'" % _text))
	return {}


func _parse_identifier() -> Dictionary:
	var id := _text
	if CONSTANTS.has(id):
		return {}
	if id == "ExtResource" or id == "SubResource":
		return _parse_reference(id)
	if id == "Array" or id == "Dictionary":
		_parse_typed(id)
		return {}
	if not CONSTRUCTORS.has(id):
		_fail("it constructs %s" % id)
		return {}
	_expect("(")
	_parse_list(")")
	return {}


func _parse_reference(id: String) -> Dictionary:
	_expect("(")
	_next()
	if _type != Tok.STRING or _escaped:
		_fail("a malformed %s" % id)
		return {}
	var ref := _text
	if id == "ExtResource" and not _ext.has(ref):
		_fail("an ExtResource with no section (%s)" % ref)
		return {}
	_expect(")")
	return {"ext": ref} if id == "ExtResource" else {}


# Array[T](...) and Dictionary[K, V](...). A type is a bare name or an ExtResource; a bare name is
# never followed by "(", which is how Resource("path") would get in.
func _parse_typed(id: String) -> void:
	_expect("[")
	for i in (2 if id == "Dictionary" else 1):
		if i == 1:
			_expect(",")
		_next()
		if _type != Tok.IDENT:
			_fail("a malformed %s type" % id)
			return
		if _text == "ExtResource" or _text == "SubResource":
			_parse_reference(_text)
		elif _peek_byte() == 0x28:   # "("
			_fail("it constructs %s" % _text)
			return
	_expect("]")
	_expect("(")
	_next()
	_parse_value()
	_expect(")")


# Comma-separated values up to `close`. A trailing comma is accepted, as the engine does.
func _parse_list(close: String) -> void:
	while _why == "":
		_next()
		if _type == Tok.PUNCT and _text == close:
			return
		_parse_value()
		_next()
		if _type == Tok.PUNCT and _text == close:
			return
		if _type != Tok.PUNCT or _text != ",":
			_fail("expected ',' or '%s'" % close)


func _parse_dictionary() -> void:
	while _why == "":
		_next()
		if _type == Tok.PUNCT and _text == "}":
			return
		_parse_value()
		_expect(":")
		_next()
		_parse_value()
		_next()
		if _type == Tok.PUNCT and _text == "}":
			return
		if _type != Tok.PUNCT or _text != ",":
			_fail("expected ',' or '}'")


func _expect(punct: String) -> void:
	if _why != "":
		return
	_next()
	if _type != Tok.PUNCT or _text != punct:
		_fail("expected '%s'" % punct)


# ==============================================================================
#  Tokens: get_token's rules, over bytes
# ==============================================================================

func _next() -> void:
	_text = ""
	_escaped = false
	_skip_space()
	_tok_line = _line
	if _why != "" or _pos >= _b.size():
		_type = Tok.EOF
		return
	var c := _b[_pos]
	if c < 128 and _punct[c] != "":
		_type = Tok.PUNCT
		_text = _punct[c]
		_pos += 1
	elif c == 0x22:   # '"'
		_pos += 1
		_read_string(Tok.STRING)
	elif c == 0x26 and _pos + 1 < _b.size() and _b[_pos + 1] == 0x22:   # '&"'
		_pos += 2
		_read_string(Tok.STRING_NAME)
	elif c == 0x23:   # "#": a colour, hex digits only
		_pos += 1
		while _pos < _b.size() and _is_hex(_b[_pos]):
			_pos += 1
		_type = Tok.COLOR
	else:
		_read_word()


# Whitespace between tokens: tab, newline, carriage return, space. Every other byte at or below 32,
# and every byte the saver never writes outside a string, is refused here or in _read_word.
func _skip_space() -> void:
	while _pos < _b.size():
		var c := _b[_pos]
		if c == 0x0A:
			_line += 1
		elif not (c == 0x09 or c == 0x0D or c == 0x20):
			return
		_pos += 1


# A backslash takes the byte after it whatever it is ("\i" is "i" to the engine), and \u/\U take
# their hex digits. Inside a string every other byte is data. An escaped string's _text is its raw
# bytes: every caller that reads one as a name or path refuses it instead.
func _read_string(type: Tok) -> void:
	var start := _pos
	var close := _b.find(0x22, _pos)
	if close == -1:
		_fail("an unterminated string")
		return
	if _next_backslash != -1 and _next_backslash < _pos:
		_next_backslash = _b.find(0x5C, _pos)
	if _next_backslash == -1 or _next_backslash > close:   # no escape: the whole string at once
		_line += _b.slice(_pos, close).count(0x0A)
		_pos = close + 1
	else:
		_escaped = true
		while true:
			if _pos >= _b.size():
				_fail("an unterminated string")
				return
			var c := _b[_pos]
			_pos += 1
			if c == 0x22:
				break
			if c == 0x0A:
				_line += 1
			elif c == 0x5C:   # "\"
				if _pos >= _b.size():
					_fail("an unterminated string")
					return
				var e := _b[_pos]
				_pos += 1
				if e == 0x0A:
					_line += 1
				elif e == 0x75 or e == 0x55:   # u / U
					for i in (4 if e == 0x75 else 6):
						if _pos >= _b.size() or not _is_hex(_b[_pos]):
							_fail("a malformed escape")
							return
						_pos += 1
	_type = type
	_text = _b.slice(start, _pos - 1).get_string_from_utf8()


# A number or an identifier, by the engine's rules: an optional "-", then digits through its exact
# number states (so "1eObject" is the number 1e and then the identifier Object), or a name.
func _read_word() -> void:
	var start := _pos
	if _b[_pos] == 0x2D:   # "-"
		_pos += 1
	var c := _b[_pos] if _pos < _b.size() else 0
	if c >= 0x30 and c <= 0x39:
		_read_number()
		_type = Tok.NUMBER
		return   # nothing reads a number's text
	elif _is_alpha(c):
		_pos += 1
		while _pos < _b.size() and (_is_alnum(_b[_pos])):
			_pos += 1
		_type = Tok.IDENT
	else:
		_fail("a character the saver never writes outside a string (byte %d)" % c)
		return
	_text = _b.slice(start, _pos).get_string_from_ascii()


func _read_number() -> void:
	var reading := 0   # 0 int, 1 decimals, 2 exponent
	var exp_sign := false
	var exp_digit := false
	while _pos < _b.size():
		var c := _b[_pos]
		var digit := c >= 0x30 and c <= 0x39
		if reading == 0:
			if c == 0x2E:
				reading = 1
			elif c == 0x65 or c == 0x45:
				reading = 2
			elif not digit:
				return
		elif reading == 1:
			if c == 0x65 or c == 0x45:
				reading = 2
			elif not digit:
				return
		else:
			if digit:
				exp_digit = true
			elif (c == 0x2D or c == 0x2B) and not exp_sign and not exp_digit:
				exp_sign = true
			else:
				return
		_pos += 1


func _peek_byte() -> int:
	var at := _pos
	while at < _b.size() and (_b[at] == 0x20 or _b[at] == 0x09 or _b[at] == 0x0D or _b[at] == 0x0A):
		at += 1
	return _b[at] if at < _b.size() else -1


static func _punct_table() -> PackedStringArray:
	var table := PackedStringArray()
	table.resize(128)
	for p in "{}[]():,.=":
		table[p.unicode_at(0)] = p
	return table


func _fail(what: String) -> void:
	if _why == "":
		_why = "%s (line %d)" % [what, _tok_line if _tok_line > 0 else _line]


static func _is_alpha(c: int) -> bool:
	return (c >= 0x41 and c <= 0x5A) or (c >= 0x61 and c <= 0x7A) or c == 0x5F


static func _is_alnum(c: int) -> bool:
	return _is_alpha(c) or (c >= 0x30 and c <= 0x39)


static func _is_hex(c: int) -> bool:
	return (c >= 0x30 and c <= 0x39) or (c >= 0x41 and c <= 0x46) or (c >= 0x61 and c <= 0x66)
