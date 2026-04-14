const JOBS_KEY = "ap_launcher_jobs";

function loadJobs() {
  try { return JSON.parse(localStorage.getItem(JOBS_KEY) ?? "[]"); }
  catch { return []; }
}

function saveJob(launchId, repo, tag) {
  // Replace any existing entry for the same repo+tag
  const jobs = loadJobs().filter(j => !(j.repo === repo && j.tag === tag));
  jobs.push({ launchId, repo, tag });
  localStorage.setItem(JOBS_KEY, JSON.stringify(jobs));
}

function removeJob(launchId) {
  const jobs = loadJobs().filter(j => j.launchId !== launchId);
  localStorage.setItem(JOBS_KEY, JSON.stringify(jobs));
}

async function fetchJSON(url, opts) {
  const res = await fetch(url, opts);
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`${res.status} ${res.statusText}: ${text}`);
  }
  return await res.json();
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

async function pollUntilEnded(launchId, { timeoutMs = 30000, onStatus } = {}) {
  const start = Date.now();
  // Fast at first, then back off a bit.
  const delaysMs = [250, 250, 500, 500, 1000, 1000, 2000, 2000, 3000, 3000];
  let i = 0;

  while (Date.now() - start < timeoutMs) {
    try {
      const st = await fetchJSON(`launch/${launchId}`);
      if (typeof onStatus === "function") onStatus(st);
      if (st?.status === "NotFound" || st?.status === "Succeeded" || st?.status === "Failed") {
        return { ended: true, status: st?.status ?? "NotFound" };
      }
    } catch {
      // If the status endpoint errors (e.g. 404), treat as ended.
      if (typeof onStatus === "function") onStatus({ launchId, status: "NotFound" });
      return { ended: true, status: "NotFound" };
    }

    const delay = delaysMs[Math.min(i, delaysMs.length - 1)];
    i += 1;
    await sleep(delay);
  }

  return { ended: false, status: "Timeout" };
}

function setStatus(text) {
  document.getElementById("status").textContent = text;
}

function findActionButton(repo, tag) {
  for (const btn of document.querySelectorAll("button[data-repo]")) {
    if (btn.dataset.repo === repo && btn.dataset.tag === tag) return btn;
  }
  return null;
}

function setRowStatus(repo, tag, text) {
  for (const td of document.querySelectorAll("td.row-status[data-repo]")) {
    if (td.dataset.repo === repo && td.dataset.tag === tag) {
      td.textContent = text;
      return;
    }
  }
}

function makeConnectLink(url, className) {
  const a = document.createElement("a");
  a.textContent = "Connect";
  a.href = url;
  a.target = "_blank";
  a.rel = "noopener noreferrer";
  a.className = (className ? className + " " : "") + "connect-btn";
  return a;
}

function makeLaunchButton(repo, tag, className) {
  const btn = document.createElement("button");
  btn.textContent = "Launch";
  btn.dataset.repo = repo;
  btn.dataset.tag = tag;
  if (className) btn.className = className;
  btn.onclick = async () => {
    setStatus(`Launching ${repo}...`);
    try {
      // Send repo only — backend resolves the tag from Harbor.
      const launchResp = await fetchJSON("launch", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ repo }),
      });

      document.getElementById("launch").textContent = JSON.stringify(
        launchResp,
        null,
        2
      );
      setStatus("Launch requested; waiting for LoadBalancer...");

      const launchId = launchResp.launchId;
      // Use the tag the backend resolved, not what the UI was showing.
      const resolvedTag = launchResp.tag ?? tag;
      if (launchId) {
        saveJob(launchId, repo, resolvedTag);
        await pollLaunch(launchId, repo, resolvedTag);
      }
    } catch (e) {
      document.getElementById("launch").textContent = String(e);
      setStatus("Launch failed");
    }
  };
  return btn;
}

function makeEndButton(launchId, repo, tag, className) {
  const btn = document.createElement("button");
  btn.textContent = "End";
  btn.dataset.repo = repo;
  btn.dataset.tag = tag;
  btn.dataset.launchId = launchId;
  btn.className = (className ? className + " " : "") + "end-btn";
  btn.onclick = async () => {
    btn.disabled = true;
    setStatus("Ending job...");
    setRowStatus(repo, tag, "Ending...");

    try {
      await fetchJSON(`launch/${launchId}`, { method: "DELETE" });
    } catch (e) {
      setStatus(`Failed to end job: ${e}`);
      setRowStatus(repo, tag, "—");
      btn.disabled = false;
      return;
    }

    // Poll until the job is actually gone (or terminal), since Kubernetes deletion is async.
    const ended = await pollUntilEnded(launchId, {
      timeoutMs: 30000,
      onStatus: (st) => {
        document.getElementById("launch").textContent = JSON.stringify(st, null, 2);
      },
    });
    removeJob(launchId);

    if (ended.ended) {
      setStatus("Job ended");
    } else {
      setStatus("End requested; still terminating...");
    }
    setRowStatus(repo, tag, "—");

    const cell = btn.parentNode;
    if (cell) cell.querySelectorAll("a.connect-btn").forEach(a => a.remove());
    btn.replaceWith(makeLaunchButton(repo, tag, className));
  };
  return btn;
}

async function pollLaunch(launchId, repo, tag) {
  const actionBtn = findActionButton(repo, tag);
  if (actionBtn && actionBtn.dataset.launchId !== launchId) {
    actionBtn.replaceWith(makeEndButton(launchId, repo, tag, actionBtn.className));
  }
  setRowStatus(repo, tag, "Pending");

  for (let i = 0; i < 60; i++) {
    await new Promise((r) => setTimeout(r, 2000));

    // Stop polling if user already ended the job
    if (!loadJobs().some(j => j.launchId === launchId)) return;

    let st;
    try {
      st = await fetchJSON(`launch/${launchId}`);
    } catch {
      removeJob(launchId);
      setStatus("Job no longer found; cleared from saved jobs");
      setRowStatus(repo, tag, "—");
      const endBtn = findActionButton(repo, tag);
      if (endBtn) endBtn.replaceWith(makeLaunchButton(repo, tag, endBtn.className));
      return;
    }
    document.getElementById("launch").textContent = JSON.stringify(st, null, 2);
    setRowStatus(repo, tag, st?.status ?? "—");

    const urls = st?.access?.urls ?? [];
    const accessStatus = st?.access?.status ?? "Pending";
    if (urls.length > 0 && accessStatus === "Ready") {
      const statusEl = document.getElementById("status");
      statusEl.innerHTML = "App is reachable: " + urls
        .map(u => `<a href="${u}" target="_blank" rel="noopener noreferrer">${u}</a>`)
        .join(", ");
      setRowStatus(repo, tag, "Ready");
      const endBtn = findActionButton(repo, tag);
      if (endBtn) endBtn.parentNode.insertBefore(makeConnectLink(urls[0], endBtn.className), endBtn);
      return;
    }
    if (st?.status === "Succeeded" || st?.status === "Failed") {
      setStatus(`Job ${st.status}; access cleaned up`);
      removeJob(launchId);
      setRowStatus(repo, tag, "—");
      const endBtn = findActionButton(repo, tag);
      if (endBtn) endBtn.replaceWith(makeLaunchButton(repo, tag, endBtn.className));
      return;
    }
    setStatus("Waiting for LoadBalancer...");
  }
}

function renderApps(apps) {
  const tbody = document.getElementById("apps");
  tbody.innerHTML = "";

  for (const app of apps) {
    const tr = document.createElement("tr");

    const repo = document.createElement("td");
    repo.textContent = app.repo.replace(/^ap-python\//, "");

    const status = document.createElement("td");
    status.className = "row-status";
    status.dataset.repo = app.repo;
    status.dataset.tag = app.tag ?? "latest";
    status.textContent = "—";

    const action = document.createElement("td");
    action.appendChild(makeLaunchButton(app.repo, app.tag ?? "latest"));

    tr.appendChild(repo);
    tr.appendChild(status);
    tr.appendChild(action);

    tbody.appendChild(tr);
  }
}

async function restoreJobs(currentTags = new Map()) {
  // currentTags: Map<repo, resolvedTag> from the latest /apps response.
  for (const job of loadJobs()) {
    // If the saved tag no longer matches the current resolved tag for this
    // repo, the job is for a stale image — drop it and show Launch.
    if (currentTags.has(job.repo) && currentTags.get(job.repo) !== job.tag) {
      removeJob(job.launchId);
      continue;
    }

    let st;
    try {
      st = await fetchJSON(`launch/${job.launchId}`);
    } catch {
      // Job is gone (expired or never existed); drop it
      removeJob(job.launchId);
      continue;
    }

    const urls = st?.access?.urls ?? [];
    const accessStatus = st?.access?.status ?? "Pending";
    if (urls.length > 0 && accessStatus === "Ready") {
      setRowStatus(job.repo, job.tag, "Ready");
      const btn = findActionButton(job.repo, job.tag);
      if (btn) {
        const connectLink = makeConnectLink(urls[0], btn.className);
        const endBtn = makeEndButton(job.launchId, job.repo, job.tag, btn.className);
        btn.replaceWith(connectLink);
        connectLink.after(endBtn);
      }
    } else if (st?.status === "Succeeded" || st?.status === "Failed") {
      removeJob(job.launchId);
    } else {
      // Still running — show End button and resume polling in the background
      setRowStatus(job.repo, job.tag, st?.status ?? "Running");
      const btn = findActionButton(job.repo, job.tag);
      if (btn) btn.replaceWith(makeEndButton(job.launchId, job.repo, job.tag, btn.className));
      pollLaunch(job.launchId, job.repo, job.tag);
    }
  }
}

async function refresh() {
  setStatus("Refreshing... ");
  try {
    const data = await fetchJSON("apps");
    const apps = data.apps ?? [];
    renderApps(apps);
    // Build a map of repo → current resolved tag for stale-job detection.
    const currentTags = new Map(apps.map(a => [a.repo, a.tag]));
    await restoreJobs(currentTags);
    setStatus(`Loaded ${apps.length} app(s)`);
  } catch (e) {
    setStatus("Refresh failed");
    document.getElementById("launch").textContent = String(e);
  }
}

document.getElementById("refresh").onclick = refresh;

refresh();
