"""Original monochrome weather icons, drawn as shapes for the e-ink display."""

import math
from functools import lru_cache

from PIL import Image, ImageChops, ImageDraw, ImageFilter


def weather_kind(code):
    if code == 0:
        return "clear"
    if code in (1, 2):
        return "partly"
    if code in (45, 48):
        return "fog"
    if code in (71, 73, 75, 77, 85, 86):
        return "snow"
    if code in (95, 96, 97, 99):
        return "thunder"
    if code in (51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82):
        return "rain"
    return "cloudy"


def weather_text(code):
    groups = {
        0: "晴", 1: "晴间多云", 2: "多云", 3: "阴",
        45: "雾", 48: "雾凇", 51: "小毛毛雨", 53: "毛毛雨", 55: "大毛毛雨",
        56: "冻毛毛雨", 57: "冻毛毛雨", 61: "小雨", 63: "中雨", 65: "大雨",
        66: "冻雨", 67: "冻雨", 71: "小雪", 73: "中雪", 75: "大雪", 77: "雪粒",
        80: "阵雨", 81: "阵雨", 82: "强阵雨", 85: "阵雪", 86: "强阵雪",
        95: "雷雨", 96: "雷雨伴冰雹", 97: "强雷雨", 99: "雷雨伴冰雹",
    }
    return groups.get(code, "天气未知")


@lru_cache(maxsize=64)
def icon(code, is_day=True, size=160):
    n = 512
    image = Image.new("L", (n, n), 255)
    draw = ImageDraw.Draw(image)
    kind = weather_kind(code)

    def box(values):
        return tuple(round(v * n) for v in values)

    def line(points, width=14):
        draw.line([box(p) for p in points], fill=0, width=width)

    if kind in ("clear", "partly"):
        cx, cy, radius = (0.5, 0.45, 0.21) if kind == "clear" else (0.34, 0.31, 0.15)
        if is_day:
            draw.ellipse(box((cx-radius, cy-radius, cx+radius, cy+radius)), outline=0, width=14)
            for a in range(0, 360, 45):
                angle = math.radians(a)
                line([(cx + (radius+.06)*math.cos(angle), cy + (radius+.06)*math.sin(angle)),
                      (cx + (radius+.13)*math.cos(angle), cy + (radius+.13)*math.sin(angle))])
        else:
            draw.ellipse(box((cx-radius, cy-radius, cx+radius, cy+radius)), fill=0)
            draw.ellipse(box((cx-radius+.11, cy-radius-.06, cx+radius+.08, cy+radius-.07)), fill=255)
            line([(0.78, 0.28), (0.78, 0.39)], width=10)
            line([(0.73, 0.335), (0.83, 0.335)], width=10)

    if kind != "clear":
        cloud = Image.new("L", image.size)
        cd = ImageDraw.Draw(cloud)
        for shape in [(0.12, .42, .48, .75), (.30, .25, .71, .75), (.55, .42, .90, .75)]:
            cd.ellipse(box(shape), fill=255)
        cd.rectangle(box((.29, .56, .74, .75)), fill=255)
        eroded = cloud
        for _ in range(13):
            eroded = eroded.filter(ImageFilter.MinFilter(3))
        edge = ImageChops.subtract(cloud, eroded)
        image.paste(255, mask=cloud)
        image.paste(0, mask=edge)
        draw = ImageDraw.Draw(image)
    if kind == "rain":
        for x in (.32, .52, .72):
            line([(x, .82), (x-.06, .98)])
    elif kind == "snow":
        for x in (.32, .68):
            for angle in (0, 60, 120):
                dx, dy = .075*math.cos(math.radians(angle)), .075*math.sin(math.radians(angle))
                line([(x-dx, .88-dy), (x+dx, .88+dy)], width=10)
    elif kind == "thunder":
        draw.polygon([box(p) for p in ((.53,.68),(.37,.88),(.50,.85),(.43,.99),(.70,.76),(.56,.79))], fill=0)
    elif kind == "fog":
        line([(.15, .85), (.85, .85)], width=12)
        line([(.24, .96), (.76, .96)], width=12)
    return image.resize((size, size), Image.Resampling.LANCZOS)
