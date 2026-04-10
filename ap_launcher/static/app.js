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

function setStatus(text) {
  document.getElementById("status").textContent = text;
}

function findActionButton(repo, tag) {
  for (const btn of document.querySelectorAll("button[data-repo]")) {
    if (btn.dataset.repo === repo && btn.dataset.tag === tag) return btn;
  }
  return null;
}

function makeOpenLink(url, className) {
  const a = document.createElement("a");
  a.textContent = "Open";
  a.href = url;
  a.target = "_blank";
  a.rel = "noopener noreferrer";
  if (className) a.className = className;
  return a;
}

function makeLaunchButton(repo, tag, className) {
  const btn = document.createElement("button");
  btn.textContent = "Launch";
  btn.dataset.repo = repo;
  btn.dataset.tag = tag;
  if (className) btn.className = className;
  btn.onclick = async () => {
    setStatus(`Launching ${repo}:${tag}...`);
    try {
      const payload = { repo, tag };
      const launchResp = await fetchJSON("launch", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });

      document.getElementById("launch").textContent = JSON.stringify(
        launchResp,
        null,
        2
      );
      setStatus("Launch requested; waiting for LoadBalancer...");

      const launchId = launchResp.launchId;
      if (launchId) {
        saveJob(launchId, repo, tag);
        await pollLaunch(launchId, repo, tag);
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
  if (className) btn.className = className;
  btn.onclick = async () => {
    btn.disabled = true;
    setStatus("Ending job...");
    try {
      await fetchJSON(`launch/${launchId}`, { method: "DELETE" });
      removeJob(launchId);
      setStatus("Job ended");
    } catch (e) {
      setStatus(`Failed to end job: ${e}`);
      btn.disabled = false;
      return;
    }
    btn.replaceWith(makeLaunchButton(repo, tag, className));
  };
  return btn;
}

async function pollLaunch(launchId, repo, tag) {
  const actionBtn = findActionButton(repo, tag);
  if (actionBtn && actionBtn.dataset.launchId !== launchId) {
    actionBtn.replaceWith(makeEndButton(launchId, repo, tag, actionBtn.className));
  }

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
      const endBtn = findActionButton(repo, tag);
      if (endBtn) endBtn.replaceWith(makeLaunchButton(repo, tag, endBtn.className));
      return;
    }
    document.getElementById("launch").textContent = JSON.stringify(st, null, 2);

    const urls = st?.access?.urls ?? [];
    if (urls.length > 0) {
      const statusEl = document.getElementById("status");
      statusEl.innerHTML = "App is reachable: " + urls
        .map(u => `<a href="${u}" target="_blank" rel="noopener noreferrer">${u}</a>`)
        .join(", ");
      const endBtn = findActionButton(repo, tag);
      if (endBtn) endBtn.replaceWith(makeOpenLink(urls[0], endBtn.className));
      return;
    }
    if (st?.status === "Succeeded" || st?.status === "Failed") {
      setStatus(`Job ${st.status}; access cleaned up`);
      removeJob(launchId);
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
    repo.textContent = app.repo;

    const tag = document.createElement("td");
    tag.textContent = app.tag ?? "latest";

    const action = document.createElement("td");
    action.appendChild(makeLaunchButton(app.repo, app.tag ?? "latest"));

    tr.appendChild(repo);
    tr.appendChild(tag);
    tr.appendChild(action);

    tbody.appendChild(tr);
  }
}

async function restoreJobs() {
  for (const job of loadJobs()) {
    let st;
    try {
      st = await fetchJSON(`launch/${job.launchId}`);
    } catch {
      // Job is gone (expired or never existed); drop it
      removeJob(job.launchId);
      continue;
    }

    const urls = st?.access?.urls ?? [];
    if (urls.length > 0) {
      const btn = findActionButton(job.repo, job.tag);
      if (btn) btn.replaceWith(makeOpenLink(urls[0], btn.className));
    } else if (st?.status === "Succeeded" || st?.status === "Failed") {
      removeJob(job.launchId);
    } else {
      // Still running — show End button and resume polling in the background
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
    renderApps(data.apps ?? []);
    await restoreJobs();
    setStatus(`Loaded ${data.apps?.length ?? 0} app(s)`);
  } catch (e) {
    setStatus("Refresh failed");
    document.getElementById("launch").textContent = String(e);
  }
}

document.getElementById("refresh").onclick = refresh;

refresh();
