extends RefCounted
## What a hologram shows, asked of the game each frame. The views (holo_world.gd, holo_table.gd)
## only ever read this; a game subclasses it and maps its own simulation onto it. Every method
## has a harmless default, so a feed implements only what its game has.
##
## Conventions (SPEC.md "Coordinates"): metres, Y up. A heading h points the way
## Vector3(cos h, 0, sin h): Basis(Vector3.UP, -h) turns a model whose bow is +X onto it.
## Plan points (x, z) are Vector2(world.x, world.z).

## Kinds of contact the views know: their symbol (holo_symbols.gd) and fallback silhouette.
const KINDS := ["own", "plane", "missile", "drone", "boat", "boss"]


## Seconds of game time, for flicker and pulses (any steadily rising clock will do).
func time() -> float:
	return 0.0


## The reference the views centre on (the player's ship): {"position": Vector3, "heading": float}.
func origin() -> Dictionary:
	return {"position": Vector3.ZERO, "heading": 0.0}


## Everything to draw this frame, the own ship included (kind "own"). Each entry:
##   id: String           stable while the contact lives
##   kind: String         one of KINDS
##   position: Vector3    drawn position (interpolated, if the game interpolates)
##   velocity: Vector3    m/s, for predicted paths (ZERO: none)
##   heading: float       for the fallback silhouette (ships: hull heading; aircraft: may be 0)
##   size: float          length (ships) or wingspan (aircraft), metres
##   beam: float          ships only, metres (optional)
##   node: Node3D         optional: the game's model, traced into a wireframe (holo_wireframe.gd)
##   model_key: String    optional: cache key for that trace (same look, same key)
##   closing: bool        optional: drawn hotter on the table when it closes on the origin
func contacts() -> Array[Dictionary]:
	return []


## Rounds in flight worth a track: [{"id": String, "position": Vector3, "friendly": bool}].
func rounds() -> Array[Dictionary]:
	return []


## Underwater runners (torpedoes): [{"position": Vector3, "velocity": Vector3}].
func runners() -> Array[Dictionary]:
	return []


## Blasts since the views last asked: [{"id": int, "kind": "kill"|"hit"|"splash", "position": Vector3,
## "radius": float}]. Ids rise; the views remember the highest seen.
func events() -> Array[Dictionary]:
	return []


## Land as contour rings in the world plan: [{"level": float (m above sea), "ring": PackedVector2Array}].
## Called rarely (the views cache it); empty for open sea.
func terrain_contours() -> Array[Dictionary]:
	return []


## Shallow-water lines round `centre` (plan), `reach` metres each way: segment pairs, plan coordinates.
## holo_contours.gd traces them from a depth function if the game has one.
func shoals(_centre: Vector2, _reach: float) -> PackedVector2Array:
	return PackedVector2Array()
