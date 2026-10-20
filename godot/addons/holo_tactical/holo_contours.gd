extends RefCounted
## Helpers a feed can use to give the holograms land and shallows (SPEC.md "Contours"):
## - island_rings: contour rings round a summit, from any ground-height function, by searching
##   along rays for where the ground falls below each level (islands that rise to one top).
## - shoal_lines: depth contours on a plan grid by marching squares, from any depth function.
## reference/python/holo_contours.py is the same in NumPy.


## Rings at `levels` (metres) round `centre` (plan), out to `reach`: [{"level", "ring"}].
## `height` is Callable(Vector2 plan) -> float (metres; -INF or below 0 off the land).
static func island_rings(height: Callable, centre: Vector2, reach: float, levels: Array, rays: int = 48, steps: int = 14) -> Array[Dictionary]:
	var rings: Array[Dictionary] = []
	for level: float in levels:
		var ring := PackedVector2Array()
		for i: int in rays:
			var direction := Vector2.from_angle(TAU * i / rays)
			var inside := 0.0
			var outside := reach
			for step: int in steps:
				var middle := (inside + outside) * .5
				if float(height.call(centre + direction * middle)) >= level: inside = middle
				else: outside = middle
			ring.append(centre + direction * inside)
		rings.append({"level": level, "ring": ring})
	return rings


## Depth contours at `levels` (metres of water) round `centre`, `reach` each way, on a cells x cells
## grid: segment pairs in plan coordinates. `depth` is Callable(Vector2 plan) -> float.
static func shoal_lines(depth: Callable, centre: Vector2, reach: float, levels: Array, cells: int = 36) -> PackedVector2Array:
	var lines := PackedVector2Array()
	var cell := reach * 2.0 / cells
	var corner := centre - Vector2(reach, reach)
	var grid: Array[PackedFloat32Array] = []
	for j: int in cells + 1:
		var row := PackedFloat32Array()
		for i: int in cells + 1:
			row.append(float(depth.call(corner + Vector2(i, j) * cell)))
		grid.append(row)
	for level: float in levels:
		for j: int in cells:
			for i: int in cells:
				var v := [grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]]
				var p := [corner + Vector2(i, j) * cell, corner + Vector2(i + 1, j) * cell, corner + Vector2(i + 1, j + 1) * cell, corner + Vector2(i, j + 1) * cell]
				var crossings := PackedVector2Array()
				for k: int in 4:
					var a: float = v[k]
					var b: float = v[(k + 1) % 4]
					if (a < level) != (b < level):
						crossings.append((p[k] as Vector2).lerp(p[(k + 1) % 4], (level - a) / (b - a)))
				if crossings.size() >= 2: lines.append_array([crossings[0], crossings[1]])
				if crossings.size() == 4: lines.append_array([crossings[2], crossings[3]])
	return lines
