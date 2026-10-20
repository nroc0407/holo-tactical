# Holo Tactical specification

An engine-neutral specification of a tactical hologram that redraws a battle from data. To port it,
work from this document, the JSON in `godot/addons/holo_tactical/data/` and the reference code in
`reference/python/`. The Godot 4 addon (`godot/addons/holo_tactical/`) is one implementation of it.
A Korean version is in `SPEC.ko.md`.

## 1. Coordinates

- Metres, Y up.
- A heading `h` points along `(cos h, 0, sin h)`. A model whose bow is +X faces it after a rotation
  of `-h` about Y.
- Plan coordinates are `(x, z)`.
- Model axes: +X ahead, +Y up, +Z right.

## 2. Feed (what the game provides)

The hologram never reads the game's simulation. The game implements one feed answering these each
frame (Godot: extend `holo_feed.gd`). Every item may be empty.

| Item | Shape | Meaning |
|---|---|---|
| `time()` | seconds | Clock for flicker and pulses; any steadily rising clock |
| `origin()` | `{position, heading}` | What the views centre on, usually the player's ship |
| `contacts()` | list | Everything to draw, the own ship included (`kind: "own"`) |
| `rounds()` | list of `{id, position, friendly}` | Rounds in flight that leave a track |
| `runners()` | list of `{position, velocity}` | Underwater runners (torpedoes): a predicted dashed line on the surface |
| `events()` | list of `{id, kind, position, radius}` | Blasts, `kind` is `kill`, `hit` or `splash`. Ids rise; views remember the highest seen |
| `terrain_contours()` | list of `{level, ring}` | Land contours; `ring` is a plan polygon. Called rarely and cached |
| `shoals(centre, reach)` | segment pairs | Shallow-water lines round a centre, plan coordinates |

A contact has:

- `id` (string, stable while it lives)
- `kind`: one of `own`, `plane`, `missile`, `drone`, `boat`, `boss`
- `position`, `velocity` (m/s), `heading`
- `size`: length for ships, wingspan for aircraft (m)
- `beam`: ships only, optional
- `node`: optional, the model to trace into a wireframe
- `model_key`: optional, cache key for that trace
- `closing`: optional, whether it is closing on the origin

## 3. Look (`data/palette.json`)

- **Background:** near-black navy.
- **Lines:** unshaded and additive, so overlaps brighten.
- **Colours:** own side and land cyan, enemies orange, threats (missiles, enemy flagship) red,
  friendly round tracks pale cyan, shallows blue, blasts yellow.
- **Flicker:** brightness `1 - amount + amount * sin(t * rate)`.
- **Text:** as little as possible. Symbols (section 4) stand in for labels; only the table's
  picked contact shows its range in text.

## 4. Symbols (`data/symbols.json`)

Segment lists after the hostile frames of military symbology, in a unit square (+x right, +y up),
drawn as camera-facing billboards.

- Air contacts: the upper half of a diamond, with an inner mark telling aircraft (^), missile
  (arrow) and drone (square) apart.
- Surface contacts: a diamond; the enemy flagship a double diamond.
- Own ship: a circle.
- Selection bracket: `picked`.
- In the full-screen view the half size is camera distance x 0.012, so symbols keep one size on
  screen.

## 5. Silhouettes (fallback shapes)

Used until a wireframe trace is ready, or when there is no model.

- Ship: a hull with a pointed bow and square stern (waterline and deck outlines with corner
  posts), a superstructure box amidships and a mast.
- Aircraft: fuselage, swept wings, tailplane and fin.
- Missile: body with cruciform tail fins.

Proportions follow `holo_shapes.gd`.

## 6. Feature edges (wireframe tracing)

Reference implementation: `reference/python/holo_edges.py`.

1. Gather every visible triangle mesh under the model node, in the model's frame. Leave out flat
   planes and quads (decals, screens), immediate-mode meshes (effects), and anything under a node
   whose name starts with one of the skip names (interiors and the like).
2. Weld vertices within 1 cm, so split normals and UV seams do not count as edges.
3. Keep only edges used by one face (outlines) and edges where two faces meet at more than
   `crease` degrees (32 full-screen, 48 on the table). The angle is measured against the first
   face that used the edge.
4. Trace on a worker thread and cache by key. For scale: a 70k-triangle warship gave 34k edges in
   about 0.35 s.
5. Brightness: dense wireframes add up into a blob, so alpha is multiplied by
   `clamp(sqrt(reference / edges), 0.18, 1)` with reference 1600 full-screen and 700 on the table.

## 7. Contours

Reference implementation: `reference/python/holo_contours.py`.

- **Island rings:** from the summit along 48 rays, bisect 14 times for the distance at which the
  ground falls below each level. Suits islands that rise to one top.
- **Shoal lines:** marching squares on a plan grid at 20 m and 50 m of water.

## 8. Full-screen view

- The game's own camera keeps working; it is switched to see only the hologram layer, with the
  palette background and fog off. The game must not switch fog or underwater lens effects back on
  every frame while the hologram is up (in the source game this washed the view out white).
- **Static layer:** laid round the camera, rebuilt after the camera moves 600 m.
  - Sea grid: 100 m spacing out to 4 km and 1 km out to 16 km, fading with distance.
  - Island contours, with ribs to the next level on every sixth point.
  - Shallows, 1 m below the surface.
- **Live layer:** redrawn every frame.
  - Contacts: a wireframe twin following the model's transform, or the silhouette.
  - Air contacts: a drop line to the sea with a ring, a predicted dashed path (aircraft 20 s,
    missiles 10 s) and an end ring.
  - Symbols; a pulse from the origin every 4 s out to 6 km; ship wakes (60 points, 0.5 s apart);
    round tracks (40 points, 0.08 s apart).
  - Runner prediction (30 s); blast rings (1.6 s, a double ring for a kill).

## 9. Table (miniature)

- Placed at the middle of a table top, radius 0.62 m, projected head-up: the origin's heading
  points along +X.
- **Ranges:** 350, 700, 1500, 3000, 6000, 12000 and 24000 m, stepped through.
- **Scales:**
  - Horizontal: radius / range.
  - Height: max(0.45 m per 4 km, horizontal scale); drawn at floor + 0.04 + altitude x height
    scale, clipped at 1 m.
  - Silhouettes: the larger of a minimum size (own ship 0.055 m, ships 0.02-0.042 m, aircraft
    0.024 m, missiles 0.016 m) and true scale.
  - Land relief: x1.3, or true scale when zoomed in far enough for that to be larger.
- **API:** every call emits `acted(kind, world point, inward)`, so the game can animate whoever
  works the table.
  - `table_hit(origin, direction)`: table plan point, or none
  - `step_range(inward)`: emits zoom
  - `begin_drag` / `drag_to`: emits pan. The view's centre slides the other way so the grabbed
    point stays under the sight (at most 30 km off).
  - `end_drag`: a press that moved less than 1.2 cm is a click and picks at that point.
  - `pick` (3.5 cm radius, nearest contact), `recenter`: emits center
- **Display:** three range rings, twelve bearing ticks and a sweep on the floor. When the view has
  slid the origin off the table, a chevron at the edge points to it. The picked contact gets a
  bracket, a pulsing ring and its range in text.
- Redrawn every 0.15 s while someone watches; history is recorded all the time.

## 10. Glow

- A post-process over the 3D view only; HUD drawn above it stays sharp.
- 20 golden-angle disc samples from a small disc (0.006 of the picture height, gain 0.85) and a
  wide one (0.03, gain 0.55), the discs turned per pixel so their steps blur into fine noise
  instead of rings.
- Vignette 0.35.
- Engines with HDR bloom may use that instead. Plain GLSL version: `shaders/holo_glow.glsl`.

## 11. Line dump (headless captures)

- Two files, `<name>.json` (header) and `<name>.bin`.
  - bin: float32 xyz for every vertex, then float32 rgba for every vertex. Consecutive vertex
    pairs are segments.
  - Header: `vertices`, `fov` (vertical, degrees), `near`, `basis` (camera X, Y, Z axes, nine
    numbers), `origin`, plus any notes.
  - A table dump is written in the table's frame, with the camera moved into that frame too.
- `reference/python/holo_render.py` turns dumps into PNGs: additive lines, a three-level Gaussian
  glow, vignette and dithering.

## 12. Porting checklist

1. Implement the feed. Contacts and an origin alone already give a picture.
2. A line renderer: unshaded, additive, vertex-coloured line meshes.
3. Layers and camera culling: a hologram-only mode, with fog and underwater effects held off.
4. Feature-edge tracing on a worker thread, with a cache.
5. Symbols and palette read from the data files.
6. The glow post-process.
7. Optional: the table and its action signal, and the headless line dump.
