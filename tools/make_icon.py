#!/usr/bin/env python3
"""Generate the USB Storage Mode app icons (icon.png / iconsel.png).

The USB trident is drawn at 4x and downsampled, which gives clean anti-aliased
edges without any font or SVG dependency.

    python3 tools/make_icon.py
"""

import os

from PIL import Image, ImageDraw

S = 4               # supersampling factor
N = 256             # final icon size
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "USBStorageMode")

USB = (88, 166, 255, 255)
USB_DIM = (56, 116, 178, 255)
WHITE = (240, 246, 255, 255)


def rounded_gradient(size, top, bottom, radius):
    """Vertical gradient inside a rounded square."""
    grad = Image.new("RGBA", (1, size))
    px = grad.load()
    for y in range(size):
        t = y / (size - 1)
        px[0, y] = tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(4))

    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    img.paste(grad.resize((size, size)), (0, 0), mask)
    return img


def stroke(draw, points, width, colour):
    """Line with round joints/caps."""
    draw.line(points, fill=colour, width=width, joint="curve")
    r = width // 2
    for x, y in points:
        draw.ellipse([x - r, y - r, x + r, y + r], fill=colour)


def usb_trident(draw, colour, width):
    """The classic USB mark: circle - stem - square + triangle + circle."""
    stroke(draw, [(128, 58), (128, 96), (128, 140), (128, 168)], width, colour)
    stroke(draw, [(128, 104), (92, 104)], width, colour)
    stroke(draw, [(128, 136), (176, 136)], width, colour)

    # square terminal (left)
    draw.rectangle([58, 88, 90, 120], fill=colour)
    # triangle terminal (bottom)
    draw.polygon([(110, 168), (146, 168), (128, 210)], fill=colour)
    # circle terminals (top and right)
    for cx, cy, r in ((128, 52, 19), (194, 136, 19)):
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=colour)


def build(selected):
    size = N * S
    top = (34, 58, 104, 255) if selected else (20, 28, 44, 255)
    bottom = (12, 17, 26, 255)
    img = rounded_gradient(size, top, bottom, radius=44 * S)

    draw = ImageDraw.Draw(img)
    colour = WHITE if selected else USB

    if selected:
        draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=44 * S,
                               outline=(88, 166, 255, 255), width=5 * S)

    # keep the mark optically centred: it is drawn in 256-space, scaled up here
    mark = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    md = ImageDraw.Draw(mark)
    usb_trident(md, colour, 17)
    img.alpha_composite(mark.resize((size, size), Image.LANCZOS))

    # a small underline that reads as "drive / storage" at 64 px
    draw.rounded_rectangle([86 * S, 224 * S, 170 * S, 234 * S],
                           radius=5 * S,
                           fill=(88, 166, 255, 255) if selected else USB_DIM)

    return img.resize((N, N), Image.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, selected in (("icon.png", False),):
        path = os.path.join(OUT, name)
        build(selected).save(path)
        print("wrote", path)


if __name__ == "__main__":
    main()