# The INERT payload every #1555 case smuggles into a file from outside the project. All it does is
# raise a flag on Engine from its static initializer, which runs the moment Godot compiles it -- so
# "the flag is up" means "the loader ran code from that file", and nothing else ever happens.
extends RefCounted

const FLAG := "__test_1555_payload_ran"


static func lower() -> void:
	if Engine.has_meta(FLAG):
		Engine.remove_meta(FLAG)


static func ran() -> bool:
	return Engine.has_meta(FLAG)


static func source() -> String:
	return 'extends Resource\nstatic func _static_init() -> void:\n\tEngine.set_meta("%s", true)\n' % FLAG


# The payload as a .tres string literal's content, escaped the way the text format reads it back.
static func escaped() -> String:
	return source().c_escape()


# An inline Object() value: the shape that loads a board silently AND runs the payload.
static func object_value() -> String:
	return 'Object(GDScript, "script/source": "%s")' % escaped()


# A whole .tres whose own script is the payload, embedded.
static func resource_text() -> String:
	return ('[gd_resource type="Resource" format=3]\n\n[sub_resource type="GDScript" id="GDScript_p"]\n'
		+ 'script/source = "%s"\n\n[resource]\nscript = SubResource("GDScript_p")\n' % escaped())


static func write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
