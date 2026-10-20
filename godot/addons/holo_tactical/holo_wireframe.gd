extends RefCounted
## Hologram wireframes traced from a game's own models. Every visible mesh under a node is gathered
## in the node's frame and only its feature edges are kept: outline edges (one face) and creases
## (faces meeting at more than `crease` degrees). The trace runs on a worker thread; until it is done
## lines_for returns null and the caller draws its simple shape. Results are cached by key.
## The algorithm is SPEC.md "Feature edges"; reference/python/holo_edges.py is the same in NumPy.
const CREASE := 32.0
## Vertices closer than this (m) are welded, so split normals and UV seams do not count as edges.
const WELD := .01

## Node names (prefixes) whose meshes are not the model's shape (interiors, decals, effects):
## a mesh under any of them is left out. Set by the game, e.g. ["Interior", "Decal"].
static var skip_names: Array[String] = []
static var _cache: Dictionary = {}
static var _jobs: Dictionary = {}


## The traced lines mesh for `key`, starting the trace from `node` if it is not cached; null until it
## is ready. A larger `crease` keeps fewer edges (small miniatures).
static func lines_for(key: String, node: Node3D, crease: float = CREASE) -> ArrayMesh:
	if _cache.has(key): return _cache[key]
	if _jobs.has(key):
		var job: Dictionary = _jobs[key]
		if not WorkerThreadPool.is_task_completed(int(job.task)): return null
		WorkerThreadPool.wait_for_task_completion(int(job.task))
		_jobs.erase(key)
		var lines: PackedVector3Array = job.result[0]
		var mesh: ArrayMesh = null
		if not lines.is_empty():
			mesh = ArrayMesh.new()
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = lines
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
		_cache[key] = mesh
		return mesh
	if node == null or not node.is_inside_tree(): return null
	var surfaces := gather(node)
	var job := {"result": [PackedVector3Array()]}
	job.task = WorkerThreadPool.add_task(func() -> void: job.result[0] = trace(surfaces, crease))
	_jobs[key] = job
	return null


## Forgets cached traces (all, or one key), e.g. after a model is rebuilt under the same key.
static func forget(key: String = "") -> void:
	if key == "": _cache.clear()
	else: _cache.erase(key)


## Every visible triangle surface under `root` as [vertices in root's frame, indices].
static func gather(root: Node3D) -> Array:
	var surfaces := []
	var to_root := root.global_transform.affine_inverse()
	for item: Node in root.find_children("*", "MeshInstance3D", true, false):
		var instance := item as MeshInstance3D
		# Flat quads and planes are decals and screens, immediate meshes drawn effects.
		if instance.mesh == null or not instance.is_visible_in_tree() or instance.mesh is PlaneMesh or instance.mesh is QuadMesh or instance.mesh is ImmediateMesh: continue
		if _skipped(instance, root): continue
		var frame := to_root * instance.global_transform
		for index: int in instance.mesh.get_surface_count():
			if instance.mesh is ArrayMesh and (instance.mesh as ArrayMesh).surface_get_primitive_type(index) != Mesh.PRIMITIVE_TRIANGLES: continue
			var arrays := instance.mesh.surface_get_arrays(index)
			var source: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var vertices := PackedVector3Array()
			vertices.resize(source.size())
			for i: int in source.size(): vertices[i] = frame * source[i]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if indices.is_empty():
				indices.resize(vertices.size())
				for i: int in vertices.size(): indices[i] = i
			surfaces.append([vertices, indices])
	return surfaces


static func _skipped(node: Node, root: Node) -> bool:
	while node != null and node != root:
		for name: String in skip_names:
			if str(node.name).begins_with(name): return true
		node = node.get_parent()
	return false


## Feature edges of gathered surfaces as line segment pairs (worker thread safe: data only).
static func trace(surfaces: Array, crease: float = CREASE) -> PackedVector3Array:
	var welded: Dictionary = {}
	var points := PackedVector3Array()
	var edges: Dictionary = {}
	var limit := cos(deg_to_rad(crease))
	for surface: Array in surfaces:
		var vertices: PackedVector3Array = surface[0]
		var indices: PackedInt32Array = surface[1]
		var ids := PackedInt32Array()
		ids.resize(vertices.size())
		for i: int in vertices.size():
			var cell := Vector3i((vertices[i] / WELD).round())
			if not welded.has(cell):
				welded[cell] = points.size()
				points.append(vertices[i])
			ids[i] = welded[cell]
		for t: int in range(0, indices.size() - 2, 3):
			var a := ids[indices[t]]
			var b := ids[indices[t + 1]]
			var c := ids[indices[t + 2]]
			if a == b or b == c or a == c: continue
			var normal := (points[b] - points[a]).cross(points[c] - points[a])
			if normal.length_squared() < 1e-12: continue
			normal = normal.normalized()
			for pair: Vector2i in [Vector2i(a, b), Vector2i(b, c), Vector2i(c, a)]:
				var key := mini(pair.x, pair.y) * 4194304 + maxi(pair.x, pair.y)
				var seen: Array = edges.get(key, [])
				if seen.is_empty(): edges[key] = [normal, 1, false]
				else:
					seen[1] = int(seen[1]) + 1
					if (seen[0] as Vector3).dot(normal) < limit: seen[2] = true
	var lines := PackedVector3Array()
	for key: int in edges:
		var entry: Array = edges[key]
		if int(entry[1]) == 1 or bool(entry[2]):
			lines.append(points[key / 4194304])
			lines.append(points[key % 4194304])
	return lines


## How bright a wireframe of `edges` edges may glow before its lines add up into a blob:
## sqrt(reference / edges), within `limits`.
static func glow_for(edges: int, reference: float = 1600.0, limits: Vector2 = Vector2(.18, 1.0)) -> float:
	return clampf(sqrt(reference / maxf(float(edges), 1.0)), limits.x, limits.y)
