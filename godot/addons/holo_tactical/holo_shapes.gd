extends RefCounted
## Simple wireframe silhouettes, drawn until (or instead of) a traced model: segment pairs in a unit
## frame, +X ahead, +Y up, +Z to the right. SPEC.md "Silhouettes".


## A ship: a hull with a pointed bow and square stern at the waterline and the deck, its corner
## posts, a superstructure block amidships and a mast. Sizes in metres.
static func ship(length: float, beam: float, freeboard: float, tower: float) -> PackedVector3Array:
	var h := length * .5
	var b := beam * .5
	var outline := [Vector2(h, 0), Vector2(h * .62, b), Vector2(-h * .9, b), Vector2(-h, b * .7),
		Vector2(-h, -b * .7), Vector2(-h * .9, -b), Vector2(h * .62, -b)]
	var lines := PackedVector3Array()
	for i: int in outline.size():
		var a: Vector2 = outline[i]
		var c: Vector2 = outline[(i + 1) % outline.size()]
		lines.append_array([Vector3(a.x, 0, a.y), Vector3(c.x, 0, c.y)])
		lines.append_array([Vector3(a.x, freeboard, a.y), Vector3(c.x, freeboard, c.y)])
		lines.append_array([Vector3(a.x, 0, a.y), Vector3(a.x, freeboard, a.y)])
	box(lines, Vector3(-length * .04, freeboard, 0), Vector3(length * .22, tower, beam * .55))
	lines.append_array([Vector3(-length * .02, freeboard + tower, 0), Vector3(-length * .02, freeboard + tower * 1.8, 0)])
	return lines


## A ship scaled from its length and beam alone.
static func ship_of(length: float, beam: float) -> PackedVector3Array:
	return ship(length, beam if beam > 0.0 else length * .13, length * .06, length * .12)


## An aircraft: fuselage, swept wings, tailplane and fin. `span` in metres.
static func plane(span: float) -> PackedVector3Array:
	var s := span * .5
	var l := span * .8
	return PackedVector3Array([
		Vector3(l * .55, 0, 0), Vector3(-l * .45, 0, 0),
		Vector3(l * .12, 0, 0), Vector3(-l * .08, 0, s), Vector3(l * .12, 0, 0), Vector3(-l * .08, 0, -s),
		Vector3(-l * .08, 0, s), Vector3(-l * .02, 0, 0), Vector3(-l * .08, 0, -s), Vector3(-l * .02, 0, 0),
		Vector3(-l * .36, 0, 0), Vector3(-l * .45, 0, s * .38), Vector3(-l * .36, 0, 0), Vector3(-l * .45, 0, -s * .38),
		Vector3(-l * .32, 0, 0), Vector3(-l * .45, s * .32, 0)])


## A missile: a body with cruciform fins at the tail. `length` in metres.
static func missile(length: float) -> PackedVector3Array:
	var h := length * .5
	var f := length * .14
	return PackedVector3Array([Vector3(h, 0, 0), Vector3(-h, 0, 0),
		Vector3(-h * .7, 0, 0), Vector3(-h, f, 0), Vector3(-h * .7, 0, 0), Vector3(-h, -f, 0),
		Vector3(-h * .7, 0, 0), Vector3(-h, 0, f), Vector3(-h * .7, 0, 0), Vector3(-h, 0, -f)])


## The fallback silhouette of a contact (holo_feed.gd), in metres.
static func for_contact(contact: Dictionary) -> PackedVector3Array:
	var size := float(contact.get("size", 10.0))
	match str(contact.get("kind", "")):
		"plane", "drone": return plane(size)
		"missile": return missile(size)
	return ship_of(size, float(contact.get("beam", 0.0)))


## The twelve edges of a box with its bottom centre at `base`.
static func box(lines: PackedVector3Array, base: Vector3, size: Vector3) -> void:
	var x := size.x * .5
	var z := size.z * .5
	var corners := [Vector3(x, 0, z), Vector3(-x, 0, z), Vector3(-x, 0, -z), Vector3(x, 0, -z)]
	for i: int in 4:
		var a: Vector3 = base + corners[i]
		var c: Vector3 = base + corners[(i + 1) % 4]
		lines.append_array([a, c, a + Vector3(0, size.y, 0), c + Vector3(0, size.y, 0), a, a + Vector3(0, size.y, 0)])
