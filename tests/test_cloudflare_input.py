from copy import deepcopy
from datetime import datetime, timezone, timedelta
import json
import unittest
from unittest.mock import patch

from generate import BASE, Config, WeatherError, load_weather_input, normalize


class CloudflareInputTests(unittest.TestCase):
    def setUp(self):
        self.config = Config.load(BASE / "config.toml")
        self.payload = json.loads((BASE / "tests/fixtures/redmond.json").read_text())
        self.envelope = {"schema": "kindle-weather-source-v1", "config": {
            key: getattr(self.config, key) for key in ("latitude", "longitude", "timezone", "forecast_days")
        }, "payload": self.payload}

    def test_cloudflare_input_avoids_direct_weather_api(self):
        with patch("generate.fetch_weather") as direct:
            data = load_weather_input(self.config, json.dumps(self.envelope))
        self.assertEqual(data, self.payload)
        direct.assert_not_called()

    def test_missing_input_uses_direct_fallback(self):
        with patch("generate.fetch_weather", return_value=self.payload) as direct:
            self.assertEqual(load_weather_input(self.config, ""), self.payload)
        direct.assert_called_once_with(self.config)

    def test_other_location_or_oversized_input_is_rejected(self):
        wrong = deepcopy(self.envelope); wrong["config"]["longitude"] = 0
        for value in [json.dumps(wrong), "x" * 32769, "[]"]:
            with self.subTest(value=value[:25]), self.assertRaises(WeatherError):
                load_weather_input(self.config, value)

    def test_cloudflare_data_still_has_to_pass_freshness_and_unit_checks(self):
        now = datetime.fromtimestamp(self.payload["current"]["time"], timezone.utc)
        data = load_weather_input(self.config, json.dumps(self.envelope))
        with self.assertRaises(WeatherError):
            normalize(data, self.config, now + timedelta(hours=3))
        data["current_units"]["temperature_2m"] = "°F"
        with self.assertRaises(WeatherError):
            normalize(data, self.config, now)
