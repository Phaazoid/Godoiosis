extends Object
class_name DevTools

# Should this build have dev tools at all? (#132) "devtools" is a custom export feature: add it
# to a preset for a debuggable exported build; the demo preset omits it.
static func enabled() -> bool:
	return OS.has_feature("editor") or OS.has_feature("devtools")
