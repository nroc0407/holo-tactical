"""Render Holo Tactical line dumps (SPEC.md "Line dump") to PNGs, the way the hologram looks on screen:
unshaded lines added on top of each other, a soft glow, a dark background and a vignette.

  python holo_render.py <dump dir> [<png dir>] [--width 1920 --height 1080] [shot ...]

Engine-neutral: any engine that writes the dump format (holo_capture.gd for Godot) can use it.
Needs numpy and opencv-python.
"""
import argparse
import json
from pathlib import Path

import cv2
import numpy as np

HERE = Path(__file__).resolve().parent
PALETTE = HERE.parents[1] / 'godot/addons/holo_tactical/data/palette.json'
# Brightness of one pixel of line at full alpha, and the glow's (sigma in pixels at 1080 lines, mix).
LINE_GAIN = 1.15
GLOW = [(2.0, .55), (9.0, .35), (28.0, .25)]


def load(folder, name):
    header = json.loads((folder / f'{name}.json').read_text(encoding='utf8'))
    raw = np.fromfile(folder / f'{name}.bin', dtype=np.float32)
    n = int(header['vertices'])
    return header, raw[:n * 3].reshape(n, 3), raw[n * 3:n * 3 + n * 4].reshape(n, 4)


def to_camera(header, verts):
    """Points into the camera's frame (camera looks down -Z, +Y up); basis rows are its X, Y, Z axes."""
    basis = np.array(header['basis'], np.float32).reshape(3, 3)
    return (verts - np.array(header['origin'], np.float32)) @ basis.T


def clip(a, b, ca, cb, near):
    za, zb = -a[:, 2], -b[:, 2]
    keep = (za > near) | (zb > near)
    a, b, ca, cb, za, zb = a[keep], b[keep], ca[keep], cb[keep], za[keep], zb[keep]
    cut = za <= near
    t = np.where(cut, (near - za) / np.maximum(zb - za, 1e-9), 0.0)[:, None]
    a = np.where(cut[:, None], a + (b - a) * t, a)
    cut = zb <= near
    t = np.where(cut, (near - zb) / np.maximum(za - zb, 1e-9), 0.0)[:, None]
    b = np.where(cut[:, None], b + (a - b) * t, b)
    return a, b, ca, cb


def project(points, fov, width, height):
    """Vertical field of view in degrees, as most engines keep the height."""
    f = 1.0 / np.tan(np.radians(fov) * .5)
    depth = np.maximum(-points[:, 2], 1e-6)
    x = (points[:, 0] * f / (width / height) / depth * .5 + .5) * width
    y = (.5 - points[:, 1] * f / depth * .5) * height
    return np.stack([x, y], 1)


def splat(image, sa, sb, ca, cb, step=.6, chunk=40000):
    """Adds every segment into `image` as samples `step` px apart, each spread bilinearly."""
    height, width = image.shape[:2]
    for start in range(0, len(sa), chunk):
        a, b = sa[start:start + chunk], sb[start:start + chunk]
        c0, c1 = ca[start:start + chunk], cb[start:start + chunk]
        length = np.linalg.norm(b - a, axis=1)
        inside = ~((np.maximum(a[:, 0], b[:, 0]) < -2) | (np.minimum(a[:, 0], b[:, 0]) > width + 2) |
                   (np.maximum(a[:, 1], b[:, 1]) < -2) | (np.minimum(a[:, 1], b[:, 1]) > height + 2))
        a, b, c0, c1, length = a[inside], b[inside], c0[inside], c1[inside], length[inside]
        if len(a) == 0:
            continue
        count = np.clip(np.ceil(length / step).astype(np.int64) + 1, 2, 6000)
        owner = np.repeat(np.arange(len(a)), count)
        offsets = np.arange(count.sum()) - np.repeat(np.cumsum(count) - count, count)
        t = (offsets / np.maximum(np.repeat(count, count) - 1, 1)).astype(np.float32)[:, None]
        points = a[owner] + (b[owner] - a[owner]) * t
        colour = c0[owner] + (c1[owner] - c0[owner]) * t
        rgb = colour[:, :3] * (colour[:, 3:4] * np.repeat(length / count, count)[:, None]).astype(np.float32)
        x0 = np.floor(points[:, 0]).astype(np.int64)
        y0 = np.floor(points[:, 1]).astype(np.int64)
        fx = (points[:, 0] - x0)[:, None]
        fy = (points[:, 1] - y0)[:, None]
        for dx, dy, w in ((0, 0, (1 - fx) * (1 - fy)), (1, 0, fx * (1 - fy)), (0, 1, (1 - fx) * fy), (1, 1, fx * fy)):
            x, y = x0 + dx, y0 + dy
            ok = (x >= 0) & (x < width) & (y >= 0) & (y < height)
            np.add.at(image, (y[ok], x[ok]), (rgb[ok] * w[ok]).astype(np.float32))


def render(folder, out, name, width, height):
    background = np.array(json.loads(PALETTE.read_text(encoding='utf8'))['background'][:3], np.float32)
    header, verts, colours = load(folder, name)
    local = to_camera(header, verts)
    a, b, ca, cb = clip(local[0::2], local[1::2], colours[0::2], colours[1::2], max(float(header['near']), 1e-3))
    sa, sb = project(a, header['fov'], width, height), project(b, header['fov'], width, height)
    lines = np.zeros((height, width, 3), np.float32)
    splat(lines, sa, sb, ca, cb)
    lines *= LINE_GAIN
    glow = np.zeros_like(lines)
    for sigma, mix in GLOW:
        glow += cv2.GaussianBlur(lines, (0, 0), sigma * height / 1080.0) * mix
    image = background + (1.0 - np.exp(-(lines + glow) * 1.25))
    yy, xx = np.mgrid[0:height, 0:width]
    r = np.hypot((xx - width / 2) / (width / 2), (yy - height / 2) / (height / 2))
    image *= (1.0 - .35 * np.clip(r - .45, 0, 1))[:, :, None]
    # Dither before 8 bits, or the dark gradients band into rings.
    image += (np.random.default_rng(7).random(image.shape, np.float32) - .5) / 255.0
    out.mkdir(parents=True, exist_ok=True)
    path = out / f'{name}.png'
    cv2.imwrite(str(path), (np.clip(image, 0, 1)[:, :, ::-1] * 255 + .5).astype(np.uint8))
    print(f'{path}  {len(sa)} segments')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('dumps')
    parser.add_argument('pngs', nargs='?')
    parser.add_argument('shots', nargs='*')
    parser.add_argument('--width', type=int, default=1920)
    parser.add_argument('--height', type=int, default=1080)
    args = parser.parse_args()
    folder = Path(args.dumps)
    out = Path(args.pngs) if args.pngs else folder
    for name in args.shots or sorted(p.stem for p in folder.glob('*.json')):
        render(folder, out, name, args.width, args.height)


if __name__ == '__main__':
    main()
