import assert from "node:assert/strict";
import { test } from "node:test";
import worker, { refreshIfNeeded } from "./worker.mjs";

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
  const { url, options } = requests[1];
  assert.equal(url, "https://api.github.com/repos/wyhangzhou/kindle-weather-dashboard/actions/workflows/weather.yml/dispatches");
  assert.equal(options.method, "POST");
  assert.equal(options.redirect, "error");
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
    assert.equal(requests.length, 2);
  }
});

test("Pages failure still attempts the publisher", async () => {
  let calls = 0;
  const fetcher = async () => {
    if (++calls === 1) throw new Error("Network unavailable");
    return new Response(null, { status: 204 });
  };
  assert.equal((await refreshIfNeeded({ GITHUB_WEATHER_TOKEN: TOKEN }, fetcher, NOW)).result, "dispatch-accepted");
  assert.equal(calls, 2);
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
