extends Node3D
## Full-screen hologram (SPEC.md "Full-screen view"): the battle rebuilt from a feed
## (holo_feed.gd). The game's camera keeps working as usual but sees only `layer`: a sea grid laid
## round the camera, land as contour stacks with ribs, shallows, every contact as a wireframe traced
## from its own model (holo_wireframe.gd; a simple silhouette until then), wakes, tracks of rounds,
## predicted paths, blast rings, a pulse from the origin and map symbols in place of text.
## Use: add under the 3D world, setup(feed), then set_active(true, camera, environment) and call
## update(dt) every frame. The game must not switch its own fog back on while it is up.
const Feed = preload("res://addons/holo_tactical/holo_feed.gd")
const Style = preload("res://addons/holo_tactical/holo_style.gd")
const Wireframe = preload("res://addons/holo_tactical/holo_wireframe.gd")
const Shapes = preload("res://addons/holo_tactical/holo_shapes.gd")
const History = preload("res://addons/holo_tactical/holo_history.gd")

## The render layer only the hologram draws on while it is up (pick one the game does not use).
var layer := 1 << 18
## Static layers are rebuilt when the camera has moved this far from where they were built.
var rebuild_distance := 600.0
var shoal_reach := 9000.0
## Blast rings live this long (s); the pulse repeats every pulse_every s out to pulse_reach.
var blast_life := 1.6
var pulse_every := 4.0
var pulse_reach := 6000.0
## Symbols keep this share of the camera distance as their half size (same size on screen),
## lifted this many half sizes above their contact.
var symbol_scale := .012
var symbol_lift := 2.4

var feed: Feed
var active := false
var history := History.new()
var _static_mesh := ImmediateMesh.new()
var _live_mesh := ImmediateMesh.new()
var _static_at := Vector2.INF
var _contours: Array[Dictionary] = []
var _blasts: Array[Dictionary] = []
var _seen_event := -1
var _clock := 0.0
var _twins: Dictionary = {}
var _materials: Dictionary = {}
var _saved_cull := 0
var _saved_environment: Dictionary = {}
var _building_static := true


func setup(feed_value: Feed) -> void:
	feed = feed_value
	name = "HoloWorld"
	for mesh: ImmediateMesh in [_static_mesh, _live_mesh]:
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.layers = layer
		node.material_override = glow_material(Color.WHITE, true)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.extra_cull_margin = 16384.0
		add_child(node)
	for tint: String in ["own", "hostile", "threat"]: _materials[tint] = glow_material(Style.colour(tint), false)
	_contours = feed.terrain_contours()
	visible = false


## An unshaded, additive line material.
static func glow_material(colour: Color, vertex_colours: bool) -> StandardMaterial3D:
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.vertex_color_use_as_albedo = vertex_colours
	glow.albedo_color = colour
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	return glow


## Up (only `layer` drawn, the palette's dark background, no fog) or down (all as it was).
func set_active(on: bool, camera: Camera3D, environment: Environment) -> void:
	if on == active: return
	active = on
	visible = on
	if on:
		_saved_cull = camera.cull_mask
		camera.cull_mask = layer
		if environment != null:
			_saved_environment = {"mode": environment.background_mode, "colour": environment.background_color, "fog": environment.fog_enabled}
			environment.background_mode = Environment.BG_COLOR
			environment.background_color = Style.colour("background")
			environment.fog_enabled = false
		_static_at = Vector2.INF
		_blasts.clear()
		for event: Dictionary in feed.events(): _seen_event = maxi(_seen_event, int(event.id))
	else:
		camera.cull_mask = _saved_cull
		if environment != null and not _saved_environment.is_empty():
			environment.background_mode = _saved_environment.mode
			environment.background_color = _saved_environment.colour
			environment.fog_enabled = _saved_environment.fog
		for key: String in _twins: (_twins[key] as Node).queue_free()
		_twins.clear()


## Every frame. History is kept while hidden too, so wakes are there the moment it opens.
func update(dt: float) -> void:
	history.record(feed, dt)
	if not active: return
	_clock += dt
	var camera := get_viewport().get_camera_3d()
	var eye: Vector3 = camera.global_position if camera != null else feed.origin().position
	var here := Vector2(eye.x, eye.z)
	if here.distance_to(_static_at) > rebuild_distance:
		_static_at = here
		_build_static(here)
	_build_live(camera, dt)


# --- Static layers -------------------------------------------------------------------------------

func _build_static(centre: Vector2) -> void:
	_building_static = true
	_static_mesh.clear_surfaces()
	_static_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var grid: Dictionary = Style.palette().grid
	var cyan := Style.colour("own")
	for spec: Array in [[grid.fine, float(grid.fine_alpha)], [grid.coarse, float(grid.coarse_alpha)]]:
		var step := float(spec[0][0])
		var reach := float(spec[0][1])
		var origin := (centre / step).floor() * step
		var count := int(reach / step)
		for k: int in range(-count, count + 1):
			for along: int in 2:
				for piece: int in range(-count, count):
					var a := origin + (Vector2(k, piece) if along == 0 else Vector2(piece, k)) * step
					var b := origin + (Vector2(k, piece + 1) if along == 0 else Vector2(piece + 1, k)) * step
					var fade := 1.0 - clampf(((a + b) * .5).distance_to(centre) / reach, 0.0, 1.0)
					if fade > 0.0: _line(Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y), cyan * Color(1, 1, 1, float(spec[1]) * fade))
	# Land: contours, with ribs between neighbouring levels of the same island on every sixth point.
	for index: int in _contours.size():
		var entry: Dictionary = _contours[index]
		var ring: PackedVector2Array = entry.ring
		var y := float(entry.level)
		var colour := cyan * Color(1, 1, 1, .7 if y < 3.0 else .35)
		var above: Dictionary = _contours[index + 1] if index + 1 < _contours.size() else {}
		var ribbed := not above.is_empty() and float(above.level) > y and (above.ring as PackedVector2Array).size() == ring.size()
		for i: int in ring.size():
			var a := ring[i]
			var b := ring[(i + 1) % ring.size()]
			_line(Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), colour)
			if ribbed and i % 6 == 0:
				var c: Vector2 = (above.ring as PackedVector2Array)[i]
				_line(Vector3(a.x, y, a.y), Vector3(c.x, float(above.level), c.y), cyan * Color(1, 1, 1, .2))
	var shoals := feed.shoals(centre, shoal_reach)
	var shoal := Style.colour("shoal")
	for i: int in range(0, shoals.size() - 1, 2):
		_line(Vector3(shoals[i].x, -1.0, shoals[i].y), Vector3(shoals[i + 1].x, -1.0, shoals[i + 1].y), shoal)
	_static_mesh.surface_end()


func _line(a: Vector3, b: Vector3, colour: Color) -> void:
	var mesh := _static_mesh if _building_static else _live_mesh
	mesh.surface_set_color(colour)
	mesh.surface_add_vertex(a)
	mesh.surface_set_color(colour)
	mesh.surface_add_vertex(b)


# --- Live layers ---------------------------------------------------------------------------------

func _build_live(camera: Camera3D, dt: float) -> void:
	_building_static = false
	_live_mesh.clear_surfaces()
	_live_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var palette := Style.palette()
	var flicker := 1.0 - float(palette.flicker.amount) + float(palette.flicker.amount) * sin(_clock * float(palette.flicker.rate))
	var predict: Dictionary = palette.predict_seconds
	var origin: Dictionary = feed.origin()
	var cyan := Style.colour("own")
	var pulse := fmod(_clock, pulse_every) / pulse_every
	_circle(origin.position, pulse * pulse_reach, cyan * Color(1, 1, 1, .35 * (1.0 - pulse)), 96)
	_trails()
	var alive: Dictionary = {}
	for contact: Dictionary in feed.contacts():
		var kind := str(contact.kind)
		var tint := "own" if kind == "own" else ("threat" if kind in ["missile", "boss"] else "hostile")
		var colour := Style.colour(tint)
		var at: Vector3 = contact.position
		if not _twin(contact, tint, alive):
			_shape(Shapes.for_contact(contact), at, _yaw(contact), colour * Color(1, 1, 1, flicker))
		if kind == "own": continue
		var velocity: Vector3 = contact.get("velocity", Vector3.ZERO)
		if kind in ["plane", "missile", "drone"]:
			_line(at, Vector3(at.x, 0, at.z), colour * Color(1, 1, 1, .18))
			_circle(Vector3(at.x, 0, at.z), 12.0, colour * Color(1, 1, 1, .25), 12)
			var ahead := at + velocity * float(predict.missile if kind == "missile" else predict.plane)
			_dashed(at, ahead, colour * Color(1, 1, 1, .55), 14)
			_circle(ahead, 18.0, colour * Color(1, 1, 1, .5), 12)
		var lift := float(contact.get("size", 10.0)) * .12 if kind in ["boat", "boss"] else 0.0
		_symbol(camera, kind, at + Vector3(0, lift, 0), colour)
	for runner: Dictionary in feed.runners():
		var at: Vector3 = runner.position
		_dashed(Vector3(at.x, .5, at.z), Vector3(at.x, .5, at.z) + (runner.velocity as Vector3) * float(predict.runner), Style.colour("runner"), 20)
	_draw_blasts(dt)
	_live_mesh.surface_end()
	_building_static = true
	for key: String in _twins.keys():
		if not alive.has(key):
			(_twins[key] as Node).queue_free()
			_twins.erase(key)
	for key: String in _twins:
		var twin: MeshInstance3D = _twins[key]
		(twin.material_override as StandardMaterial3D).albedo_color.a = flicker * float(twin.get_meta("glow", 1.0))


## The contact's traced wireframe in place of its model; false while there is none yet.
func _twin(contact: Dictionary, tint: String, alive: Dictionary) -> bool:
	var node: Node3D = contact.get("node")
	if node == null or not is_instance_valid(node): return false
	var wire: Dictionary = Style.palette().wireframe
	var mesh := Wireframe.lines_for(str(contact.get("model_key", contact.id)), node, float(wire.crease))
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
		twin.material_override = (_materials[tint] as StandardMaterial3D).duplicate()
		twin.set_meta("glow", Wireframe.glow_for(mesh.surface_get_array_len(0) / 2, float(wire.glow_reference)))
	twin.global_transform = node.global_transform
	alive[key] = true
	return true


static func _yaw(contact: Dictionary) -> float:
	var velocity: Vector3 = contact.get("velocity", Vector3.ZERO)
	if str(contact.kind) in ["plane", "missile", "drone"] and Vector2(velocity.x, velocity.z).length() > .5:
		return atan2(velocity.z, velocity.x)
	return float(contact.get("heading", 0.0))


## A symbol (data/symbols.json) facing the camera, the same size on screen near or far.
func _symbol(camera: Camera3D, kind: String, at: Vector3, colour: Color) -> void:
	if camera == null: return
	var size := camera.global_position.distance_to(at) * symbol_scale
	var right := camera.global_basis.x * size
	var up := camera.global_basis.y * size
	var centre := at + up * symbol_lift
	var glyph := Style.symbol(kind)
	for i: int in range(0, glyph.size(), 2):
		_line(centre + right * glyph[i].x + up * glyph[i].y, centre + right * glyph[i + 1].x + up * glyph[i + 1].y, colour)


func _shape(lines: PackedVector3Array, at: Vector3, yaw: float, colour: Color) -> void:
	var basis := Basis(Vector3.UP, -yaw)
	for i: int in range(0, lines.size(), 2):
		_line(at + basis * lines[i], at + basis * lines[i + 1], colour)


func _circle(at: Vector3, radius: float, colour: Color, segments: int) -> void:
	for i: int in segments:
		var a := TAU * i / segments
		var b := TAU * (i + 1) / segments
		_line(at + Vector3(cos(a), 0, sin(a)) * radius, at + Vector3(cos(b), 0, sin(b)) * radius, colour)


func _dashed(a: Vector3, b: Vector3, colour: Color, dashes: int) -> void:
	for i: int in dashes:
		_line(a.lerp(b, float(i) / dashes), a.lerp(b, (float(i) + .55) / dashes), colour)


func _trails() -> void:
	for id: String in history.wakes:
		var wake: Dictionary = history.wakes[id]
		var points: Array = wake.points
		var colour := Style.colour("own" if wake.kind == "own" else "hostile")
		for i: int in range(1, points.size()):
			var a: Vector3 = points[i - 1]
			var b: Vector3 = points[i]
			_line(Vector3(a.x, .3, a.z), Vector3(b.x, .3, b.z), colour * Color(1, 1, 1, .5 * float(i) / points.size()))
	for id: String in history.tracks:
		var track: Dictionary = history.tracks[id]
		var points: Array = track.points
		var colour := Style.colour("friendly_round" if track.friendly else "threat")
		for i: int in range(1, points.size()):
			_line(points[i - 1], points[i], colour * Color(1, 1, 1, .85 * float(i) / points.size()))


func _draw_blasts(dt: float) -> void:
	for event: Dictionary in feed.events():
		if int(event.id) <= _seen_event: continue
		_seen_event = int(event.id)
		_blasts.append({"at": event.position, "radius": float(event.get("radius", 10.0)), "age": 0.0, "kill": str(event.kind) == "kill"})
	for blast: Dictionary in _blasts:
		blast.age = float(blast.age) + dt
		var t := float(blast.age) / blast_life
		var colour := (Style.colour("blast") if blast.kill else Style.colour("own")) * Color(1, 1, 1, .8 * (1.0 - t))
		_circle(blast.at, float(blast.radius) * (1.0 + t * 4.0), colour, 24)
		if blast.kill: _circle(blast.at, float(blast.radius) * (.5 + t * 2.0), colour, 16)
	_blasts = _blasts.filter(func(blast: Dictionary) -> bool: return float(blast.age) < blast_life)


## For captures (holo_capture.gd): every lines mesh drawn now, as [mesh, world transform, tint].
func line_sources() -> Array:
	var sources := [[_static_mesh, Transform3D.IDENTITY, Color.WHITE], [_live_mesh, Transform3D.IDENTITY, Color.WHITE]]
	for twin: MeshInstance3D in _twins.values():
		sources.append([twin.mesh, twin.global_transform, (twin.material_override as StandardMaterial3D).albedo_color])
	return sources
