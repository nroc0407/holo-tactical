extends RefCounted
## The look's data (data/palette.json) and the map symbols (data/symbols.json), loaded once.
## Games may change `palette` entries before building views.
const DIR := "res://addons/holo_tactical/data/"

static var _palette: Dictionary = {}
static var _symbols: Dictionary = {}


static func palette() -> Dictionary:
	if _palette.is_empty(): _palette = JSON.parse_string(FileAccess.get_file_as_string(DIR + "palette.json"))
	return _palette


static func colour(name: String) -> Color:
	var value: Array = palette()[name]
	return Color(float(value[0]), float(value[1]), float(value[2]), float(value[3]) if value.size() > 3 else 1.0)


## A symbol's segments as pairs of Vector2 in its unit square.
static func symbol(kind: String) -> PackedVector2Array:
	if _symbols.is_empty():
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "symbols.json"))
		for key: String in data:
			if key.begins_with("_"): continue
			var pairs := PackedVector2Array()
			for segment: Array in data[key]:
				pairs.append(Vector2(float(segment[0]), float(segment[1])))
				pairs.append(Vector2(float(segment[2]), float(segment[3])))
			_symbols[key] = pairs
	return _symbols.get(kind, _symbols.get("boat", PackedVector2Array()))
