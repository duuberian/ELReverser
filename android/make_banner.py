#!/usr/bin/env python3
from PIL import Image, ImageDraw
import random
import math

BG = (10, 10, 10)
RED = (255, 68, 68)

random.seed(42)


def draw_distorted_waveform(draw, cx, cy, wave_width, max_height, px):
    num_bars = wave_width // px
    start_x = cx - wave_width // 2

    for i in range(num_bars):
        t = i / num_bars
        amp = (
            math.sin(t * math.pi * 2 * 3) * 0.4 +
            math.sin(t * math.pi * 2 * 7 + 0.5) * 0.25 +
            math.sin(t * math.pi * 2 * 13 + 1.2) * 0.15 +
            random.uniform(-0.2, 0.2)
        )
        env = math.sin(t * math.pi) ** 0.6
        amp *= env

        bar_h = int(abs(amp) * max_height)
        bar_h = (bar_h // px) * px
        bar_h = max(px, bar_h)

        x = start_x + i * px
        y_top = cy - bar_h
        y_bot = cy + bar_h

        brightness = 0.45 + abs(amp) * 0.55
        r = int(RED[0] * brightness)
        g = int(RED[1] * brightness)
        b = int(RED[2] * brightness)
        draw.rectangle([x, y_top, x + px - 1, y_bot], fill=(r, g, b))

        if random.random() < 0.12:
            goff = random.choice([-3, -2, -1, 1, 2, 3]) * px
            gh = random.randint(1, 3) * px
            gy = cy + random.randint(-int(max_height * 0.5), int(max_height * 0.5))
            draw.rectangle(
                [x + goff, gy, x + goff + px * 2 - 1, gy + gh],
                fill=RED
            )

    random.seed(99)
    for _ in range(6):
        gy = random.randint(cy - int(max_height * 0.8), cy + int(max_height * 0.8))
        gx = random.randint(start_x - 20, start_x + wave_width - 60)
        gw = random.randint(16, 100)
        draw.rectangle(
            [gx, gy, gx + gw, gy + px],
            fill=(int(RED[0] * 0.25), int(RED[1] * 0.25), int(RED[2] * 0.25))
        )


def make_banner():
    W, H = 1280, 640
    PX = 4
    img = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(img)
    draw_distorted_waveform(draw, W // 2, H // 2, 700, 180, PX)
    img.save("banner.png", "PNG")
    print("banner.png saved")


def make_icon():
    W, H = 512, 512
    PX = 4
    img = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(img)
    random.seed(42)
    draw_distorted_waveform(draw, W // 2, H // 2, 380, 140, PX)
    img.save("icon.png", "PNG")
    print("icon.png saved")


if __name__ == "__main__":
    make_banner()
    make_icon()
