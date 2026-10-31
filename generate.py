"""Fetch Open-Meteo weather and publish complete, validated e-ink image sets."""

import argparse
from dataclasses import asdict, dataclass
from datetime import date, datetime, timedelta, timezone
from functools import lru_cache
import hashlib
import html
import io
import json
import math
import os
from pathlib import Path
import shutil
import sys
import tempfile
import time
import tomllib
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen
import uuid
from zoneinfo import ZoneInfo

from PIL import Image, ImageDraw, ImageFont

from weather_icons import icon, weather_text

BASE = Path(__file__).resolve().parent
UTC = timezone.utc
MARKER = ".kindle-weather-output"
SCHEMA = "kindle-weather-v1"


class WeatherError(ValueError):
    pass


@dataclass(frozen=True)
class Config:
    city: str
    region: str
    latitude: float
    longitude: float
    timezone: str
    temperature_unit: str = "celsius"
    forecast_days: int = 5
    max_weather_age_minutes: int = 90
    kindle_rotation: str = "counterclockwise"

    @classmethod
    def load(cls, path):
        with Path(path).open("rb") as stream:
            config = cls(**tomllib.load(stream))
        ZoneInfo(config.timezone)
        if not (-90 <= config.latitude <= 90 and -180 <= config.longitude <= 180):
            raise WeatherError("Invalid coordinates")
        if config.temperature_unit not in ("celsius", "fahrenheit"):
            raise WeatherError("temperature_unit must be celsius or fahrenheit")
        if not 3 <= config.forecast_days <= 5:
            raise WeatherError("forecast_days must be between 3 and 5")
        if not 15 <= config.max_weather_age_minutes <= 180:
            raise WeatherError("max_weather_age_minutes must be between 15 and 180")
        if config.kindle_rotation not in ("clockwise", "counterclockwise"):
            raise WeatherError("Invalid kindle_rotation")
        return config


@dataclass(frozen=True)
class Day:
    date: date
    code: int
    high: float
    low: float
    rain: float | None


@dataclass(frozen=True)
class Weather:
    generated_at: datetime
    weather_at: datetime
    temperature: float
    apparent: float
    humidity: float
    wind: float
    code: int
    is_day: bool
    days: tuple[Day, ...]


def number(value, name, low, high):
    if isinstance(value, bool) or not isinstance(value, (float, int)):
        raise WeatherError(f"Missing or invalid {name}")
    if not math.isfinite(value) or not low <= value <= high:
        raise WeatherError(f"Out-of-range {name}")
    return value


def fetch_weather(config):
    params = {
        "latitude": config.latitude, "longitude": config.longitude,
        "current": "temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m",
        "daily": "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max",
        "temperature_unit": "celsius", "wind_speed_unit": "kmh",
        "timezone": config.timezone, "timeformat": "unixtime", "forecast_days": config.forecast_days,
    }
    request = Request("https://api.open-meteo.com/v1/forecast?" + urlencode(params),
                      headers={"User-Agent": "KindleWeather/1.0 (personal weather display)"})
    last_error = None
    for attempt in range(3):
        try:
            with urlopen(request, timeout=12) as response:
                data = response.read(262145)
            if len(data) > 262144:
                raise WeatherError("Weather response exceeds expected size")
            return json.loads(data)
        except HTTPError as exc:
            if exc.code < 500 and exc.code != 429:
                raise WeatherError(f"Weather API returned HTTP {exc.code}") from exc
            last_error = exc
        except (URLError, TimeoutError, json.JSONDecodeError) as exc:
            last_error = exc
        if attempt < 2:
            time.sleep(2 ** (attempt + 1))
    raise WeatherError(f"Weather API unavailable after three attempts: {last_error}")


def normalize(payload, config, now=None):
    now = now or datetime.now(UTC)
    if now.tzinfo is None:
        raise WeatherError("Reference time must include a timezone")
    try:
        if payload.get("error") or payload["timezone"] != config.timezone:
            raise WeatherError("Weather response has an error or unexpected timezone")
        current, daily = payload["current"], payload["daily"]
        if payload["current_units"]["temperature_2m"] != "°C" or payload["current_units"]["wind_speed_10m"] != "km/h":
            raise WeatherError("Unexpected current-weather units")
        for key in ("temperature_2m_max", "temperature_2m_min"):
            if payload["daily_units"][key] != "°C":
                raise WeatherError("Unexpected daily-temperature units")
        if payload["daily_units"]["precipitation_probability_max"] != "%":
            raise WeatherError("Unexpected precipitation-probability units")
        weather_at = datetime.fromtimestamp(number(current["time"], "weather time", 0, 4102444800), UTC)
        age = (now - weather_at).total_seconds()
        if age > config.max_weather_age_minutes * 60 or age < -600:
            raise WeatherError("Weather data is stale or its timestamp is in the future")
        offset = number(payload["utc_offset_seconds"], "API UTC offset", -86400, 86400)
        today = now.astimezone(ZoneInfo(config.timezone)).date()
        keys = ("time", "weather_code", "temperature_2m_max", "temperature_2m_min", "precipitation_probability_max")
        if any(len(daily[key]) != config.forecast_days for key in keys):
            raise WeatherError("Incomplete daily forecast")
        days = []
        for i in range(config.forecast_days):
            # Open-Meteo daily Unix dates use its reported offset, including across DST boundaries.
            stamp = number(daily["time"][i], "daily time", 0, 4102444800)
            day = datetime.fromtimestamp(stamp + offset, UTC).date()
            if day != today + timedelta(days=i):
                raise WeatherError("Forecast calendar dates do not match the requested local days")
            high = number(daily["temperature_2m_max"][i], "daily high", -100, 70)
            low = number(daily["temperature_2m_min"][i], "daily low", -100, 70)
            if low > high:
                raise WeatherError("Daily low exceeds high")
            rain = daily["precipitation_probability_max"][i]
            if rain is not None:
                rain = number(rain, "rain probability", 0, 100)
            days.append(Day(day, int(number(daily["weather_code"][i], "weather code", 0, 999)), high, low, rain))
        return Weather(
            now.astimezone(UTC), weather_at,
            number(current["temperature_2m"], "temperature", -100, 70),
            number(current["apparent_temperature"], "apparent temperature", -150, 100),
            number(current["relative_humidity_2m"], "humidity", 0, 100),
            number(current["wind_speed_10m"], "wind speed", 0, 500),
            int(number(current["weather_code"], "weather code", 0, 999)),
            bool(number(current["is_day"], "is_day", 0, 1)), tuple(days),
        )
    except (KeyError, TypeError, OverflowError, OSError) as exc:
        raise WeatherError(f"Malformed weather response: {exc}") from exc


@lru_cache(maxsize=32)
def font(size, weight=500):
    result = ImageFont.truetype(str(BASE / "assets/fonts/NotoSansSC-VF.ttf"), size * 2)
    result.set_variation_by_axes([weight])
    return result


def degrees(value, config):
    return round(value if config.temperature_unit == "celsius" else value * 9 / 5 + 32)


def probability(value):
    return "—" if value is None else f"{round(value)}%"


def render(weather, config):
    canvas = Image.new("L", (1600, 1200), 255)
    draw = ImageDraw.Draw(canvas)

    def text(x, y, value, size=24, weight=500, anchor="lt", fill=0):
        draw.text((round(x*2), round(y*2)), str(value), font=font(size, weight), fill=fill, anchor=anchor)

    def rule(y, x1=28, x2=772, fill=0, width=1):
        draw.line((x1*2, y*2, x2*2, y*2), fill=fill, width=width*2)

    tz = ZoneInfo(config.timezone)
    local = weather.generated_at.astimezone(tz)
    weekday = "一二三四五六日"[local.weekday()]
    text(28, 21, config.city, 35, 700)
    text(772, 25, f"{local.month}月{local.day}日  周{weekday}", 28, 600, "rt")
    text(29, 65, config.region, 18, fill=50)
    text(772, 65, f"{local.year}年", 18, anchor="rt", fill=50)
    rule(99, width=2)

    temperature = str(degrees(weather.temperature, config))
    text(25, 128, temperature, 145, 650)
    width = draw.textlength(temperature, font=font(145, 650)) / 2
    unit = "°C" if config.temperature_unit == "celsius" else "°F"
    text(34+width, 154, unit, 49, 500)
    text(30, 298, f"体感 {degrees(weather.apparent, config)}{unit}", 26)
    canvas.paste(icon(weather.code, weather.is_day, 310), (1040, 222))
    description = weather_text(weather.code)
    size = 30 if len(description) <= 6 else 26
    text(600, 298, description, size, 600, "mt")

    text(29, 344, f"今日降雨 {probability(weather.days[0].rain)}", 23)
    text(330, 344, f"湿度 {round(weather.humidity)}%", 23)
    text(772, 344, f"风速 {round(weather.wind)} km/h", 23, anchor="rt")
    rule(385, width=2)

    column_width = 744 / len(weather.days)
    for i, day in enumerate(weather.days):
        center = 28 + column_width * (i + .5)
        label = "今天" if i == 0 else "明天" if i == 1 else "周" + "一二三四五六日"[day.date.weekday()]
        text(center, 402, label, 22, 600, "mt")
        canvas.paste(icon(day.code, True, 104), (round(center*2-52), 858))
        text(center, 494, f"{degrees(day.high, config)}° / {degrees(day.low, config)}°", 25, 600, "mt")
        text(center, 534, f"降雨 {probability(day.rain)}", 20, anchor="mt", fill=35)
    rule(570, fill=140)
    weather_local = weather.weather_at.astimezone(tz)
    text(29, 581, f"天气 {weather_local:%m/%d %H:%M}  ·  更新 {local:%H:%M}", 16, fill=45)
    text(772, 581, "Open-Meteo", 16, anchor="rt", fill=45)
    canvas = canvas.resize((800, 600), Image.Resampling.LANCZOS)
    return canvas.point([round(value / 17) * 17 for value in range(256)])


def png_bytes(image):
    data = io.BytesIO()
    image.save(data, "PNG", optimize=True, compress_level=9)
    raw = data.getvalue()
    with Image.open(io.BytesIO(raw)) as check:
        check.verify()
    return raw


def generate_site(payload, config, output, now=None):
    output = Path(output).absolute()
    if output.is_symlink() or (output.exists() and not (output / MARKER).is_file()):
        raise WeatherError("Refusing to replace an existing directory without the generated-output marker")
    weather = normalize(payload, config, now)
    image = render(weather, config)
    rotate = Image.Transpose.ROTATE_90 if config.kindle_rotation == "counterclockwise" else Image.Transpose.ROTATE_270
    images = {"dashboard.png": image, "dashboard-kindle.png": image.transpose(rotate)}
    output.parent.mkdir(parents=True, exist_ok=True)
    manifest = {
        "schema": SCHEMA, "city": config.city, "timezone": config.timezone,
        "generated_at": weather.generated_at.isoformat(), "weather_at": weather.weather_at.isoformat(),
        "temperature_unit": config.temperature_unit, "kindle_rotation": config.kindle_rotation,
        "images": {},
    }
    with tempfile.TemporaryDirectory(prefix=".weather-build-", dir=output.parent) as temporary:
        stage = Path(temporary)
        for name, picture in images.items():
            data = png_bytes(picture)
            (stage / name).write_bytes(data)
            manifest["images"][name] = {"sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data),
                                        "width": picture.width, "height": picture.height, "mode": picture.mode}
        (stage / MARKER).write_text(SCHEMA + "\n")
        (stage / ".nojekyll").touch()
        (stage / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
        (stage / "weather.json").write_text(json.dumps(asdict(weather), ensure_ascii=False, default=lambda value: value.isoformat(), indent=2) + "\n")
        updated = weather.generated_at.astimezone(ZoneInfo(config.timezone)).strftime("%Y-%m-%d %H:%M %Z")
        (stage / "index.html").write_text(f'''<!doctype html>
<html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="1800"><title>{html.escape(config.city)} 天气</title>
<style>body{{max-width:800px;margin:24px auto;padding:0 12px;font:16px system-ui;color:#222;background:#fff}}img{{width:100%;height:auto}}footer{{line-height:1.8;color:#555}}a{{color:inherit}}</style>
<main><img src="dashboard.png?v={int(weather.generated_at.timestamp())}" width="800" height="600" alt="{html.escape(config.city)} 当前天气与未来五天预报"></main>
<footer>更新于 {updated}。数据：<a href="https://open-meteo.com/">Open-Meteo</a>（<a href="https://creativecommons.org/licenses/by/4.0/">CC BY 4.0</a>）。</footer></html>\n''')
        backup = output.with_name(".weather-old-" + uuid.uuid4().hex)
        if output.exists():
            output.rename(backup)
        try:
            stage.rename(output)
        except BaseException:
            if backup.exists():
                backup.rename(output)
            raise
        if backup.exists():
            shutil.rmtree(backup)
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=BASE / "config.toml")
    parser.add_argument("--output", type=Path, default=BASE / "public")
    args = parser.parse_args()
    try:
        config = Config.load(args.config)
        result = generate_site(fetch_weather(config), config, args.output)
    except (WeatherError, OSError, ValueError) as exc:
        print(f"Weather image not published: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
