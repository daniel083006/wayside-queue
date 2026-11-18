// Read-only tech view.

function badgeFor(e) {
  if (e.status === "requested") {
    return `<span class="badge req">Requested${e.job ? " · " + esc(e.job.service_name) : ""}</span>`;
  }
  return "";
}

function render(m) {
  document.getElementById("salon").textContent = m.settings.salon_name;
  document.title = m.settings.salon_name + " Line";

  const line = document.getElementById("line");
  line.innerHTML = m.line.length
    ? m.line.map((e, i) => `
        <li class="row ${e.status}">
          <span class="num">${i + 1}</span>
          <span class="name">${esc(e.tech.name)}</span>
          ${badgeFor(e)}
        </li>`).join("")
    : `<li class="empty">Nobody is on the line yet.</li>`;

  const busy = document.getElementById("busy");
  busy.innerHTML = m.busy.length
    ? m.busy.map(e => `
        <li class="busy-row">
          <span class="name">${esc(e.tech.name)}</span>
          <span class="svc">${e.job ? esc(e.job.service_name) : ""}</span>
        </li>`).join("")
    : `<li class="empty">Nobody is busy right now.</li>`;
}

async function refresh() {
  try { render(await loadState()); }
  catch (err) { console.error(err); setLiveDot("ERROR"); }
}

if (!CONFIGURED) {
  showNotConfigured();
} else {
  db.rpc("refresh_day").then(refresh);
  subscribeLive(refresh, setLiveDot);
}
