extends Control
## Holo Tactical demo: the demo feed's made-up battle in three views.
##   1  full-screen hologram (the camera sees only the hologram's layer, with the glow)
##   2  hologram table (a table standing in a dark room of its own layer)
##   3  plain (the primitive models on a flat sea)
## Mouse: right-drag turns the camera, the wheel zooms (on the table: steps its range), on the table
## the left button slides the view or picks, the middle button recentres. Tab puts the camera on the
## next contact (Shift+Tab back on the own ship). Space pauses.
const DemoFeed = preload("res://demo/demo_feed.gd")
const HoloWorld = preload("res://addons/holo_tactical/holo_world.gd")
const HoloTable = preload("res://addons/holo_tactical/holo_table.gd")
const Style = preload("res://addons/holo_tactical/holo_style.gd")
## The table's room: its own layer, out of the battle's way.
const TABLE_LAYER := 1 << 17
const TABLE_AT := Vector3(0, -5000, 0)

var feed := DemoFeed.new()
var view_box: SubViewportContainer
var viewport: SubViewport
var world: Node3D
var camera: Camera3D
var environment: Environment
var holo_world: HoloWorld
var table: HoloTable
var glow: ShaderMaterial
var hud: Label
var view := "hologram"
var paused := false
## Chase camera round the own ship, and the table camera round the table.
var orbit := 2.4
var elevation := .45
var distance := 2600.0
var table_orbit := 1.4
var table_radius := 1.1
var turning := false
var dragging := false
var acted_log := ""
## The contact the chase camera circles ("": the own ship).
var focus := ""


func _ready() -> void:
	view_box = SubViewportContainer.new()
	view_box.stretch = true
	view_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	view_box.gui_input.connect(_view_input)
	add_child(view_box)
	viewport = SubViewport.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view_box.add_child(viewport)
	world = Node3D.new()
	viewport.add_child(world)
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(.55, .68, .76)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(.8, .85, .9)
	var holder := WorldEnvironment.new()
	holder.environment = environment
	world.add_child(holder)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-.9, .6, 0)
	world.add_child(sun)
	var sea := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40000, 40000)
	sea.mesh = plane
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(.12, .3, .4)
	sea.material_override = water
	world.add_child(sea)
	camera = Camera3D.new()
	camera.far = 30000.0
	world.add_child(camera)
	feed.setup(world)
	holo_world = HoloWorld.new()
	world.add_child(holo_world)
	holo_world.setup(feed)
	# The table: a dark disc stand in a room of its own layer, the projection just above it.
	var stand := MeshInstance3D.new()
	var top := CylinderMesh.new()
	top.top_radius = .7
	top.bottom_radius = .7
	top.height = .05
	stand.mesh = top
	stand.layers = TABLE_LAYER
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(.04, .06, .08)
	stand.material_override = dark
	stand.position = TABLE_AT - Vector3(0, .03, 0)
	world.add_child(stand)
	table = HoloTable.new()
	table.layer = TABLE_LAYER
	world.add_child(table)
	table.position = TABLE_AT
	table.setup(feed)
	table.acted.connect(func(kind: String, _at: Vector3, inward: bool) -> void:
		acted_log = kind + (" in" if inward else "") if kind == "zoom" else kind)
	glow = ShaderMaterial.new()
	glow.shader = load("res://addons/holo_tactical/holo_glow.gdshader")
	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_font_size_override("font_size", 16)
	add_child(hud)
	set_view("hologram")


func set_view(next: String) -> void:
	view = next
	holo_world.set_active(false, camera, environment)
	camera.cull_mask = 0xFFFFF & ~TABLE_LAYER
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(.55, .68, .76)
	view_box.material = null
	match view:
		"hologram":
			holo_world.set_active(true, camera, environment)
			view_box.material = glow
		"table":
			camera.cull_mask = TABLE_LAYER
			environment.background_color = Style.colour("background")
			view_box.material = glow


func _process(delta: float) -> void:
	if not paused: feed.step(delta)
	holo_world.update(0.0 if paused else delta)
	table.update(0.0 if paused else delta, view == "table")
	_place_camera()
	hud.text = "1 hologram · 2 table · 3 plain · Tab follow contact · Space pause   [%s]  contacts %d  range %d m  %s%s" % [view, feed.contacts().size(), int(table.holo_range), acted_log, ("  following " + focus) if focus != "" else ""]


func _place_camera() -> void:
	if view == "table":
		var centre := TABLE_AT + Vector3(0, .12, 0)
		camera.near = .02
		camera.fov = 55.0
		camera.position = centre + Vector3(cos(table_orbit) * table_radius, table_radius * .7, sin(table_orbit) * table_radius)
		camera.look_at(centre, Vector3.UP)
		return
	camera.near = .5
	camera.fov = 60.0
	var home: Vector3 = feed.origin().position + Vector3(0, 20, 0)
	var bearing := orbit + float(feed.origin().heading)
	if focus != "":
		var found := false
		for contact: Dictionary in feed.contacts():
			if str(contact.id) == focus:
				home = contact.position
				bearing = orbit
				found = true
		if not found: focus = ""
	camera.position = home + Vector3(cos(bearing) * cos(elevation), sin(elevation), sin(bearing) * cos(elevation)) * distance
	camera.look_at(home, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: set_view("hologram")
			KEY_2: set_view("table")
			KEY_3: set_view("plain")
			KEY_SPACE: paused = not paused
			KEY_TAB:
				if event.shift_pressed:
					focus = ""
					return
				var ids: Array = feed.contacts().filter(func(c: Dictionary) -> bool: return c.kind != "own").map(func(c: Dictionary) -> String: return str(c.id))
				if not ids.is_empty(): focus = ids[(ids.find(focus) + 1) % ids.size()]


func _view_input(event: InputEvent) -> void:
	if view == "table" and event is InputEventMouseButton:
		var at := table.table_hit(camera.project_ray_origin(event.position), camera.project_ray_normal(event.position))
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and at.is_finite():
				dragging = true
				table.begin_drag(at)
			elif not event.pressed and dragging:
				dragging = false
				table.end_drag()
			return
		if event.button_index == MOUSE_BUTTON_MIDDLE and event.pressed and at.is_finite():
			table.recenter()
			return
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			table.step_range(event.button_index == MOUSE_BUTTON_WHEEL_UP)
			return
	if view == "table" and event is InputEventMouseMotion and dragging:
		var at := table.table_hit(camera.project_ray_origin(event.position), camera.project_ray_normal(event.position))
		if at.is_finite(): table.drag_to(at)
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT: turning = event.pressed
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			distance = clampf(distance * (.88 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.14), 20.0, 12000.0)
	if event is InputEventMouseMotion and turning:
		if view == "table": table_orbit -= event.relative.x * .006
		else:
			orbit -= event.relative.x * .006
			elevation = clampf(elevation + event.relative.y * .004, .05, 1.45)
