extends SceneTree
## Headless captures of the demo, no window:
##   <godot console> --headless --path godot --fixed-fps 60 --script res://tools/capture_demo.gd [-- --scene=trial]
## Runs the demo battle (or the trial run with game models), stops it at moments worth seeing and
## dumps each view's lines (holo_capture.gd) to ../out/<shot>; python
## ../reference/python/holo_render.py ../out turns them into PNGs.
const Capture = preload("res://addons/holo_tactical/holo_capture.gd")
## [name, seconds of battle before it, view, camera]
const SHOTS := [
	["hologram_wide", 10.0, "hologram", {"orbit": 1.1, "elevation": .85, "distance": 8500.0}],
	["hologram_close", 10.0, "hologram", {"orbit": -.7, "elevation": .22, "distance": 900.0}],
	["table", 10.0, "table", {"orbit": 1.4, "radius": .95, "range": 12000.0}],
	["table_zoom", 10.0, "table", {"orbit": 2.2, "radius": .8, "range": 1500.0}],
	["table_pan", 10.0, "table", {"orbit": .9, "radius": .9, "range": 3000.0, "offset": Vector2(2200, 1500), "pick": true}],
	["hologram_escort", 10.0, "hologram", {"orbit": 2.3, "elevation": .32, "distance": 120.0, "focus": "b1"}],
	["hologram_escort2", 10.0, "hologram", {"orbit": -.9, "elevation": .25, "distance": 95.0, "focus": "b3"}],
	["hologram_aircraft", 10.0, "hologram", {"orbit": 2.6, "elevation": .35, "distance": 45.0, "focus": "plane"}],
]

var demo: Node
var shot := 0
var waiting := -1
var out_dir := ""
var prefix := ""


func _initialize() -> void:
	out_dir = ProjectSettings.globalize_path("res://").path_join("../out")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var scene := "res://demo/holo_demo.tscn"
	if "--scene=trial" in OS.get_cmdline_user_args():
		scene = "res://demo/trial.tscn"
		prefix = "trial_"
	demo = load(scene).instantiate()
	root.add_child(demo)


func _process(_delta: float) -> bool:
	if shot >= SHOTS.size(): return true
	var spec: Array = SHOTS[shot]
	if waiting < 0:
		if demo.feed.clock < float(spec[1]): return false
		demo.paused = true
		_frame(spec)
		waiting = 40
		return false
	_frame(spec)
	waiting -= 1
	if waiting > 0: return false
	var view_node: Node3D = demo.table if spec[2] == "table" else demo.holo_world
	Capture.dump(view_node, demo.camera, out_dir.path_join(prefix + str(spec[0])), {"contacts": demo.feed.contacts().size(), "elapsed": demo.feed.clock})
	print("captured ", prefix, spec[0], " at ", snappedf(demo.feed.clock, .1), " s: ", demo.feed.contacts().size(), " contacts")
	if shot == 0:
		var boat: Dictionary = demo.feed.boats[1]
		var plane: Dictionary = demo.feed.planes[0]
		print("  escort ", boat.model_key, " length ", snappedf(float(boat.size), .1), " m beam ", snappedf(float(boat.beam), .1), " · aircraft ", plane.model_key, " span ", snappedf(float(plane.size), .1), " m")
	waiting = -1
	shot += 1
	return false


func _frame(spec: Array) -> void:
	var view: String = spec[2]
	var camera: Dictionary = spec[3]
	if demo.view != view: demo.set_view(view)
	if view == "table":
		demo.table_orbit = camera.orbit
		demo.table_radius = camera.radius
		demo.table.holo_range = camera.range
		demo.table.view_offset = camera.get("offset", Vector2.ZERO)
		if camera.get("pick", false) and demo.table.picked == "":
			# Pick the contact nearest the table's middle, to show the picked symbol and range.
			var best := ""
			var nearest := INF
			for contact: Dictionary in demo.feed.contacts():
				if contact.kind == "own": continue
				var p: Vector2 = demo.table._project(Vector2(contact.position.x, contact.position.z))
				if p.length() < nearest:
					nearest = p.length()
					best = str(contact.id)
			demo.table.picked = best
		demo.table._timer = 0.0
	else:
		demo.orbit = camera.orbit
		demo.elevation = camera.elevation
		demo.distance = camera.distance
		var focus: String = camera.get("focus", "")
		# "plane": the first aircraft still flying.
		if focus == "plane": focus = str(demo.feed.planes[0].id) if demo.focus == "" or not demo.focus.begins_with("p") else demo.focus
		demo.focus = focus
