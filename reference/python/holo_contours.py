"""Land and shallows for the holograms (SPEC.md "Contours"): the reference for porting
godot/addons/holo_tactical/holo_contours.gd.

- island_rings: rings round a summit at given heights, by bisecting along rays for where the
  ground falls below each level (islands that rise to one top).
- shoal_lines: depth contours on a plan grid by marching squares.

  python holo_contours.py --self-test
"""
import argparse
import math

import numpy as np


def island_rings(height, centre, reach, levels, rays=48, steps=14):
    """height(x, z) -> metres. Returns [{"level": float, "ring": (rays, 2) array}]."""
    rings = []
    for level in levels:
        ring = np.zeros((rays, 2))
        for i in range(rays):
            direction = np.array([math.cos(2 * math.pi * i / rays), math.sin(2 * math.pi * i / rays)])
            inside, outside = 0.0, reach
            for _ in range(steps):
                middle = (inside + outside) * .5
                x, z = np.asarray(centre) + direction * middle
                if height(x, z) >= level:
                    inside = middle
                else:
                    outside = middle
            ring[i] = np.asarray(centre) + direction * inside
        rings.append({"level": level, "ring": ring})
    return rings


def shoal_lines(depth, centre, reach, levels, cells=36):
    """depth(x, z) -> metres of water. Returns segment endpoints (k, 2, 2) in plan coordinates."""
    cell = reach * 2.0 / cells
    corner = np.asarray(centre, float) - reach
    xs = corner[0] + np.arange(cells + 1) * cell
    zs = corner[1] + np.arange(cells + 1) * cell
    grid = np.array([[depth(x, z) for x in xs] for z in zs])
    segments = []
    for level in levels:
        for j in range(cells):
            for i in range(cells):
                v = [grid[j, i], grid[j, i + 1], grid[j + 1, i + 1], grid[j + 1, i]]
                p = [(xs[i], zs[j]), (xs[i + 1], zs[j]), (xs[i + 1], zs[j + 1]), (xs[i], zs[j + 1])]
                crossings = []
                for k in range(4):
                    a, b = v[k], v[(k + 1) % 4]
                    if (a < level) != (b < level):
                        t = (level - a) / (b - a)
                        crossings.append((p[k][0] + (p[(k + 1) % 4][0] - p[k][0]) * t, p[k][1] + (p[(k + 1) % 4][1] - p[k][1]) * t))
                if len(crossings) >= 2:
                    segments.append(crossings[:2])
                if len(crossings) == 4:
                    segments.append(crossings[2:])
    return np.array(segments).reshape(-1, 2, 2)


def self_test():
    # A cone 100 m tall and 1000 m across: its 50 m ring is a circle of radius 250 m.
    cone = lambda x, z: 100.0 - math.hypot(x, z) / 5.0
    ring = island_rings(cone, (0.0, 0.0), 1000.0, [50.0])[0]["ring"]
    radius = np.linalg.norm(ring, axis=1)
    assert np.all(np.abs(radius - 250.0) < 1.0), radius
    # Water 60 m deep shoaling toward the middle: a closed 20 m line round it.
    bowl = lambda x, z: min(60.0, math.hypot(x, z) / 10.0)
    lines = shoal_lines(bowl, (0.0, 0.0), 1000.0, [20.0])
    assert len(lines) > 20 and np.all(np.abs(np.linalg.norm(lines, axis=2) - 200.0) < 30.0)
    print(f'self-test ok: cone ring r=250, shoal {len(lines)} segments')


if __name__ == '__main__':
    argparse.ArgumentParser().parse_args()
    self_test()
