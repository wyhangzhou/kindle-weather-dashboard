// Independent clock for the existing GitHub publisher. No public trigger.
const PAGES = "https://wyhangzhou.github.io/kindle-weather-dashboard/manifest.json";
const DISPATCH = "https://api.github.com/repos/wyhangzhou/kindle-weather-dashboard/actions/workflows/weather.yml/dispatches";

export function isFresh(manifest, now) {
  if (!manifest || manifest.schema !== "kindle-weather-v1") return false;
  const { generated_epoch: generated, weather_epoch: weather, expires_epoch: expires } = manifest;
  if (![generated, weather, expires].every(Number.isSafeInteger)) return false;
  const lifetime = expires - weather;
  return generated > 0 && weather > 0 && generated <= now + 60 && weather <= now + 600
    && generated >= weather - 600 && generated - weather <= 90 * 60
    && lifetime >= 15 * 60 && lifetime <= 180 * 60
    && now - generated < 20 * 60 && expires - now >= 45 * 60;
}

async function readManifest(fetcher, now) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 12000);
  try {
    const response = await fetcher(`${PAGES}?check=${now}`, {
      headers: { "Cache-Control": "no-cache" },
      redirect: "error", signal: controller.signal,
    });
    return response.ok ? await response.json() : null;
  } catch {
    return null; // An unreadable site also needs a publisher attempt.
  } finally {
    clearTimeout(timeout);
  }
}

export async function refreshIfNeeded(env, fetcher = fetch, now = Math.floor(Date.now() / 1000)) {
  if (isFresh(await readManifest(fetcher, now), now)) return { result: "already-fresh" };
  if (typeof env.GITHUB_WEATHER_TOKEN !== "string" || !env.GITHUB_WEATHER_TOKEN.trim()) {
    throw new Error("Missing GITHUB_WEATHER_TOKEN secret");
  }
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 12000);
  try {
    const response = await fetcher(DISPATCH, {
      method: "POST", redirect: "error", signal: controller.signal,
      headers: {
        "Accept": "application/vnd.github+json",
        "Content-Type": "application/json",
        "User-Agent": "kindle-weather-scheduler",
        "X-GitHub-Api-Version": "2026-03-10",
        "Authorization": `Bearer ${env.GITHUB_WEATHER_TOKEN}`,
      },
      body: JSON.stringify({ ref: "main" }),
    });
    // API versions can return either run details (200) or no content (204).
    const status = response.status;
    if (response.body) await response.body.cancel();
    if (status !== 200 && status !== 204) throw new Error(`GitHub dispatch rejected (HTTP ${status})`);
    // Accepted is not the same as successful generation or deployment.
    return { result: "dispatch-accepted", status };
  } finally {
    clearTimeout(timeout);
  }
}

export default {
  async scheduled(_controller, env, _ctx) {
    console.log(JSON.stringify(await refreshIfNeeded(env)));
  },
  async fetch() {
    return new Response("Not found\n", { status: 404 });
  },
};
