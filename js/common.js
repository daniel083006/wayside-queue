// Shared code used by both the tech view and the manager screen.

const CFG = window.APP_CONFIG || {};
const CONFIGURED = /^https:\/\//.test(CFG.SUPABASE_URL || "") && !/PASTE-/.test(CFG.SUPABASE_KEY || "PASTE-");
const db = CONFIGURED ? window.supabase.createClient(CFG.SUPABASE_URL, CFG.SUPABASE_KEY) : null;

// Make text safe to put on the page.
function esc(s) {
  return String(s == null ? "" : s).replace(/[&<>"']/g, c =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}

function fmtTime(ts, tz) {
  if (!ts) return "";
  try {
    return new Intl.DateTimeFormat("en-US", { hour: "numeric", minute: "2-digit", timeZone: tz }).format(new Date(ts));
  } catch (e) {
    return new Date(ts).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
  }
}

function salonToday(tz) {
  try { return new Intl.DateTimeFormat("en-CA", { timeZone: tz }).format(new Date()); }
  catch (e) { return new Date().toISOString().slice(0, 10); }
}

function fmtDate(isoDay) {
  const [y, m, d] = isoDay.split("-").map(Number);
  return new Date(y, m - 1, d).toLocaleDateString("en-US", { weekday: "long", month: "long", day: "numeric", year: "numeric" });
}

// Read everything needed to draw the line.
async function loadState() {
  const [settings, services, techs, techServices, roster] = await Promise.all([
    db.from("settings").select("*").eq("id", 1).maybeSingle(),
    db.from("services").select("*").order("sort_order").order("id"),
    db.from("techs").select("*").order("name"),
    db.from("tech_services").select("*"),
    db.from("roster").select("*"),
  ]);
  for (const r of [settings, services, techs, techServices, roster]) if (r.error) throw r.error;
  const s = settings.data || { salon_name: "Wayside Nails", timezone: "America/New_York" };
  const jobIds = roster.data.map(r => r.job_id).filter(Boolean);
  let jobs = [];
  if (jobIds.length) {
    const j = await db.from("jobs").select("*").in("id", jobIds);
    if (j.error) throw j.error;
    jobs = j.data;
  }
  return buildModel(s, services.data, techs.data, techServices.data, roster.data, jobs);
}

function buildModel(settings, services, techs, techServices, roster, jobs) {
  const serviceById = new Map(services.map(s => [s.id, s]));
  const jobById = new Map(jobs.map(j => [j.id, j]));
  const activeTechs = techs.filter(t => !t.archived);
  const skills = new Map(activeTechs.map(t => [t.id, []]));
  for (const ts of techServices) {
    const svc = serviceById.get(ts.service_id);
    if (skills.has(ts.tech_id) && svc && !svc.archived) skills.get(ts.tech_id).push(svc);
  }
  for (const list of skills.values()) list.sort((a, b) => a.sort_order - b.sort_order || a.id - b.id);
  const techById = new Map(activeTechs.map(t => [t.id, t]));
  const entries = roster
    .filter(r => techById.has(r.tech_id))
    .map(r => ({ ...r, tech: techById.get(r.tech_id), job: jobById.get(r.job_id) || null, skills: skills.get(r.tech_id) }));
  const line = entries.filter(e => e.position != null).sort((a, b) => a.position - b.position);
  const busy = entries.filter(e => e.status === "busy")
    .sort((a, b) => String(a.job ? a.job.started_at : "").localeCompare(String(b.job ? b.job.started_at : "")));
  const onLine = new Set(entries.map(e => e.tech_id));
  const off = activeTechs.filter(t => !onLine.has(t.id));
  return {
    settings, services: services.filter(s => !s.archived), allServices: services,
    techs: activeTechs, skills, line, busy, off,
  };
}

// Call onChange whenever anything changes in the database (live updates).
function subscribeLive(onChange, onStatus) {
  let timer = null;
  const kick = () => { clearTimeout(timer); timer = setTimeout(onChange, 150); };
  const channel = db.channel("salon-live")
    .on("postgres_changes", { event: "*", schema: "public" }, kick)
    .subscribe(status => { if (onStatus) onStatus(status); if (status === "SUBSCRIBED") kick(); });
  // Phones pause websites in the background; refresh as soon as the screen is back.
  document.addEventListener("visibilitychange", () => { if (!document.hidden) kick(); });
  window.addEventListener("online", kick);
  // Safety net: refresh every 30 seconds even if live updates drop.
  setInterval(kick, 30000);
  return channel;
}

function setLiveDot(status) {
  const el = document.getElementById("live");
  if (!el) return;
  const ok = status === "SUBSCRIBED";
  el.className = "live " + (ok ? "on" : "off");
  el.textContent = ok ? "Live" : "Reconnecting…";
}

let toastTimer = null;
function toast(message, ok = true) {
  let el = document.getElementById("toast");
  if (!el) { el = document.createElement("div"); el.id = "toast"; el.setAttribute("role", "status"); document.body.appendChild(el); }
  el.textContent = message;
  el.className = "toast show " + (ok ? "ok" : "bad");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { el.className = "toast"; }, ok ? 3500 : 6000);
}

function showNotConfigured() {
  document.body.innerHTML = `<main class="wrap"><div class="card"><h1>Almost there</h1>
    <p>This website is not connected to the database yet.</p>
    <p>Open <b>js/config.js</b> in GitHub and paste your Supabase Project URL and key (see step 4 of the setup guide).</p></div></main>`;
}
