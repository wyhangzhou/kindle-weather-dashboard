import assert from "node:assert/strict";
import { test } from "node:test";
import worker, { refreshIfNeeded } from "./worker.mjs";
import { fetchWeatherInput, weatherConfig } from "./weather-source.mjs";

const NOW = 1793512800;
const TOKEN = "test-value-never-a-real-token";
const fresh = () => ({
  schema: "kindle-weather-v1", generated_epoch: NOW - 60,
  weather_epoch: NOW - 300, expires_epoch: NOW - 300 + 5400,
});

function transport(manifest, status = 204) {
  const requests = [];
  const fetcher = async (url, options) => {
    requests.push({ url, options });
    if (requests.length === 1) return new Response(JSON.stringify(manifest));
    if (url.startsWith("https://api.open-meteo.com/")) throw new Error("Simulated unavailable source");
    return new Response(status === 204 ? null : "{}", { status });
  };
  return { requests, fetcher };
}

test("fresh published data skips GitHub and does not send a credential to Pages", async () => {
  const { fetcher, requests } = transport(fresh());
  assert.deepEqual(await refreshIfNeeded({}, fetcher, NOW), { result: "already-fresh" });
  assert.equal(requests.length, 1);
  assert.equal(requests[0].options.headers.Authorization, undefined);
});

test("stale data dispatches only the fixed weather workflow on main", async () => {
  const stale = fresh(); stale.generated_epoch -= 7200; stale.weather_epoch -= 7200; stale.expires_epoch -= 7200;
  const { fetcher, requests } = transport(stale);
  assert.equal((await refreshIfNeeded({ GITHUB_WEATHER_TOKEN: TOKEN }, fetcher, NOW)).result, "dispatch-accepted");
  const { url, options } = requests[2];
  assert.equal(url, "https://api.github.com/repos/wyhangzhou/kindle-weather-dashboard/actions/workflows/weather.yml/dispatches");
  assert.equal(options.method, "POST");
  assert.equal(options.redirect, "manual");
  assert.equal(options.headers.Authorization, `Bearer ${TOKEN}`);
  assert.deepEqual(JSON.parse(options.body), { ref: "main" });
});

test("recent generation cannot hide old weather or a fabricated future timestamp", async () => {
  const variants = [
    { ...fresh(), weather_epoch: NOW - 5300, expires_epoch: NOW + 100 },
    { ...fresh(), generated_epoch: NOW + 3600 },
    { ...fresh(), expires_epoch: NOW + 86400 },
    { ...fresh(), generated_epoch: String(NOW - 60) },
    null,
  ];
  for (const manifest of variants) {
    const { fetcher, requests } = transport(manifest);
    await refreshIfNeeded({ GITHUB_WEATHER_TOKEN: TOKEN }, fetcher, NOW);
    assert.equal(requests.length, 3);
  }
});

test("Pages failure still attempts the publisher", async () => {
  let calls = 0;
  const fetcher = async () => {
    if (++calls === 1) throw new Error("Network unavailable");
    return new Response(null, { status: 204 });
  };
  assert.equal((await refreshIfNeeded({ GITHUB_WEATHER_TOKEN: TOKEN }, fetcher, NOW)).result, "dispatch-accepted");
  assert.equal(calls, 3);
});

test("Workers-compatible redirect mode never follows Pages or credentialed GitHub redirects", async () => {
  const requests = [];
  const fetcher = async (url, options) => {
    // Workers throws for `error`; `follow` could forward Authorization to Location.
    assert.equal(options.redirect, "manual");
    requests.push({ url, options });
    return new Response(null, { status: 302, headers: { Location: "https://untrusted.invalid/" } });
  };
  await assert.rejects(refreshIfNeeded({ GITHUB_WEATHER_TOKEN: TOKEN }, fetcher, NOW), /HTTP 302/);
  assert.equal(requests.length, 3);
  assert.ok(requests[0].url.startsWith("https://wyhangzhou.github.io/"));
  assert.equal(requests[0].options.headers.Authorization, undefined);
  assert.equal(requests[2].url, "https://api.github.com/repos/wyhangzhou/kindle-weather-dashboard/actions/workflows/weather.yml/dispatches");
});

test("missing credentials and rejected dispatches fail instead of claiming a publish", async () => {
  await assert.rejects(refreshIfNeeded({}, transport(null).fetcher, NOW), /Missing GITHUB_WEATHER_TOKEN/);
  await assert.rejects(refreshIfNeeded({ GITHUB_WEATHER_TOKEN: TOKEN }, transport(null, 401).fetcher, NOW), /HTTP 401/);
  const accepted = await refreshIfNeeded({ GITHUB_WEATHER_TOKEN: TOKEN }, transport(null, 200).fetcher, NOW);
  assert.equal(accepted.result, "dispatch-accepted");
});

test("HTTP visitors cannot trigger a build", async () => {
  const response = await worker.fetch(new Request("https://example.invalid/refresh"));
  assert.equal(response.status, 404);
});

test("Cloudflare supplies bounded weather input to GitHub without exposing its secret to weather", async () => {
  const requests = [];
  const fetcher = async (url, options) => {
    requests.push({ url, options });
    if (url.startsWith("https://wyhangzhou.github.io/")) return new Response("null");
    if (url.startsWith("https://api.open-meteo.com/")) return Response.json({ current: { time: NOW } });
    return new Response(null, { status: 204 });
  };
  const result = await refreshIfNeeded({ GITHUB_WEATHER_TOKEN: TOKEN }, fetcher, NOW);
  assert.equal(result.result, "dispatch-accepted");
  assert.equal(requests[1].options.headers.Authorization, undefined);
  assert.equal(requests[1].options.redirect, "manual");
  const envelope = JSON.parse(JSON.parse(requests[2].options.body).inputs.weather_input);
  assert.deepEqual(envelope.config, weatherConfig);
  assert.equal(envelope.schema, "kindle-weather-source-v1");
  assert.equal(envelope.payload.current.time, NOW);
});

test("Cloudflare rejects redirects, rate limits and oversized weather responses without rapid retries", async () => {
  for (const response of [new Response(null, { status: 302 }), new Response(null, { status: 429 }), new Response("x".repeat(30001))]) {
    let calls = 0;
    await assert.rejects(fetchWeatherInput(async () => { calls++; return response; }));
    assert.equal(calls, 1);
  }
});
