extends "res://addons/holo_tactical/holo_feed.gd"
## A made-up battle for the demo and the headless captures: the own ship steams in a wide circle,
## an enemy group closes from one side, aircraft come in from three bearings and fire missiles,
## our rounds go up at the nearest aircraft and some of them kill it. Models are Godot primitive
## meshes, so the wireframe tracer has something real to trace, or, when `boat_models` and
## `plane_models` name glTF scenes (the trial scene: demo/models/), those models, sized from their
## own bounds. Deterministic (fixed seed).
const Contours = preload("res://addons/holo_tactical/holo_contours.gd")
const ISLANDS := [
	{"centre": Vector2(3800, 2500), "height": 160.0, "sigma": 420.0},
	{"centre": Vector2(-2900, -3200), "height": 210.0, "sigma": 520.0},
	{"centre": Vector2(6100, -2600), "height": 120.0, "sigma": 360.0},
]
const BOATS := 9
const PLANES := 36
const ROUND_SPEED := 650.0

var root: Node3D
var clock := 0.0
var rng := RandomNumberGenerator.new()
var own := {}
var boats: Array[Dictionary] = []
var planes: Array[Dictionary] = []
var missiles: Array[Dictionary] = []
var shots: Array[Dictionary] = []
var torpedoes: Array[Dictionary] = []
var blasts: Array[Dictionary] = []
var serial := 0
var fire_timer := 0.0
var _contours: Array[Dictionary] = []
## glTF scenes for the escorts (the enemy flagship stays a primitive) and the aircraft; empty: primitives.
var boat_models: Array[String] = []
var plane_models: Array[String] = []
var _scenes: Dictionary = {}


func setup(root_value: Node3D) -> void:
	root = root_value
	rng.seed = 20261020
	own = {"id": "own", "kind": "own", "position": Vector3(0, 0, 0), "heading": 0.0, "size": 220.0, "beam": 30.0,
		"node": _ship_model(220.0, 30.0, true), "model_key": "demo_own"}
	var raid := rng.randf() * TAU
	for i: int in BOATS:
		var bearing := raid + PI / 3.0 + rng.randf_range(-.6, .6)
		var length := 180.0 if i == 0 else rng.randf_range(60.0, 140.0)
		var at := Vector3(cos(bearing), 0, sin(bearing)) * rng.randf_range(2600, 5600)
		var boat := {"id": "b%d" % i, "kind": "boss" if i == 0 else "boat", "position": at, "heading": atan2(-at.z, -at.x),
			"size": length, "beam": length * .13, "speed": rng.randf_range(8, 14)}
		if i > 0 and not boat_models.is_empty():
			var path: String = boat_models[i % boat_models.size()]
			boat.node = _model(path)
			var bounds := _bounds(boat.node)
			boat.size = bounds.size.x
			boat.beam = bounds.size.z
			boat.model_key = path.get_file().get_basename()
		else:
			boat.node = _ship_model(length, length * .13, false)
			boat.model_key = "demo_boss" if i == 0 else "demo_boat_%d" % int(length / 20.0)
		boats.append(boat)
	for i: int in PLANES: _spawn_plane(raid + TAU / 3.0 * (i % 3) + rng.randf_range(-.4, .4))
	# Islands: each rises to one summit; its rings are traced from the height function.
	for island: Dictionary in ISLANDS:
		var levels := [2.0, float(island.height) * .25, float(island.height) * .5, float(island.height) * .75]
		_contours.append_array(Contours.island_rings(_height, island.centre, float(island.sigma) * 3.5, levels))


func _spawn_plane(bearing: float) -> void:
	serial += 1
	var at := Vector3(cos(bearing), 0, sin(bearing)) * rng.randf_range(3200, 7500)
	at.y = rng.randf_range(60, 900)
	var span := rng.randf_range(11, 18)
	var key := "demo_plane_%d" % int(span / 3.0)
	var node: Node3D
	if plane_models.is_empty():
		node = _plane_model(span)
	else:
		var path: String = plane_models[serial % plane_models.size()]
		node = _model(path)
		span = _bounds(node).size.z
		key = path.get_file().get_basename()
	planes.append({"id": "p%d" % serial, "kind": "drone" if serial % 7 == 0 else "plane", "position": at, "velocity": Vector3.ZERO,
		"size": span, "speed": rng.randf_range(120, 210), "node": node, "model_key": key, "launched": false})


## Ground height of the islands (Gaussian summits; below 0 is sea).
func _height(at: Vector2) -> float:
	var h := -30.0
	for island: Dictionary in ISLANDS:
		var d := at.distance_to(island.centre) / float(island.sigma)
		h = maxf(h, float(island.height) * exp(-d * d * .5) - 8.0)
	return h


func _depth(at: Vector2) -> float:
	var shallow := 0.0
	for island: Dictionary in ISLANDS:
		var d := at.distance_to(island.centre) / (float(island.sigma) * 2.4)
		shallow = maxf(shallow, exp(-d * d * .5))
	return 80.0 * (1.0 - shallow)


func step(dt: float) -> void:
	clock += dt
	# The own ship: a wide circle at 15 m/s.
	own.heading = float(own.heading) + dt * .012
	own.position = (own.position as Vector3) + Vector3(cos(own.heading), 0, sin(own.heading)) * 15.0 * dt
	var home: Vector3 = own.position
	for boat: Dictionary in boats:
		var to := home - (boat.position as Vector3)
		var aim := atan2(to.z, to.x) + (PI * .45 if to.length() < 2200.0 else 0.0)
		boat.heading = lerp_angle(float(boat.heading), aim, dt * .05)
		boat.velocity = Vector3(cos(boat.heading), 0, sin(boat.heading)) * float(boat.speed)
		boat.position = (boat.position as Vector3) + boat.velocity * dt
		if rng.randf() < dt * .015 and torpedoes.size() < 6:
			torpedoes.append({"position": boat.position, "velocity": to.normalized() * 22.0, "life": 40.0})
	for plane: Dictionary in planes:
		var to := home + Vector3(0, plane.position.y, 0) - (plane.position as Vector3)
		var flat := Vector3(to.x, 0, to.z)
		var direction := flat.normalized()
		if flat.length() < 1600.0: direction = direction.rotated(Vector3.UP, PI * .5)
		plane.velocity = (plane.velocity as Vector3).lerp(direction * float(plane.speed), dt * .8)
		plane.position = (plane.position as Vector3) + plane.velocity * dt
		if not bool(plane.launched) and flat.length() < 4200.0 and rng.randf() < dt * .2:
			plane.launched = true
			serial += 1
			missiles.append({"id": "m%d" % serial, "kind": "missile", "position": plane.position, "velocity": Vector3.ZERO, "size": 6.0, "life": 30.0})
	for missile: Dictionary in missiles:
		var to: Vector3 = home + Vector3(0, 8, 0) - (missile.position as Vector3)
		missile.velocity = to.normalized() * 290.0
		missile.position = (missile.position as Vector3) + missile.velocity * dt
		missile.life = float(missile.life) - dt
		if to.length() < 300.0 and rng.randf() < dt * 3.0: _blast("hit", missile.position, 18.0); missile.life = 0.0
	missiles = missiles.filter(func(m: Dictionary) -> bool: return float(m.life) > 0.0)
	# Our rounds go up at the nearest aircraft; some arrive and kill it.
	fire_timer -= dt
	if fire_timer <= 0.0 and not planes.is_empty():
		fire_timer = .6
		var target: Dictionary = planes[0]
		for plane: Dictionary in planes:
			if (plane.position as Vector3).distance_to(home) < (target.position as Vector3).distance_to(home): target = plane
		serial += 1
		shots.append({"id": "r%d" % serial, "position": home + Vector3(0, 20, 0), "target": target, "friendly": true})
	for shot: Dictionary in shots:
		var target: Dictionary = shot.target
		var to: Vector3 = (target.position as Vector3) - (shot.position as Vector3)
		shot.position = (shot.position as Vector3) + to.normalized() * minf(ROUND_SPEED * dt, to.length())
		if to.length() < 30.0:
			shot.done = true
			if planes.has(target) and rng.randf() < .55:
				_blast("kill", target.position, 24.0)
				(target.node as Node).queue_free()
				planes.erase(target)
				_spawn_plane(rng.randf() * TAU)
	shots = shots.filter(func(s: Dictionary) -> bool: return not s.get("done", false) and planes.has(s.target))
	for torpedo: Dictionary in torpedoes:
		torpedo.position = (torpedo.position as Vector3) + (torpedo.velocity as Vector3) * dt
		torpedo.life = float(torpedo.life) - dt
	torpedoes = torpedoes.filter(func(t: Dictionary) -> bool: return float(t.life) > 0.0)
	_place(own)
	for boat: Dictionary in boats: _place(boat)
	for plane: Dictionary in planes: _place(plane)


func _blast(kind: String, at: Vector3, radius: float) -> void:
	serial += 1
	blasts.append({"id": serial, "kind": kind, "position": at, "radius": radius})
	if blasts.size() > 64: blasts.pop_front()


func _place(contact: Dictionary) -> void:
	var node: Node3D = contact.get("node")
	if node == null or not is_instance_valid(node): return
	var velocity: Vector3 = contact.get("velocity", Vector3.ZERO)
	var heading := atan2(velocity.z, velocity.x) if str(contact.kind) in ["plane", "drone"] and velocity.length() > 1.0 else float(contact.get("heading", 0.0))
	node.global_transform = Transform3D(Basis(Vector3.UP, -heading), contact.position)


# --- Models: glTF scenes or primitive meshes, +X forward ----------------------------------------

## A glTF model scene, placed under the root.
func _model(path: String) -> Node3D:
	if not _scenes.has(path): _scenes[path] = load(path)
	var node: Node3D = (_scenes[path] as PackedScene).instantiate()
	root.add_child(node)
	return node


## Bounds of every mesh under a model, in the model's own frame (length along X, beam along Z).
static func _bounds(model: Node3D) -> AABB:
	var to_model := model.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	for item: Node in model.find_children("*", "MeshInstance3D", true, false):
		var part := (to_model * (item as MeshInstance3D).global_transform) * (item as MeshInstance3D).get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box


func _part(parent: Node3D, mesh: Mesh, at: Vector3) -> void:
	var item := MeshInstance3D.new()
	item.mesh = mesh
	item.position = at
	parent.add_child(item)


func _ship_model(length: float, beam: float, own_ship: bool) -> Node3D:
	var ship := Node3D.new()
	root.add_child(ship)
	var hull := PrismMesh.new()
	hull.size = Vector3(beam, length * .07, length)
	hull.left_to_right = .5
	var hull_node := MeshInstance3D.new()
	hull_node.mesh = hull
	hull_node.rotation = Vector3(0, PI * .5, PI)
	hull_node.position = Vector3(0, length * .035, 0)
	ship.add_child(hull_node)
	var deck := BoxMesh.new()
	deck.size = Vector3(length * .8, length * .012, beam * .95)
	_part(ship, deck, Vector3(-length * .05, length * .075, 0))
	var tower := BoxMesh.new()
	tower.size = Vector3(length * .16, length * .09, beam * .5)
	_part(ship, tower, Vector3(length * .02, length * .13, 0))
	var funnel := CylinderMesh.new()
	funnel.top_radius = beam * .1
	funnel.bottom_radius = beam * .12
	funnel.height = length * .07
	funnel.radial_segments = 10
	_part(ship, funnel, Vector3(-length * .1, length * .14, 0))
	for x: float in ([.3, -.32] if own_ship else [.3]):
		var turret := CylinderMesh.new()
		turret.top_radius = beam * .2
		turret.bottom_radius = beam * .22
		turret.height = length * .025
		turret.radial_segments = 12
		_part(ship, turret, Vector3(length * x, length * .095, 0))
		var barrel := BoxMesh.new()
		barrel.size = Vector3(length * .09, length * .006, beam * .05)
		_part(ship, barrel, Vector3(length * (x + .06 * signf(x)), length * .1, 0))
	return ship


func _plane_model(span: float) -> Node3D:
	var plane := Node3D.new()
	root.add_child(plane)
	var body := CapsuleMesh.new()
	body.radius = span * .045
	body.height = span * .8
	body.radial_segments = 8
	body.rings = 2
	var body_node := MeshInstance3D.new()
	body_node.mesh = body
	body_node.rotation = Vector3(0, 0, PI * .5)
	plane.add_child(body_node)
	var wing := BoxMesh.new()
	wing.size = Vector3(span * .18, span * .015, span)
	_part(plane, wing, Vector3(span * .02, 0, 0))
	var tail := BoxMesh.new()
	tail.size = Vector3(span * .1, span * .012, span * .38)
	_part(plane, tail, Vector3(-span * .34, 0, 0))
	var fin := BoxMesh.new()
	fin.size = Vector3(span * .1, span * .14, span * .012)
	_part(plane, fin, Vector3(-span * .34, span * .07, 0))
	return plane


# --- The feed ------------------------------------------------------------------------------------

func time() -> float:
	return clock


func origin() -> Dictionary:
	return {"position": own.position, "heading": own.heading}


func contacts() -> Array[Dictionary]:
	var list: Array[Dictionary] = [own]
	var home: Vector3 = own.position
	for boat: Dictionary in boats:
		var offset: Vector3 = (boat.position as Vector3) - home
		boat.closing = (boat.get("velocity", Vector3.ZERO) as Vector3).dot(offset) < 0.0
		list.append(boat)
	list.append_array(planes)
	list.append_array(missiles)
	return list


func rounds() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for shot: Dictionary in shots: list.append({"id": shot.id, "position": shot.position, "friendly": true})
	for missile: Dictionary in missiles: list.append({"id": missile.id, "position": missile.position, "friendly": false})
	return list


func runners() -> Array[Dictionary]:
	return torpedoes


func events() -> Array[Dictionary]:
	return blasts


func terrain_contours() -> Array[Dictionary]:
	return _contours


func shoals(centre: Vector2, reach: float) -> PackedVector2Array:
	return Contours.shoal_lines(_depth, centre, reach, [20.0, 50.0], 32)
