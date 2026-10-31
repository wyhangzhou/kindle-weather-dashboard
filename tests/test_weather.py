from copy import deepcopy
from datetime import datetime, timedelta, timezone
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from PIL import Image

from generate import BASE, MARKER, SCHEMA, Config, WeatherError, generate_site, normalize, probability


class WeatherPipelineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture = json.loads((BASE / "tests/fixtures/redmond.json").read_text())
        cls.config = Config(city="Redmond", region="华盛顿州 · 美国", latitude=47.67399,
                            longitude=-122.12151, timezone="America/Los_Angeles")
        cls.now = datetime.fromtimestamp(cls.fixture["current"]["time"], timezone.utc) + timedelta(minutes=5)

    def test_forecast_calendar_survives_fall_dst_transition(self):
        weather = normalize(self.fixture, self.config, self.now)
        self.assertEqual([day.date.isoformat() for day in weather.days],
                         ["2026-10-31", "2026-11-01", "2026-11-02", "2026-11-03", "2026-11-04"])

    def test_stale_or_future_current_weather_is_rejected(self):
        for delta in (timedelta(hours=3), timedelta(hours=-1)):
            with self.subTest(delta=delta), self.assertRaises(WeatherError):
                normalize(self.fixture, self.config, self.now + delta)

    def test_invalid_weather_preserves_previous_image(self):
        payload = deepcopy(self.fixture)
        payload["current"]["temperature_2m"] = None
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "site"
            output.mkdir()
            (output / MARKER).write_text(SCHEMA)
            previous = output / "dashboard.png"
            previous.write_bytes(b"previous-good-image")
            with self.assertRaises(WeatherError):
                generate_site(payload, self.config, output, self.now)
            self.assertEqual(previous.read_bytes(), b"previous-good-image")

    def test_unexpected_units_are_rejected(self):
        payload = deepcopy(self.fixture)
        payload["current_units"]["temperature_2m"] = "°F"
        with self.assertRaises(WeatherError):
            normalize(payload, self.config, self.now)

    def test_missing_rain_probability_is_not_zero(self):
        payload = deepcopy(self.fixture)
        payload["daily"]["precipitation_probability_max"][0] = None
        weather = normalize(payload, self.config, self.now)
        self.assertIsNone(weather.days[0].rain)
        self.assertEqual(probability(weather.days[0].rain), "—")

    def test_output_contract_for_cloud_and_native_framebuffer(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "site"
            manifest = generate_site(self.fixture, self.config, output, self.now)
            for name, dimensions in (("dashboard.png", (800, 600)), ("dashboard-kindle.png", (600, 800))):
                data = (output / name).read_bytes()
                self.assertEqual(hashlib.sha256(data).hexdigest(), manifest["images"][name]["sha256"])
                with Image.open(output / name) as image:
                    image.load()
                    self.assertEqual(image.size, dimensions)
                    self.assertEqual(image.mode, "L")
                    self.assertLessEqual(len(image.getcolors(256)), 16)
                    self.assertGreater(len(image.getcolors(256)), 1)
            # A subsequent successful run can replace an owned output directory.
            generate_site(self.fixture, self.config, output, self.now + timedelta(minutes=1))
            self.assertTrue((output / "index.html").is_file())

    def test_unrelated_output_directory_is_preserved(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "notes"
            output.mkdir()
            note = output / "important.txt"
            note.write_text("keep")
            with self.assertRaises(WeatherError):
                generate_site(self.fixture, self.config, output, self.now)
            self.assertEqual(note.read_text(), "keep")


if __name__ == "__main__":
    unittest.main()
