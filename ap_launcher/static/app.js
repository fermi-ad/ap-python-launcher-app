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
    const btn = document.createElement("button");
    btn.textContent = "Launch";
    btn.onclick = async () => {
      setStatus(`Launching ${app.repo}:${app.tag ?? "latest"}...`);
      try {
        const payload = { repo: app.repo, tag: app.tag ?? "latest" };
        const launchResp = await fetchJSON("/launch", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(payload),
        });
        document.getElementById("launch").textContent = JSON.stringify(
          launchResp,
          null,
          2
        );
        setStatus("Launch requested");
      } catch (e) {
        document.getElementById("launch").textContent = String(e);
        setStatus("Launch failed");
      }
    };

    action.appendChild(btn);

    tr.appendChild(repo);
    tr.appendChild(tag);
    tr.appendChild(action);

    tbody.appendChild(tr);
  }
}

async function refresh() {
  setStatus("Refreshing... ");
  try {
    const data = await fetchJSON("/apps");
    renderApps(data.apps ?? []);
    setStatus(`Loaded ${data.apps?.length ?? 0} app(s)`);
  } catch (e) {
    setStatus("Refresh failed");
    document.getElementById("launch").textContent = String(e);
  }
}

document.getElementById("refresh").onclick = refresh;

refresh();
