// Manager (front desk) screen.

const PW_KEY = "wayside_manager_pw";
let PW = null;
let model = null;
let currentTab = "line";
let dragging = false;
let busyAction = false;

function storeGet(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }
function storeSet(k, v) { try { v == null ? localStorage.removeItem(k) : localStorage.setItem(k, v); } catch (e) {} }
const $ = id => document.getElementById(id);

// ---------- Login ----------
function showLogin(msg) {
  PW = null; storeSet(PW_KEY, null);
  $("app").hidden = true; $("login").hidden = false;
  $("login-msg").textContent = msg || "";
  $("pw").value = "";
}

async function tryLogin(pw) {
  const tz = Intl.DateTimeFormat().resolvedOptions().timeZone;
  const { data, error } = await db.rpc("check_login", { p_password: pw, p_timezone: tz });
  if (error) { showLogin("Could not reach the database. Check the internet and try again."); return false; }
  if (!data) { showLogin("Wrong password. Please try again."); return false; }
  PW = pw; storeSet(PW_KEY, pw);
  $("login").hidden = true; $("app").hidden = false;
  return true;
}

// ---------- Talking to the database ----------
async function act(fn, args = {}) {
  if (busyAction) return null;
  busyAction = true;
  document.body.classList.add("working");
  try {
    const { data, error } = await db.rpc(fn, { p_password: PW, ...args });
    if (error) {
      if (String(error.message).includes("WRONG_PASSWORD")) { showLogin("The password was changed. Please log in again."); return null; }
      toast("Something went wrong: " + error.message, false);
      return null;
    }
    if (data && data.message) toast(data.message, data.ok);
    return data;
  } catch (e) {
    toast("No connection. Check the internet and try again.", false);
    return null;
  } finally {
    busyAction = false;
    document.body.classList.remove("working");
    await refresh();
  }
}

async function refresh() {
  if (!PW) return;
  try {
    model = await loadState();
    if (!dragging) renderAll();
    const { data } = await db.rpc("last_undo_label", { p_password: PW });
    const u = $("undo");
    u.disabled = !data;
    u.textContent = data ? "↶ Undo: " + data : "↶ Undo";
    if (currentTab === "history") loadHistory();
  } catch (e) {
    console.error(e);
    setLiveDot("ERROR");
  }
}

// ---------- Pop-up box ----------
function openModal(title, html) {
  $("modal-title").textContent = title;
  $("modal-body").innerHTML = html;
  $("modal").hidden = false;
}
function closeModal() { $("modal").hidden = true; $("modal-body").innerHTML = ""; }
$("modal-cancel").onclick = closeModal;
$("modal").addEventListener("click", e => { if (e.target.id === "modal") closeModal(); });

// ---------- Drawing ----------
function renderAll() {
  if (!model) return;
  $("salon").textContent = model.settings.salon_name;
  renderLineTab();
  if (currentTab === "techs" && !document.activeElement.matches("#tab-techs input")) renderTechsTab();
}

function skillText(e) {
  return e.skills && e.skills.length ? e.skills.map(s => esc(s.name)).join(", ") : "No services set";
}

function renderLineTab() {
  $("service-buttons").innerHTML = model.services.map(s =>
    `<button class="btn svc" data-walkin="${s.id}">${esc(s.name)}</button>`).join("");

  $("line").innerHTML = model.line.length ? model.line.map((e, i) => `
    <li class="row ${e.status}" data-id="${e.tech_id}">
      <span class="handle" aria-label="Drag to reorder">☰</span>
      <span class="num">${i + 1}</span>
      <span class="who">
        <span class="name">${esc(e.tech.name)}</span>
        ${e.status === "requested"
          ? `<span class="badge req">Requested · ${e.job ? esc(e.job.service_name) : ""}</span>`
          : `<span class="skills">${skillText(e)}</span>`}
      </span>
      <span class="actions">
        ${e.status === "requested"
          ? `<button class="btn primary" data-finish="${e.tech_id}">Done</button>`
          : `<button class="btn" data-request="${e.tech_id}">Requested</button>`}
        <button class="btn ghost x" data-remove="${e.tech_id}" aria-label="Take off line">✕</button>
      </span>
    </li>`).join("") : `<li class="empty">Nobody is on the line. Add techs below.</li>`;

  $("busy").innerHTML = model.busy.length ? model.busy.map(e => `
    <li class="busy-row">
      <span class="who"><span class="name">${esc(e.tech.name)}</span>
        <span class="svc">${e.job ? esc(e.job.service_name) + " · since " + fmtTime(e.job.started_at, model.settings.timezone) : ""}</span></span>
      <span class="actions">
        <button class="btn primary big-done" data-finish="${e.tech_id}">Done</button>
        <button class="btn ghost x" data-remove="${e.tech_id}" aria-label="Take off line">✕</button>
      </span>
    </li>`).join("") : `<li class="empty">Nobody is busy right now.</li>`;

  $("off").innerHTML = model.off.length
    ? model.off.map(t => `<button class="btn chip" data-add="${t.id}">+ ${esc(t.name)}</button>`).join("")
    : `<p class="empty">Everyone is on the line.</p>`;
}

function renderTechsTab() {
  $("tech-list").innerHTML = model.techs.length ? model.techs.map(t => {
    const mine = new Set((model.skills.get(t.id) || []).map(s => s.id));
    return `<div class="tech-card" data-tech="${t.id}">
      <div class="tech-head">
        <span class="name">${esc(t.name)}</span>
        <button class="btn ghost small" data-rename="${t.id}">Rename</button>
        <button class="btn ghost small danger" data-deltech="${t.id}">Delete</button>
      </div>
      <div class="chips">${model.services.map(s =>
        `<button class="btn chip toggle ${mine.has(s.id) ? "on" : ""}" data-toggle="${t.id}:${s.id}" aria-pressed="${mine.has(s.id)}">${mine.has(s.id) ? "✓ " : ""}${esc(s.name)}</button>`).join("")}
      </div>
    </div>`;
  }).join("") : `<p class="empty">No techs yet. Add one above.</p>`;

  $("service-list").innerHTML = model.services.map(s => `
    <li><span>${esc(s.name)}</span><button class="btn ghost small danger" data-delsvc="${s.id}">Delete</button></li>`).join("");
}

async function loadHistory() {
  const day = $("hist-date").value || salonToday(model.settings.timezone);
  const { data, error } = await db.from("jobs").select("*").eq("day", day).order("started_at");
  if (error) { $("history").innerHTML = `<p class="card">Could not load history.</p>`; return; }
  const tz = model.settings.timezone;
  if (!data.length) { $("history").innerHTML = `<section class="card"><p class="empty">No jobs on ${esc(fmtDate(day))}.</p></section>`; return; }
  const byTech = new Map();
  for (const j of data) {
    if (!byTech.has(j.tech_name)) byTech.set(j.tech_name, []);
    byTech.get(j.tech_name).push(j);
  }
  const names = [...byTech.keys()].sort((a, b) => a.localeCompare(b));
  $("history").innerHTML = `<p class="hint center">${esc(fmtDate(day))} · ${data.length} customer${data.length === 1 ? "" : "s"}</p>` +
    names.map(n => {
      const jobs = byTech.get(n);
      return `<section class="card hist">
        <h3>${esc(n)} <span class="count">${jobs.length} customer${jobs.length === 1 ? "" : "s"}</span></h3>
        <ul class="plain-list">${jobs.map(j => `<li>
          <span class="time">${fmtTime(j.started_at, tz)}</span>
          <span class="what">${esc(j.service_name)}</span>
          <span class="badge ${j.kind === "requested" ? "req" : "walk"}">${j.kind === "requested" ? "Requested" : "Walk-in"}</span>
          ${j.finished_at ? "" : `<span class="badge now">In progress</span>`}
        </li>`).join("")}</ul>
      </section>`;
    }).join("");
}

// ---------- Buttons ----------
function techName(id) { const t = model.techs.find(t => t.id === id); return t ? t.name : "this tech"; }
function onLineEntry(id) { return [...model.line, ...model.busy].find(e => e.tech_id === id); }

document.addEventListener("click", async ev => {
  const b = ev.target.closest("button");
  if (!b || !PW) return;
  const d = b.dataset;

  if (d.tab) return switchTab(d.tab);
  if (d.walkin) return act("assign_walkin", { p_service_id: +d.walkin });
  if (d.add) return act("add_to_line", { p_tech_id: +d.add });
  if (d.finish) return act("finish_job", { p_tech_id: +d.finish });

  if (d.request) {
    const id = +d.request;
    const e = onLineEntry(id);
    const list = (e && e.skills && e.skills.length) ? e.skills : model.services;
    const others = model.services.filter(s => !list.includes(s));
    openModal(`Customer asked for ${techName(id)}. Which service?`,
      `<div class="svc-grid">${list.map(s => `<button class="btn svc" data-reqsvc="${id}:${s.id}">${esc(s.name)}</button>`).join("")}</div>` +
      (others.length ? `<details><summary>Other services</summary><div class="svc-grid">${others.map(s =>
        `<button class="btn svc" data-reqsvc="${id}:${s.id}">${esc(s.name)}</button>`).join("")}</div></details>` : ""));
    return;
  }
  if (d.reqsvc) {
    const [t, s] = d.reqsvc.split(":").map(Number);
    closeModal();
    return act("mark_requested", { p_tech_id: t, p_service_id: s });
  }

  if (d.remove) {
    const id = +d.remove;
    const e = onLineEntry(id);
    if (e && e.status !== "waiting") {
      openModal(`${techName(id)} is still with a customer.`,
        `<p>Take them off the line anyway? Their job will be marked finished.</p>
         <button class="btn danger big" data-confirmremove="${id}">Yes, take off the line</button>`);
      return;
    }
    return act("remove_from_line", { p_tech_id: id });
  }
  if (d.confirmremove) { closeModal(); return act("remove_from_line", { p_tech_id: +d.confirmremove }); }

  if (b.id === "undo") return act("undo_last");
  if (b.id === "logout") return showLogin("Logged out.");

  if (d.toggle) {
    const [t, s] = d.toggle.split(":").map(Number);
    const mine = new Set((model.skills.get(t) || []).map(x => x.id));
    mine.has(s) ? mine.delete(s) : mine.add(s);
    return act("save_tech", { p_tech_id: t, p_name: techName(t), p_service_ids: [...mine] });
  }
  if (d.rename) {
    const id = +d.rename;
    openModal(`Rename ${techName(id)}`,
      `<form id="rename-form" class="stack"><input id="rename-input" value="${esc(techName(id))}" autocomplete="off">
       <button class="btn primary big" type="submit">Save</button></form>`);
    $("rename-form").onsubmit = async e => {
      e.preventDefault();
      const mine = (model.skills.get(id) || []).map(x => x.id);
      const name = $("rename-input").value;
      closeModal();
      await act("save_tech", { p_tech_id: id, p_name: name, p_service_ids: mine });
    };
    $("rename-input").focus();
    return;
  }
  if (d.deltech) {
    const id = +d.deltech;
    openModal(`Delete ${techName(id)}?`,
      `<p>They will be removed from the salon list. Their past history stays.</p>
       <button class="btn danger big" data-confirmdeltech="${id}">Yes, delete</button>`);
    return;
  }
  if (d.confirmdeltech) { closeModal(); return act("delete_tech", { p_tech_id: +d.confirmdeltech }); }
  if (d.delsvc) {
    const s = model.services.find(x => x.id === +d.delsvc);
    openModal(`Delete ${s ? s.name : "service"}?`,
      `<p>It will disappear from the buttons and from every tech. Past history keeps the name.</p>
       <button class="btn danger big" data-confirmdelsvc="${d.delsvc}">Yes, delete</button>`);
    return;
  }
  if (d.confirmdelsvc) { closeModal(); return act("delete_service", { p_service_id: +d.confirmdelsvc }); }
});

function switchTab(tab) {
  currentTab = tab;
  document.querySelectorAll(".tab").forEach(t => t.classList.toggle("active", t.dataset.tab === tab));
  ["line", "techs", "history"].forEach(n => { $("tab-" + n).hidden = n !== tab; });
  if (tab === "techs") renderTechsTab();
  if (tab === "history") {
    if (!$("hist-date").value) $("hist-date").value = salonToday(model.settings.timezone);
    loadHistory();
  }
  window.scrollTo(0, 0);
}

$("hist-date").addEventListener("change", loadHistory);

$("add-tech").onsubmit = async e => {
  e.preventDefault();
  const name = $("new-tech").value.trim();
  if (!name) return;
  const r = await act("save_tech", { p_tech_id: null, p_name: name, p_service_ids: [] });
  if (r && r.ok) { $("new-tech").value = ""; renderTechsTab(); }
};
$("add-service").onsubmit = async e => {
  e.preventDefault();
  const name = $("new-service").value.trim();
  if (!name) return;
  const r = await act("add_service", { p_name: name });
  if (r && r.ok) { $("new-service").value = ""; renderTechsTab(); }
};
$("change-pw").onsubmit = async e => {
  e.preventDefault();
  const np = $("new-pw").value;
  const r = await act("change_password", { p_new_password: np });
  if (r && r.ok) { PW = np; storeSet(PW_KEY, np); $("new-pw").value = ""; }
};
$("login-form").onsubmit = async e => {
  e.preventDefault();
  if (await tryLogin($("pw").value)) start();
};

// Drag to reorder the line.
function setupSortable() {
  Sortable.create($("line"), {
    handle: ".handle",
    animation: 150,
    filter: ".empty",
    onStart: () => { dragging = true; },
    onEnd: async ev => {
      dragging = false;
      if (ev.oldIndex === ev.newIndex) return renderAll();
      const ids = [...$("line").querySelectorAll("li[data-id]")].map(li => +li.dataset.id);
      await act("reorder_line", { p_tech_ids: ids });
    },
  });
}

// ---------- Start ----------
let started = false;
function start() {
  if (started) return refresh();
  started = true;
  setupSortable();
  subscribeLive(refresh, setLiveDot);
  refresh();
}

if (!CONFIGURED) {
  showNotConfigured();
} else {
  const saved = storeGet(PW_KEY);
  if (saved) tryLogin(saved).then(ok => { if (ok) start(); });
  else showLogin();
}
