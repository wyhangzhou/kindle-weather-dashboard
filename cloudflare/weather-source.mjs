// The renderer rejects inputs if these differ from config.toml.
export const weatherConfig = Object.freeze({
  latitude: 47.67399, longitude: -122.12151,
  timezone: "America/Los_Angeles", forecast_days: 5,
});

export async function fetchWeatherInput(fetcher = fetch) {
  const url = new URL("https://api.open-meteo.com/v1/forecast");
  const params = {
    ...weatherConfig,
    current: "temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m",
    daily: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max",
    temperature_unit: "celsius", wind_speed_unit: "kmh", timeformat: "unixtime",
  };
  for (const [key, value] of Object.entries(params)) url.searchParams.set(key, String(value));
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 20000);
  try {
    const response = await fetcher(url.toString(), {
      redirect: "manual", signal: controller.signal,
      headers: { "User-Agent": "KindleWeather/1.0 (personal weather display)" },
    });
    if (!response.ok) {
      if (response.body) await response.body.cancel();
      throw new Error(`Weather API HTTP ${response.status}`);
    }
    const reader = response.body.getReader();
    const chunks = []; let size = 0;
    try {
      while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        size += value.byteLength;
        if (size > 30000) throw new Error("Weather response exceeds expected size");
        chunks.push(value);
      }
    } finally { await reader.cancel(); }
    const bytes = new Uint8Array(size); let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
    const payload = JSON.parse(new TextDecoder().decode(bytes));
    if (!payload || typeof payload !== "object" || Array.isArray(payload) || payload.error) {
      throw new Error("Invalid weather response");
    }
    const input = JSON.stringify({ schema: "kindle-weather-source-v1", config: weatherConfig, payload });
    if (new TextEncoder().encode(input).byteLength > 32768) throw new Error("Weather input too large");
    return input;
  } finally { clearTimeout(timer); }
}
