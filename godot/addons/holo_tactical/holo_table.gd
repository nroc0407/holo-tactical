extends Node3D
## Miniature hologram table (SPEC.md "Table"): a head-up projection of the feed (holo_feed.gd) on a
## round table top. Place this node at the middle of the table top, +X toward "ahead" (the
## projection turns so the origin's heading points along +X). Land as contour stacks, shallows on
## the floor, contacts as small wireframes traced from their models (true scale once zoomed in),
## wakes, tracks, predicted paths and map symbols; only a picked contact shows text (its range).
## Worked by hand through the API: table_hit (where a sight line meets it), step_range (zoom),
## begin_drag / drag_to / end_drag (slide the view; a press let go in place is a click), pick and
## recenter. Each of these emits `acted` so the game can animate whoever works the table.
const Feed = preload("res://addons/holo_tactical/holo_feed.gd")
const Style = preload("res://addons/holo_tactical/holo_style.gd")
const Wireframe = preload("res://addons/holo_tactical/holo_wireframe.gd")
const Shapes = preload("res://addons/holo_tactical/holo_shapes.gd")
const History = preload("res://addons/holo_tactical/holo_history.gd")
const World = preload("res://addons/holo_tactical/holo_world.gd")

## kind: "zoom" | "pan" | "pick" | "center"; at: the world point on the table it is about; inward:
## for zoom, true when zooming in.
signal acted(kind: String, at: Vector3, inward: bool)

## Projection radius (m), the ranges the zoom steps through (m), the height scale's top (aircraft
## at 4 km stand `height` above the floor until zoomed in to true scale), land relief exaggeration.
var radius := .62
var ranges: Array[float] = [350.0, 700.0, 1500.0, 3000.0, 6000.0, 12000.0, 24000.0]
var height := .45
var terrain_lift := 1.3
## Minimum silhouette sizes on the table (m): the own ship's length, other ships, aircraft, missiles.
var own_length := .055
var ship_length := Vector2(.02, .042)
var air_span := .024
var missile_length := .016
## Map symbols' half size and lift; click radius; how far the view may slide (m); click slop (m).
var symbol_size := .008
var symbol_lift := .022
var pick_radius := .035
var max_offset := 30000.0
var click_slop := .012
## Seconds between redraws while watched.
var redraw := .15
var font: Font
## The render layer(s) the table's lines are drawn on (a room of its own, or the default).
var layer := 1

var feed: Feed
var holo_range := 12000.0
## The view's centre off the origin, world metres (x, z); kept as the origin moves on.
var view_offset := Vector2.ZERO
var drag: Dictionary = {}
## The picked contact's id, or "".
var picked := ""
var history := History.new()
var _mesh := ImmediateMesh.new()
var _lines: MeshInstance3D
var _label: Label3D
var _timer := 0.0
var _contours: Array[Dictionary] = []
var _shoals := PackedVector2Array()
var _shoal_at := Vector2.INF
var _shoal_range := 0.0
var _twins: Dictionary = {}
var _materials: Dictionary = {}


func setup(feed_value: Feed) -> void:
	feed = feed_value
	name = "HoloTable"
	_lines = MeshInstance3D.new()
	_lines.mesh = _mesh
	_lines.material_override = World.glow_material(Color.WHITE, true)
	_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lines.extra_cull_margin = 2.0
	_lines.layers = layer
	add_child(_lines)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.shaded = false
	_label.double_sided = true
	_label.pixel_size = .00045
	_label.font_size = 28
	_label.outline_size = 6
	_label.outline_modulate = Color(0, .08, .12, .8)
	_label.visible = false
	_label.layers = layer
	if font != null: _label.font = font
	add_child(_label)
	for tint: String in ["own", "opening", "closing", "threat"]: _materials[tint] = World.glow_material(Style.colour(tint), false)
	_contours = feed.terrain_contours()


## Every frame; it redraws only while someone watches (`watching`), history is kept always.
func update(dt: float, watching: bool) -> void:
	history.record(feed, dt)
	if not watching: return
	_timer -= dt
	if _timer > 0.0: return
	_timer = redraw
	_draw()


# --- Worked by hand -----------------------------------------------------------------------------

## Where a sight line meets the projection's floor, in the table's plan (x ahead, z right), or INF.
func table_hit(origin: Vector3, direction: Vector3) -> Vector2:
	var inverse := global_transform.affine_inverse()
	var o := inverse * origin
	var d := inverse.basis * direction
	if absf(d.y) < .0001: return Vector2.INF
	var t := (.03 - o.y) / d.y
	if t <= 0.0 or t > 4.0: return Vector2.INF
	var hit := Vector2(o.x + d.x * t, o.z + d.z * t)
	return hit if hit.length() <= radius * 1.05 else Vector2.INF


## A table plan point in the world.
func table_point(at: Vector2, lift: float = .04) -> Vector3:
	return to_global(Vector3(at.x, lift, at.y))


func step_range(inward: bool) -> float:
	var index := ranges.find(holo_range)
	if index < 0: index = ranges.size() - 2
	holo_range = ranges[clampi(index + (-1 if inward else 1), 0, ranges.size() - 1)]
	_timer = 0.0
	acted.emit("zoom", table_point(Vector2.ZERO, .06), inward)
	return holo_range


func begin_drag(at: Vector2) -> void:
	drag = {"from": at, "offset": view_offset, "moved": 0.0}
	acted.emit("pan", table_point(at), false)


## The grabbed point stays under the sight: the view slides the other way.
func drag_to(at: Vector2) -> void:
	if drag.is_empty(): return
	var delta: Vector2 = at - drag.from
	drag.moved = maxf(float(drag.moved), delta.length())
	view_offset = ((drag.offset as Vector2) - (delta / _true_scale()).rotated(float(feed.origin().heading))).limit_length(max_offset)
	_timer = 0.0
	acted.emit("pan", table_point(at), false)


## Ends a drag; a press that hardly moved is a click and picks what is under it. Returns the pick
## ({} for none) on a click, null after a real drag.
func end_drag() -> Variant:
	if drag.is_empty(): return null
	var click: bool = float(drag.moved) < click_slop
	var at: Vector2 = drag.from
	if click: view_offset = drag.offset
	drag = {}
	return pick(at) if click else null


## The contact under a table point, picked ({} for none: the pick is cleared).
func pick(at: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var nearest := pick_radius
	for contact: Dictionary in feed.contacts():
		if str(contact.kind) == "own": continue
		var p := _project(Vector2(contact.position.x, contact.position.z))
		if p.distance_to(at) < nearest:
			nearest = p.distance_to(at)
			best = contact
	picked = str(best.get("id", ""))
	_timer = 0.0
	acted.emit("pick", table_point(at, .03), false)
	return best


func recenter() -> void:
	view_offset = Vector2.ZERO
	_timer = 0.0
	acted.emit("center", table_point(Vector2.ZERO), false)


## Where the origin stands on the table (it leaves the middle when the view slides).
func origin_point() -> Vector2:
	var at: Vector3 = feed.origin().position
	return _project(Vector2(at.x, at.z))


# --- Projection ---------------------------------------------------------------------------------

func _true_scale() -> float:
	return radius / holo_range


func _height_scale() -> float:
	return maxf(height / 4000.0, _true_scale())


func _project(world: Vector2) -> Vector2:
	var origin: Dictionary = feed.origin()
	var centre := Vector2(origin.position.x, origin.position.z) + view_offset
	return (world - centre).rotated(-float(origin.heading)) * _true_scale()


func _point(world: Vector3, floor_y: float = .012) -> Vector3:
	var p := _project(Vector2(world.x, world.z))
	var y := floor_y if world.y < 5.0 else minf(floor_y + .04 + world.y * _height_scale(), 1.0)
	return Vector3(p.x, y, p.y)


func _inside(a: Vector3) -> bool:
	return Vector2(a.x, a.z).length() <= radius


# --- Drawing ------------------------------------------------------------------------------------

func _line(a: Vector3, b: Vector3, colour: Color) -> void:
	_mesh.surface_set_color(colour)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_color(colour)
	_mesh.surface_add_vertex(b)


func _clipped(a: Vector3, b: Vector3, colour: Color) -> void:
	if _inside(a) and _inside(b): _line(a, b, colour)


func _ring(r: float, y: float, colour: Color, segments: int = 48) -> void:
	for i: int in segments:
		var a := TAU * i / segments
		var b := TAU * (i + 1) / segments
		_line(Vector3(cos(a) * r, y, sin(a) * r), Vector3(cos(b) * r, y, sin(b) * r), colour)


func _small_ring(at: Vector3, r: float, colour: Color) -> void:
	for i: int in 10:
		var a := TAU * i / 10
		var b := TAU * (i + 1) / 10
		_line(at + Vector3(cos(a), 0, sin(a)) * r, at + Vector3(cos(b), 0, sin(b)) * r, colour)


func _dashed(a: Vector3, b: Vector3, colour: Color, dashes: int = 10) -> void:
	for i: int in dashes:
		var from := a.lerp(b, float(i) / dashes)
		var to := a.lerp(b, (float(i) + .55) / dashes)
		if not _inside(to): return
		_line(from, to, colour)


func _shape(lines: PackedVector3Array, at: Vector3, yaw: float, fit: float, colour: Color) -> void:
	var basis := Basis(Vector3.UP, -yaw).scaled(Vector3.ONE * fit)
	for i: int in range(0, lines.size(), 2):
		_line(at + basis * lines[i], at + basis * lines[i + 1], colour)


func _symbol(camera: Camera3D, kind: String, at: Vector3, colour: Color) -> void:
	if camera == null: return
	var view := global_basis.inverse() * camera.global_basis
	var right := view.x.normalized() * symbol_size
	var up := view.y.normalized() * symbol_size
	var glyph := Style.symbol(kind)
	for i: int in range(0, glyph.size(), 2):
		_line(at + right * glyph[i].x + up * glyph[i].y, at + right * glyph[i + 1].x + up * glyph[i + 1].y, colour)


func _draw() -> void:
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var cyan := Style.colour("own")
	var time := feed.time()
	var flicker := .85 + .15 * sin(time * 23.0)
	var base := cyan * Color(1, 1, 1, .55 * flicker)
	var faint := cyan * Color(1, 1, 1, .22 * flicker)
	var origin: Dictionary = feed.origin()
	var heading := float(origin.heading)
	var camera := get_viewport().get_camera_3d()
	var palette := Style.palette()
	# Floor: range rings at thirds, bearing ticks, a sweep.
	for k: int in range(1, 4): _ring(radius * k / 3.0, .01, faint if k < 3 else base)
	for i: int in 12:
		var a := TAU * i / 12
		_line(Vector3(cos(a), .01, sin(a)) * radius * .94, Vector3(cos(a), .01, sin(a)) * radius, base)
	var sweep := time * 1.6
	_line(Vector3(0, .012, 0), Vector3(cos(sweep), .012, sin(sweep)) * radius, base)
	_draw_shoals(origin)
	for entry: Dictionary in _contours:
		var ring: PackedVector2Array = entry.ring
		var y := .013 + float(entry.level) * maxf(height / 4000.0 * terrain_lift, _true_scale())
		var colour := base if float(entry.level) < 3.0 else faint * Color(1, 1, 1, 1.6)
		for i: int in ring.size():
			var a := _project(ring[i])
			var b := _project(ring[(i + 1) % ring.size()])
			_clipped(Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), colour)
	_draw_trails()
	var true_scale := _true_scale()
	var alive: Dictionary = {}
	var picked_at := Vector3.INF
	var picked_contact: Dictionary = {}
	for contact: Dictionary in feed.contacts():
		var kind := str(contact.kind)
		var size := float(contact.get("size", 10.0))
		var at: Vector3 = contact.position
		var p := _point(at, .012 if kind == "own" else .02)
		if kind == "own":
			if not _inside(p):
				_edge_chevron(Vector2(p.x, p.z), cyan)
				continue
		elif not _inside(p): continue
		var tint := "own"
		var fit := 1.0
		match kind:
			"own": fit = maxf(own_length / maxf(size, 1.0), true_scale)
			"boat", "boss":
				tint = "threat" if kind == "boss" else ("closing" if bool(contact.get("closing", false)) else "opening")
				fit = maxf(clampf(size / 270.0 * own_length, ship_length.x, ship_length.y) * (1.3 if kind == "boss" else 1.0) / maxf(size, 1.0), true_scale)
			"missile":
				tint = "threat"
				fit = maxf(missile_length / maxf(size, 1.0), true_scale)
			_:
				tint = "opening"
				fit = maxf(air_span / maxf(size, 1.0), true_scale)
		var colour: Color = (_materials[tint] as StandardMaterial3D).albedo_color
		if not _twin(contact, p, heading, fit, tint, alive):
			_shape(Shapes.for_contact(contact), p, World._yaw(contact) - heading, fit, colour)
		if kind == "own": continue
		_line(Vector3(p.x, .01, p.z), p, colour * Color(1, 1, 1, .35))
		_symbol(camera, kind, p + Vector3(0, symbol_lift, 0), colour)
		if kind in ["plane", "missile", "drone"]:
			var velocity: Vector3 = contact.get("velocity", Vector3.ZERO)
			var finish := _point(at + velocity * float(palette.predict_seconds.missile if kind == "missile" else palette.predict_seconds.plane))
			_dashed(p, finish, colour * Color(1, 1, 1, .6))
			if _inside(finish): _small_ring(finish, .008, colour * Color(1, 1, 1, .6))
		if str(contact.id) == picked:
			picked_at = p
			picked_contact = contact
	for runner: Dictionary in feed.runners():
		var start := _point(runner.position, .01)
		if _inside(start):
			_dashed(start, _point((runner.position as Vector3) + (runner.velocity as Vector3) * float(palette.predict_seconds.runner), .01), Style.colour("runner"), 14)
	_label.visible = false
	if picked_at.is_finite():
		var pulse := .02 + .006 * sin(time * 8.0)
		_small_ring(picked_at, pulse, Color(1, 1, 1, .95))
		_symbol(camera, "picked", picked_at + Vector3(0, symbol_lift, 0), Color(1, 1, 1, .95))
		var range_m := Vector2(picked_contact.position.x - origin.position.x, picked_contact.position.z - origin.position.z).length()
		_label.text = "%.1f km" % (range_m / 1000.0)
		_label.position = picked_at + Vector3(0, symbol_lift * 2.2, 0)
		_label.visible = true
	elif picked != "":
		picked = ""
	_mesh.surface_end()
	for key: String in _twins.keys():
		if not alive.has(key):
			(_twins[key] as Node).queue_free()
			_twins.erase(key)


func _twin(contact: Dictionary, at: Vector3, heading: float, fit: float, tint: String, alive: Dictionary) -> bool:
	var node: Node3D = contact.get("node")
	if node == null or not is_instance_valid(node): return false
	var wire: Dictionary = Style.palette().wireframe
	var mesh := Wireframe.lines_for(str(contact.get("model_key", contact.id)) + "@table", node, float(wire.table_crease))
	if mesh == null: return false
	var key := str(contact.id)
	var twin: MeshInstance3D = _twins.get(key)
	if twin == null:
		twin = MeshInstance3D.new()
		twin.layers = layer
		twin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(twin)
		_twins[key] = twin
	if twin.mesh != mesh or twin.get_meta("tint", "") != tint:
		twin.mesh = mesh
		twin.set_meta("tint", tint)
		var glow := (_materials[tint] as StandardMaterial3D).duplicate() as StandardMaterial3D
		glow.albedo_color.a *= Wireframe.glow_for(mesh.surface_get_array_len(0) / 2, float(wire.table_glow_reference), Vector2(.15, 1.0))
		twin.material_override = glow
	# The model's own attitude, turned into the head-up frame.
	twin.transform = Transform3D((Basis(Vector3.UP, heading) * node.global_basis.orthonormalized()).scaled(Vector3.ONE * fit), at)
	alive[key] = true
	return true


func _edge_chevron(towards: Vector2, colour: Color) -> void:
	var d := towards.normalized()
	var edge := d * radius * .93
	var side := Vector2(-d.y, d.x) * .02
	var tip := d * radius * .99
	for pair: Array in [[edge + side, tip], [edge - side, tip]]:
		_line(Vector3(pair[0].x, .015, pair[0].y), Vector3(pair[1].x, .015, pair[1].y), colour)


func _draw_shoals(origin: Dictionary) -> void:
	var here := Vector2(origin.position.x, origin.position.z) + view_offset
	if _shoal_range != holo_range or here.distance_to(_shoal_at) > holo_range * .1:
		_shoal_at = here
		_shoal_range = holo_range
		_shoals = feed.shoals(here, holo_range)
	var colour := Style.colour("shoal") * Color(1, 1, 1, 1.15)
	for i: int in range(0, _shoals.size() - 1, 2):
		var a := _project(_shoals[i])
		var b := _project(_shoals[i + 1])
		_clipped(Vector3(a.x, .006, a.y), Vector3(b.x, .006, b.y), colour)


func _draw_trails() -> void:
	for id: String in history.wakes:
		var wake: Dictionary = history.wakes[id]
		var points: Array = wake.points
		var colour := Style.colour("own" if wake.kind == "own" else "opening")
		for i: int in range(1, points.size()):
			_clipped(_point(points[i - 1], .008), _point(points[i], .008), colour * Color(1, 1, 1, .45 * float(i) / points.size()))
	for id: String in history.tracks:
		var track: Dictionary = history.tracks[id]
		var points: Array = track.points
		var colour := Style.colour("friendly_round" if track.friendly else "threat")
		for i: int in range(1, points.size()):
			_clipped(_point(points[i - 1]), _point(points[i]), colour * Color(1, 1, 1, .8 * float(i) / points.size()))


## For captures (holo_capture.gd): every lines mesh drawn now, as [mesh, transform in the table's
## frame, tint].
func line_sources() -> Array:
	var sources := [[_mesh, Transform3D.IDENTITY, Color.WHITE]]
	for twin: MeshInstance3D in _twins.values():
		sources.append([twin.mesh, twin.transform, (twin.material_override as StandardMaterial3D).albedo_color])
	return sources
