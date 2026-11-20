import io
import json
from datetime import datetime, timezone
import unittest
from unittest.mock import call, patch
from urllib.error import HTTPError, URLError

from generate import Config, WeatherError, fetch_weather


class WeatherFetchTests(unittest.TestCase):
    def setUp(self):
        self.config = Config(city="Redmond", region="Washington", latitude=47.67399,
                             longitude=-122.12151, timezone="America/Los_Angeles")
        self.payload = {"current": {"temperature_2m": 8}}

    def response(self):
        return io.BytesIO(json.dumps(self.payload).encode())

    def test_recovers_after_the_previously_exhausted_three_handshakes(self):
        failures = [URLError(TimeoutError("TLS handshake timed out")) for _ in range(3)]
        with patch("generate.urlopen", side_effect=failures + [self.response()]) as request, \
                patch("generate.time.sleep") as sleep:
            self.assertEqual(fetch_weather(self.config), self.payload)
        self.assertEqual(request.call_count, 4)
        self.assertTrue(all(item.kwargs["timeout"] == 20 for item in request.call_args_list))
        self.assertEqual(sleep.call_args_list, [call(2), call(4), call(8)])

    def test_temporary_network_and_server_errors_can_recover(self):
        for failure in [TimeoutError("read timeout"), URLError("temporary network failure"),
                        HTTPError("https://api.open-meteo.com/", 429, "busy", {"Retry-After": "2"}, None),
                        HTTPError("https://api.open-meteo.com/", 503, "unavailable", {}, None)]:
            if isinstance(failure, HTTPError):
                self.addCleanup(failure.close)
            with self.subTest(error=type(failure).__name__, code=getattr(failure, "code", None)), \
                    patch("generate.urlopen", side_effect=[failure, self.response()]) as request, \
                    patch("generate.time.sleep") as sleep:
                self.assertEqual(fetch_weather(self.config), self.payload)
                self.assertEqual(request.call_count, 2)
                sleep.assert_called_once_with(2)

    def test_permanent_http_error_fails_without_retries(self):
        error = HTTPError("https://api.open-meteo.com/", 403, "forbidden", {}, None)
        self.addCleanup(error.close)
        with patch("generate.urlopen", side_effect=error) as request, \
                patch("generate.time.sleep") as sleep:
            with self.assertRaisesRegex(WeatherError, "HTTP 403"):
                fetch_weather(self.config)
        self.assertEqual(request.call_count, 1)
        sleep.assert_not_called()

    def test_persistent_failure_still_fails_after_a_bounded_number_of_attempts(self):
        with patch("generate.urlopen", side_effect=URLError("network unavailable")) as request, \
                patch("generate.time.sleep") as sleep:
            with self.assertRaisesRegex(WeatherError, "after 4 attempts.*network unavailable"):
                fetch_weather(self.config)
        self.assertEqual(request.call_count, 4)
        self.assertEqual(sleep.call_args_list, [call(2), call(4), call(8)])

    def test_rate_limit_waits_at_least_retry_after(self):
        error = HTTPError("https://api.open-meteo.com/", 429, "busy", {"Retry-After": "30"}, None)
        self.addCleanup(error.close)
        with patch("generate.urlopen", side_effect=[error, self.response()]), patch("generate.time.sleep") as sleep:
            self.assertEqual(fetch_weather(self.config), self.payload)
        sleep.assert_called_once_with(30)

    def test_long_rate_limit_defers_to_next_scheduled_run(self):
        error = HTTPError("https://api.open-meteo.com/", 429, "busy", {"Retry-After": "900"}, None)
        self.addCleanup(error.close)
        with patch("generate.urlopen", side_effect=error) as request, patch("generate.time.sleep") as sleep:
            with self.assertRaisesRegex(WeatherError, "next scheduled update"):
                fetch_weather(self.config)
        self.assertEqual(request.call_count, 1)
        sleep.assert_not_called()

    def test_http_date_retry_after_is_respected(self):
        error = HTTPError("https://api.open-meteo.com/", 429, "busy",
                          {"Retry-After": "Fri, 20 Nov 2026 22:00:30 GMT"}, None)
        self.addCleanup(error.close)
        with patch("generate.datetime") as clock, patch("generate.urlopen", side_effect=[error, self.response()]), \
                patch("generate.time.sleep") as sleep:
            clock.now.return_value = datetime(2026, 11, 20, 22, 0, tzinfo=timezone.utc)
            self.assertEqual(fetch_weather(self.config), self.payload)
        sleep.assert_called_once_with(30)


if __name__ == "__main__":
    unittest.main()
