extends "res://demo/holo_demo.gd"
## Trial run: the demo battle with real game models in place of the primitive ones: the
## escorts are the small craft and the aircraft the small types from the Theseus project
## (demo/models/: torpedo boat, patrol boat, missile boat; small bomber, small torpedo bomber,
## rocket fighter). Everything else is the demo's: 1 hologram, 2 table, 3 plain.
const BOAT_MODELS: Array[String] = ["res://demo/models/torpedo_boat.glb", "res://demo/models/patrol_boat.glb", "res://demo/models/missile_boat.glb"]
const PLANE_MODELS: Array[String] = ["res://demo/models/bomber_small.glb", "res://demo/models/torpedo_small.glb", "res://demo/models/rocket_fighter.glb"]


func _init() -> void:
	feed.boat_models = BOAT_MODELS
	feed.plane_models = PLANE_MODELS


func _ready() -> void:
	super._ready()
	var note := Label.new()
	note.text = "TRIAL · models: torpedo / patrol / missile boat, small bomber / torpedo bomber / rocket fighter"
	note.position = Vector2(16, 40)
	note.add_theme_font_size_override("font_size", 14)
	add_child(note)
