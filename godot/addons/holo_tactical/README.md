# holo_tactical addon (Godot 4.7+)

Copy this folder to `res://addons/holo_tactical/`. It needs no plugin activation; scripts are
preloaded by path. Spec: `SPEC.md` at the repository root.

| Script | Role |
|---|---|
| `holo_feed.gd` | The interface a game extends: `time`, `origin`, `contacts`, `rounds`, `runners`, `events`, `terrain_contours`, `shoals` |
| `holo_world.gd` | Full-screen hologram. `setup(feed)`, `set_active(on, camera, environment)`, `update(dt)`. Option: `layer` (render layer bit it draws on) |
| `holo_table.gd` | Miniature table. `setup(feed)`, `update(dt, watching)`, `table_hit`, `step_range`, `begin_drag`, `drag_to`, `end_drag`, `pick`, `recenter`, signal `acted(kind, at, inward)`. Options: `radius`, `ranges`, `height`, `layer`, `font` |
| `holo_wireframe.gd` | Feature-edge tracer on a worker thread with a cache: `lines_for(key, node, crease)`, `skip_names`, `forget()` |
| `holo_shapes.gd` | Fallback silhouettes (ship, aircraft, missile) |
| `holo_contours.gd` | Helpers for feeds: `island_rings(height, ...)`, `shoal_lines(depth, ...)` |
| `holo_style.gd` | Loads `data/palette.json` and `data/symbols.json` |
| `holo_history.gd` | Wakes and round tracks sampled from the feed (used by both views) |
| `holo_capture.gd` | Writes a view's lines and camera for headless captures (`dump(view, camera, path)`) |
| `holo_glow.gdshader` | Glow and vignette post-process for the container that shows the 3D view |

Notes:

- The full-screen view swaps the camera's cull mask and the environment's background and fog,
  and puts them back on `set_active(false)`. Keep your game from re-enabling fog every frame while
  it is up.
- Pick a `layer` your game does not use (default `1 << 18`).
- Traced wireframes are cached by `model_key`. Call `holo_wireframe.gd`'s `forget(key)` after
  rebuilding a model under the same key.
