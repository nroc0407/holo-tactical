extends RefCounted
## Captures without a picture (SPEC.md "Line dump"): a headless engine renders nothing, but the
## holograms are lines the game builds itself, so a view's segments, their colours and the camera are
## written out and reference/python/holo_render.py draws them (additive lines, glow, vignette).
## Files: <path>.json (header) and <path>.bin (float32 xyz per vertex, then float32 rgba per vertex;
## consecutive vertex pairs are segments).


## Dumps a view (holo_world.gd or holo_table.gd: anything with line_sources()) seen by `camera`.
## A table is written in its own frame, so the camera is moved into that frame too.
static func dump(view: Node3D, camera: Camera3D, path: String, extra: Dictionary = {}) -> void:
	var verts := PackedFloat32Array()
	var colours := PackedFloat32Array()
	var table: bool = view.has_method("table_hit")
	var eye := camera.global_transform
	if table: eye = view.global_transform.affine_inverse() * eye
	for source: Array in view.call("line_sources"):
		_add(verts, colours, source[0], source[1], source[2])
	var file := FileAccess.open(path + ".bin", FileAccess.WRITE)
	file.store_buffer(verts.to_byte_array())
	file.store_buffer(colours.to_byte_array())
	file.close()
	var header := {"view": "table" if table else "hologram", "vertices": verts.size() / 3, "fov": camera.fov, "near": camera.near,
		"basis": [eye.basis.x.x, eye.basis.x.y, eye.basis.x.z, eye.basis.y.x, eye.basis.y.y, eye.basis.y.z, eye.basis.z.x, eye.basis.z.y, eye.basis.z.z],
		"origin": [eye.origin.x, eye.origin.y, eye.origin.z]}
	header.merge(extra)
	var json := FileAccess.open(path + ".json", FileAccess.WRITE)
	json.store_string(JSON.stringify(header))
	json.close()


static func _add(verts: PackedFloat32Array, colours: PackedFloat32Array, mesh: Mesh, frame: Transform3D, tint: Color) -> void:
	if mesh == null or mesh.get_surface_count() == 0: return
	var arrays := mesh.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var tints: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	for i: int in points.size():
		var p := frame * points[i]
		verts.append_array([p.x, p.y, p.z])
		var c := (tints[i] if i < tints.size() else Color.WHITE) * tint
		colours.append_array([c.r, c.g, c.b, c.a])
