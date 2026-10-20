extends RefCounted
## Wakes behind ships and tracks behind rounds in flight, sampled from a feed (holo_feed.gd) so they
## are there the moment a view opens. Positions are world points.
const Feed = preload("res://addons/holo_tactical/holo_feed.gd")
## Ships leave wakes; one sample per WAKE_STEP s, WAKE_POINTS kept. Rounds: TRACK_STEP s, TRACK_POINTS.
const WAKE_KINDS := ["own", "boat", "boss"]
var wake_step := .5
var wake_points := 60
var track_step := .08
var track_points := 40

## id -> {"points": Array[Vector3], "kind" or "friendly"}
var wakes: Dictionary = {}
var tracks: Dictionary = {}
var _wake_timer := 0.0
var _track_timer := 0.0


func record(feed: Feed, dt: float) -> void:
	_wake_timer -= dt
	if _wake_timer <= 0.0:
		_wake_timer = wake_step
		var alive := {}
		for contact: Dictionary in feed.contacts():
			if not str(contact.kind) in WAKE_KINDS: continue
			var id := str(contact.id)
			alive[id] = true
			_sample(wakes, id, contact.position, wake_points, {"kind": contact.kind})
		_prune(wakes, alive)
	_track_timer -= dt
	if _track_timer <= 0.0:
		_track_timer = track_step
		var alive := {}
		for shot: Dictionary in feed.rounds():
			var id := str(shot.id)
			alive[id] = true
			_sample(tracks, id, shot.position, track_points, {"friendly": bool(shot.get("friendly", true))})
		_prune(tracks, alive)


static func _sample(store: Dictionary, id: String, at: Vector3, keep: int, info: Dictionary) -> void:
	if not store.has(id):
		store[id] = info.duplicate()
		store[id].points = []
	var points: Array = store[id].points
	points.append(at)
	if points.size() > keep: points.pop_front()


static func _prune(store: Dictionary, alive: Dictionary) -> void:
	for id: String in store.keys():
		if not alive.has(id): store.erase(id)
