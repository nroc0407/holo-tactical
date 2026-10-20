"""Feature edges of a triangle mesh (SPEC.md "Feature edges"): the reference for porting the
hologram wireframe tracer to any engine. Same rules as godot/addons/holo_tactical/holo_wireframe.gd:
weld vertices closer than WELD, keep an edge if one face uses it (outline) or two faces meet at it at
more than `crease` degrees.

  python holo_edges.py model.obj [--crease 32] [--out edges.json]
  python holo_edges.py --self-test

Needs numpy. The OBJ reader takes v/f lines only (enough for a check; engines feed their own arrays).
"""
import argparse
import json
from pathlib import Path

import numpy as np

CREASE = 32.0
WELD = .01


def feature_edges(vertices, triangles, crease=CREASE, weld=WELD):
    """vertices (n, 3) float, triangles (m, 3) int -> segment endpoints (k, 2, 3)."""
    vertices = np.asarray(vertices, np.float64)
    triangles = np.asarray(triangles, np.int64)
    cells = np.round(vertices / weld).astype(np.int64)
    _, first, ids = np.unique(cells, axis=0, return_index=True, return_inverse=True)
    points = vertices[first]
    tri = ids.reshape(-1)[triangles]
    tri = tri[(tri[:, 0] != tri[:, 1]) & (tri[:, 1] != tri[:, 2]) & (tri[:, 0] != tri[:, 2])]
    normal = np.cross(points[tri[:, 1]] - points[tri[:, 0]], points[tri[:, 2]] - points[tri[:, 0]])
    length = np.linalg.norm(normal, axis=1)
    keep = length > 1e-12
    tri, normal = tri[keep], normal[keep] / length[keep, None]
    edges = np.concatenate([tri[:, [0, 1]], tri[:, [1, 2]], tri[:, [2, 0]]])
    face = np.tile(np.arange(len(tri)), 3)
    edges.sort(axis=1)
    order = np.lexsort((edges[:, 1], edges[:, 0]))
    edges, face = edges[order], face[order]
    starts = np.flatnonzero(np.r_[True, np.any(edges[1:] != edges[:-1], axis=1)])
    counts = np.diff(np.r_[starts, len(edges)])
    limit = np.cos(np.radians(crease))
    kept = []
    for start, count in zip(starts, counts):
        if count == 1:
            kept.append(edges[start])
            continue
        # Compared with the first face that used it, as the Godot tracer does.
        if np.any(normal[face[start + 1:start + count]] @ normal[face[start]] < limit):
            kept.append(edges[start])
    kept = np.array(kept, np.int64).reshape(-1, 2)
    return points[kept]


def read_obj(path):
    vertices, faces = [], []
    for line in Path(path).read_text(encoding='utf8', errors='ignore').splitlines():
        part = line.split()
        if not part:
            continue
        if part[0] == 'v':
            vertices.append([float(x) for x in part[1:4]])
        elif part[0] == 'f':
            index = [int(p.split('/')[0]) - 1 for p in part[1:]]
            faces.extend([index[0], index[i], index[i + 1]] for i in range(1, len(index) - 1))
    return np.array(vertices), np.array(faces)


def self_test():
    # A unit cube as 12 triangles: its 12 edges are creases (90 degrees), the 6 face diagonals are flat.
    v = np.array([[x, y, z] for x in (0, 1) for y in (0, 1) for z in (0, 1)], float)
    quads = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    tris = [t for a, b, c, d in quads for t in ((a, b, c), (a, c, d))]
    edges = feature_edges(v, tris)
    assert len(edges) == 12, len(edges)
    print('self-test ok: cube -> 12 feature edges')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('obj', nargs='?')
    parser.add_argument('--crease', type=float, default=CREASE)
    parser.add_argument('--out')
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    if args.self_test or not args.obj:
        self_test()
        return
    vertices, faces = read_obj(args.obj)
    edges = feature_edges(vertices, faces, args.crease)
    print(f'{len(faces)} triangles -> {len(edges)} feature edges')
    if args.out:
        Path(args.out).write_text(json.dumps(edges.round(4).tolist()), encoding='utf8')


if __name__ == '__main__':
    main()
