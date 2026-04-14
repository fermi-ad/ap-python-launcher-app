/**
 * Frontend tests for ap_launcher/static/app.js
 *
 * Loading strategy:
 * - The script is eval'd ONCE in a global beforeAll via window.eval(), which
 *   runs in the jsdom global scope (has document/localStorage/fetch) and adds
 *   function declarations to window (=== global).
 * - Functions are captured into module-level variables after the eval.
 * - Between tests, only the DOM content and localStorage state are reset;
 *   the script itself is not re-evaluated (avoids 'const' re-declaration errors).
 *
 * The script calls refresh() at the bottom; we flush that with a real setTimeout(0)
 * tick before any test runs.
 */

const fs = require("fs");
const path = require("path");

const APP_JS_PATH = path.resolve(
  __dirname,
  "../../ap_launcher/static/app.js"
);
const APP_JS_SRC = fs.readFileSync(APP_JS_PATH, "utf-8");
const JOBS_KEY = "ap_launcher_jobs";

// Captured references — populated once in beforeAll.
let loadJobs, saveJob, removeJob, fetchJSON, setStatus;
let renderApps, pollLaunch, restoreJobs, refresh;

// ---------------------------------------------------------------------------
// Mock helpers
// ---------------------------------------------------------------------------

function mockFetchOk(data) {
  return jest.fn().mockResolvedValue({
    ok: true,
    json: () => Promise.resolve(data),
    text: () => Promise.resolve(JSON.stringify(data)),
  });
}

function mockFetchError(status, statusText, body) {
  return jest.fn().mockResolvedValue({
    ok: false,
    status,
    statusText,
    json: () => Promise.resolve({}),
    text: () => Promise.resolve(body),
  });
}

function mockFetchNetworkError(msg = "Network error") {
  return jest.fn().mockRejectedValue(new Error(msg));
}

// ---------------------------------------------------------------------------
// One-time script loading
// ---------------------------------------------------------------------------

/** Reset only the inner content of the pre-existing DOM nodes. */
function resetDOM() {
  document.getElementById("apps").innerHTML = "";
  document.getElementById("status").textContent = "";
  document.getElementById("launch").textContent = "";
}

beforeAll(async () => {
  // Build the minimal DOM the script expects.
  // <tbody> must live inside <table> — jsdom follows browser HTML parsing rules.
  document.body.innerHTML = `
    <button id="refresh">Refresh</button>
    <span id="status"></span>
    <table><tbody id="apps"></tbody></table>
    <pre id="launch"></pre>
  `;

  // Mock fetch BEFORE eval because app.js calls refresh() at load time.
  global.fetch = mockFetchOk({ apps: [] });

  // window.eval() = indirect eval in jsdom global scope:
  //   - 'document', 'localStorage', 'fetch' are the jsdom globals.
  //   - 'const' declarations get their own block scope (no re-declaration on second eval).
  //   - function declarations are added to window (=== global).
  window.eval(APP_JS_SRC);

  // Capture references from global.
  loadJobs    = global.loadJobs;
  saveJob     = global.saveJob;
  removeJob   = global.removeJob;
  fetchJSON   = global.fetchJSON;
  setStatus   = global.setStatus;
  renderApps  = global.renderApps;
  pollLaunch  = global.pollLaunch;
  restoreJobs = global.restoreJobs;
  refresh     = global.refresh;

  // Flush the initial refresh() Promise so it completes before any test runs.
  await new Promise((r) => setTimeout(r, 0));
});

// Default beforeEach: reset DOM + state (localStorage is cleared by setup.js).
beforeEach(() => {
  resetDOM();
  global.fetch = mockFetchOk({ apps: [] });
});

// ---------------------------------------------------------------------------
// localStorage helpers
// ---------------------------------------------------------------------------

describe("loadJobs", () => {
  test("returns empty array when localStorage is empty", () => {
    expect(loadJobs()).toEqual([]);
  });

  test("returns parsed array when set", () => {
    const jobs = [{ launchId: "x", repo: "r", tag: "t" }];
    localStorage.setItem(JOBS_KEY, JSON.stringify(jobs));
    expect(loadJobs()).toEqual(jobs);
  });

  test("returns empty array when localStorage has invalid JSON", () => {
    localStorage.setItem(JOBS_KEY, "bad json");
    expect(loadJobs()).toEqual([]);
  });
});

describe("saveJob", () => {
  test("adds a new job to localStorage", () => {
    saveJob("id1", "repo-a", "latest");
    expect(loadJobs()).toEqual([{ launchId: "id1", repo: "repo-a", tag: "latest" }]);
  });

  test("replaces existing entry for the same repo+tag", () => {
    saveJob("old-id", "repo-a", "latest");
    saveJob("new-id", "repo-a", "latest");
    const jobs = loadJobs();
    expect(jobs).toHaveLength(1);
    expect(jobs[0].launchId).toBe("new-id");
  });

  test("preserves entries for different repo+tag combinations", () => {
    saveJob("id1", "repo-a", "latest");
    saveJob("id2", "repo-b", "latest");
    expect(loadJobs()).toHaveLength(2);
  });
});

describe("removeJob", () => {
  test("removes job with matching launchId", () => {
    saveJob("id1", "r", "t");
    removeJob("id1");
    expect(loadJobs()).toEqual([]);
  });

  test("leaves other jobs intact", () => {
    saveJob("id1", "r1", "t");
    saveJob("id2", "r2", "t");
    removeJob("id1");
    const jobs = loadJobs();
    expect(jobs).toHaveLength(1);
    expect(jobs[0].launchId).toBe("id2");
  });

  test("is no-op when launchId is not present", () => {
    saveJob("id1", "r", "t");
    removeJob("nonexistent");
    expect(loadJobs()).toHaveLength(1);
  });
});

// ---------------------------------------------------------------------------
// fetchJSON
// ---------------------------------------------------------------------------

describe("fetchJSON", () => {
  test("resolves to parsed JSON on ok response", async () => {
    global.fetch = mockFetchOk({ key: "val" });
    const result = await fetchJSON("/url");
    expect(result).toEqual({ key: "val" });
  });

  test("throws error with status and body text on non-ok response", async () => {
    global.fetch = mockFetchError(429, "Too Many Requests", "limit exceeded");
    await expect(fetchJSON("/url")).rejects.toThrow("429 Too Many Requests: limit exceeded");
  });

  test("passes opts to fetch", async () => {
    const mockF = mockFetchOk({});
    global.fetch = mockF;
    await fetchJSON("/url", { method: "POST" });
    expect(mockF).toHaveBeenCalledWith("/url", { method: "POST" });
  });
});

// ---------------------------------------------------------------------------
// renderApps
// ---------------------------------------------------------------------------

describe("renderApps", () => {
  test("renders one row per app", () => {
    renderApps([{ repo: "a", tag: "v1" }, { repo: "b", tag: "v2" }]);
    expect(document.querySelectorAll("#apps tr")).toHaveLength(2);
  });

  test("clears previous rows before rendering", () => {
    renderApps([{ repo: "a", tag: "v1" }]);
    renderApps([{ repo: "b", tag: "v2" }, { repo: "c", tag: "v3" }]);
    expect(document.querySelectorAll("#apps tr")).toHaveLength(2);
  });

  test("row contains repo name, tag, and Launch button", () => {
    renderApps([{ repo: "proj/app", tag: "latest" }]);
    const row = document.querySelector("#apps tr");
    expect(row.textContent).toContain("proj/app");
    const btn = row.querySelector("button");
    expect(btn.dataset.tag).toBe("latest");
    expect(btn.textContent).toBe("Launch");
  });

  test("button has data-repo and data-tag attributes", () => {
    renderApps([{ repo: "proj/app", tag: "latest" }]);
    const btn = document.querySelector("button[data-repo]");
    expect(btn.dataset.repo).toBe("proj/app");
    expect(btn.dataset.tag).toBe("latest");
  });

  test("null tag is shown as 'latest'", () => {
    renderApps([{ repo: "r", tag: null }]);
    const btn = document.querySelector("button[data-repo]");
    expect(btn.dataset.tag).toBe("latest");
  });

  test("undefined tag is shown as 'latest'", () => {
    renderApps([{ repo: "r" }]);
    const btn = document.querySelector("button[data-repo]");
    expect(btn.dataset.tag).toBe("latest");
  });

  test("renders empty tbody when apps is empty", () => {
    renderApps([]);
    expect(document.querySelector("#apps").innerHTML).toBe("");
  });
});

// ---------------------------------------------------------------------------
// pollLaunch — fake timers to skip 2-second per-iteration delays
// ---------------------------------------------------------------------------

describe("pollLaunch", () => {
  beforeEach(() => {
    // Switch to fake timers AFTER beforeAll has already loaded the script with real timers.
    jest.useFakeTimers();
  });

  afterEach(() => {
    jest.clearAllTimers();
    jest.useRealTimers();
  });

  /** Advance fake clock and flush pending Promises. */
  async function tick(ms = 2000) {
    jest.advanceTimersByTime(ms);
    for (let i = 0; i < 10; i++) await Promise.resolve();
  }

  test("updates #launch element with status JSON on each poll", async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ status: "Running", access: { urls: [] } }),
      text: () => Promise.resolve(""),
    });

    saveJob("id1", "r", "t");
    pollLaunch("id1", "r", "t");
    await tick();

    expect(document.getElementById("launch").textContent).toContain("Running");
  });

  test("exits and shows URL when access.urls is populated", async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ status: "Running", access: { status: "Ready", urls: ["http://1.2.3.4:80/"] } }),
      text: () => Promise.resolve(""),
    });

    saveJob("id1", "r", "t");
    const p = pollLaunch("id1", "r", "t");
    await tick();
    await p;

    expect(document.getElementById("status").innerHTML).toContain("1.2.3.4");
  });

  test("replaces Launch button with Connect link when URL available", async () => {
    renderApps([{ repo: "myrepo", tag: "latest" }]);

    global.fetch = jest.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ status: "Running", access: { status: "Ready", urls: ["http://host:80/"] } }),
      text: () => Promise.resolve(""),
    });

    saveJob("id1", "myrepo", "latest");
    const p = pollLaunch("id1", "myrepo", "latest");
    await tick();
    await p;

    expect(document.querySelector("a[href='http://host:80/']")).not.toBeNull();
  });

  test("exits and removes job when status is Succeeded", async () => {
    saveJob("id1", "r", "t");

    global.fetch = jest.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ status: "Succeeded", access: { urls: [] } }),
      text: () => Promise.resolve(""),
    });

    const p = pollLaunch("id1", "r", "t");
    await tick();
    await p;

    expect(loadJobs().find((j) => j.launchId === "id1")).toBeUndefined();
  });

  test("exits and removes job when status is Failed", async () => {
    saveJob("id1", "r", "t");

    global.fetch = jest.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ status: "Failed", access: { urls: [] } }),
      text: () => Promise.resolve(""),
    });

    const p = pollLaunch("id1", "r", "t");
    await tick();
    await p;

    expect(loadJobs().find((j) => j.launchId === "id1")).toBeUndefined();
  });

  test("removes job and updates status on fetch error", async () => {
    saveJob("id1", "r", "t");
    global.fetch = mockFetchNetworkError("gone");

    const p = pollLaunch("id1", "r", "t");
    await tick();
    await p;

    expect(loadJobs().find((j) => j.launchId === "id1")).toBeUndefined();
    expect(document.getElementById("status").textContent).toContain("no longer found");
  });

  test("stops after 60 polls without resolution", async () => {
    const mockF = jest.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ status: "Running", access: { urls: [] } }),
      text: () => Promise.resolve(""),
    });
    global.fetch = mockF;

    const p = pollLaunch("id1", "r", "t");
    for (let i = 0; i < 61; i++) {
      await tick();
    }
    await p;

    const pollCalls = mockF.mock.calls.filter((c) => c[0] && String(c[0]).includes("launch/"));
    expect(pollCalls.length).toBeLessThanOrEqual(60);
  });
});

// ---------------------------------------------------------------------------
// restoreJobs
// ---------------------------------------------------------------------------

describe("restoreJobs", () => {
  test("does nothing when no saved jobs", async () => {
    const mockF = mockFetchOk({ apps: [] });
    global.fetch = mockF;
    mockF.mockClear();

    await restoreJobs();

    const launchCalls = mockF.mock.calls.filter(
      (c) => c[0] && String(c[0]).includes("launch/")
    );
    expect(launchCalls).toHaveLength(0);
  });

  test("removes job from storage on fetch error during restore", async () => {
    saveJob("expired-id", "r", "t");
    global.fetch = mockFetchNetworkError();
    await restoreJobs();
    expect(loadJobs().find((j) => j.launchId === "expired-id")).toBeUndefined();
  });

  test("removes Succeeded job on restore", async () => {
    saveJob("done-id", "r", "t");
    global.fetch = jest.fn().mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve({ status: "Succeeded", access: { urls: [] } }),
      text: () => Promise.resolve(""),
    });
    await restoreJobs();
    expect(loadJobs().find((j) => j.launchId === "done-id")).toBeUndefined();
  });

  test("removes Failed job on restore", async () => {
    saveJob("failed-id", "r", "t");
    global.fetch = jest.fn().mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve({ status: "Failed", access: { urls: [] } }),
      text: () => Promise.resolve(""),
    });
    await restoreJobs();
    expect(loadJobs().find((j) => j.launchId === "failed-id")).toBeUndefined();
  });

  test("replaces button with link for already-ready job", async () => {
    renderApps([{ repo: "myrepo", tag: "latest" }]);
    saveJob("ready-id", "myrepo", "latest");
    global.fetch = jest.fn().mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve({ status: "Running", access: { status: "Ready", urls: ["http://host:80/"] } }),
      text: () => Promise.resolve(""),
    });
    await restoreJobs();
    expect(document.querySelector("a[href='http://host:80/']")).not.toBeNull();
  });

  test("keeps running job in storage and resumes polling", async () => {
    saveJob("running-id", "r", "t");
    global.fetch = jest.fn().mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve({ status: "Running", access: { urls: [] } }),
      text: () => Promise.resolve(""),
    });
    await restoreJobs();
    // Job is still in storage — pollLaunch will clean it up later
    expect(loadJobs().find((j) => j.launchId === "running-id")).toBeDefined();
  });
});
