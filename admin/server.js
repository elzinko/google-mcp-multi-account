#!/usr/bin/env node
// Interface d'admin gws multi-comptes — serveur local (127.0.0.1 uniquement).
// Zéro dépendance : Node stdlib. Toute action passe par bin/gwsa (source de vérité).
// Sécurité : bind loopback, en-tête X-GWSA-Admin obligatoire sur /api (anti-CSRF,
// un site tiers ne peut pas l'envoyer sans déclencher un préflight CORS refusé),
// contrôle d'Origin, execFile sans shell, validation stricte des entrées.
"use strict";
const http = require("http");
const net = require("net");
const fs = require("fs");
const path = require("path");
const os = require("os");
const { execFile, execFileSync, spawn } = require("child_process");

const PORT = Number.parseInt(process.env.GWSA_ADMIN_PORT || "4877", 10);
const HOST = "127.0.0.1";
const REPO = path.resolve(__dirname, "..");
const GWSA = path.join(REPO, "bin", "gwsa");
const ROOT = process.env.GWSA_ROOT || path.join(os.homedir(), ".config", "gws-accounts");
const DEPLOY_ROOT = process.env.GWSA_DEPLOY_ROOT || path.join(os.homedir(), ".local", "share", "google-mcp");
const STABLE_ADMIN_PORT = 4877;
const STABLE_BROKER_PORT = 4878;

function readJson(file) {
  try { return JSON.parse(fs.readFileSync(file, "utf8")); } catch { return null; }
}

function readText(file) {
  try { return fs.readFileSync(file, "utf8").trim(); } catch { return ""; }
}

function sandboxManifest(dir) {
  return readJson(path.join(dir, ".sandbox.json"))
    || readJson(path.join(dir, ".couloir.json"));
}

function gitField(repo, args) {
  try {
    return execFileSync("git", ["-C", repo, ...args], {
      encoding: "utf8", timeout: 2000, stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch { return ""; }
}

function gitIdentity(repo) {
  const branch = gitField(repo, ["rev-parse", "--abbrev-ref", "HEAD"]) || "";
  const sha = gitField(repo, ["rev-parse", "--short", "HEAD"]) || "";
  let dirty = false;
  try {
    dirty = !!gitField(repo, ["status", "--porcelain"]);
  } catch {}
  return { branch: branch || null, sha: sha || null, dirty };
}

function serverVersion() {
  const fromFile = readText(path.join(REPO, "VERSION"));
  if (fromFile) return fromFile;
  const mf = sandboxManifest(REPO);
  if (mf && mf.version) return String(mf.version);
  const g = gitIdentity(REPO);
  if (g.branch && g.sha) {
    return g.branch + "@" + g.sha + (g.dirty ? " (dirty)" : " (dev)");
  }
  return "dev";
}

function portListening(port) {
  return new Promise((resolve) => {
    const s = net.connect({ host: HOST, port: Number(port) }, () => {
      s.destroy();
      resolve(true);
    });
    s.on("error", () => resolve(false));
    s.setTimeout(250, () => { s.destroy(); resolve(false); });
  });
}

function mcpConfigPaths() {
  const home = os.homedir();
  if (process.env.GWSA_DESKTOP_CONFIG || process.env.GWSA_CURSOR_CONFIG) {
    return [
      process.env.GWSA_DESKTOP_CONFIG,
      process.env.GWSA_CURSOR_CONFIG,
    ].filter(Boolean);
  }
  if (process.platform === "darwin") {
    return [
      path.join(home, "Library", "Application Support", "Claude", "claude_desktop_config.json"),
      path.join(home, ".cursor", "mcp.json"),
    ];
  }
  return [
    path.join(process.env.XDG_CONFIG_HOME || path.join(home, ".config"), "Claude", "claude_desktop_config.json"),
    path.join(home, ".cursor", "mcp.json"),
  ];
}

/** Entrée stable à protéger (MCP « courant » branché sur current / 4878). */
const PROTECTED_MCP_NAMES = new Set(["google-multi-account"]);

function isProtectedMcpClient(entry) {
  if (!entry) return false;
  if (PROTECTED_MCP_NAMES.has(entry.name)) return true;
  const bin = String(entry.binary || "");
  return bin.includes("/google-mcp/current/bin/google-mcp")
    || (Number(entry.broker_port) === STABLE_BROKER_PORT && entry.name === "google-multi-account");
}

/**
 * Retire une entrée mcpServers google-mcp d'un fichier Claude/Cursor.
 * Refuse les configs hors liste autorisée et l'entrée stable (sauf force).
 */
function removeMcpClientEntry(name, configPath, { force = false } = {}) {
  const allowed = new Set(mcpConfigPaths().map((p) => path.resolve(p)));
  const cfg = path.resolve(String(configPath || ""));
  if (!allowed.has(cfg)) {
    return { ok: false, error: "fichier de config non autorisé" };
  }
  if (!name || typeof name !== "string" || name.length > 200) {
    return { ok: false, error: "nom d'entrée invalide" };
  }
  const data = readJson(cfg);
  if (!data || typeof data !== "object") {
    return { ok: false, error: "config introuvable ou JSON invalide" };
  }
  const servers = data.mcpServers;
  if (!servers || typeof servers !== "object" || Array.isArray(servers)) {
    return { ok: false, error: "mcpServers absent" };
  }
  const srv = servers[name];
  if (!srv || typeof srv !== "object") {
    return { ok: false, error: "entrée introuvable : " + name };
  }
  const cmd = String(srv.command || "");
  if (path.basename(cmd) !== "google-mcp") {
    return { ok: false, error: "seules les entrées google-mcp peuvent être retirées ici" };
  }
  const entry = {
    name,
    binary: cmd,
    broker_port: Number.parseInt((srv.env || {}).GWSA_BROKER_PORT || "4878", 10),
  };
  if (isProtectedMcpClient(entry) && !force) {
    return {
      ok: false,
      error: "entrée protégée (MCP stable) — utilise force=true pour outrepasser, ou édite le JSON à la main",
      protected: true,
    };
  }
  delete servers[name];
  fs.writeFileSync(cfg, JSON.stringify(data, null, 2) + "\n", { mode: 0o600 });
  return { ok: true, removed: name, config: cfg };
}

function scanMcpClients() {
  const out = [];
  for (const cfg of mcpConfigPaths()) {
    const data = readJson(cfg);
    if (!data || typeof data !== "object") continue;
    const servers = data.mcpServers || {};
    for (const [name, srv] of Object.entries(servers)) {
      if (!srv || typeof srv !== "object") continue;
      const cmd = String(srv.command || "");
      if (path.basename(cmd) !== "google-mcp") continue;
      const env = srv.env || {};
      const brokerPort = Number.parseInt(env.GWSA_BROKER_PORT || "4878", 10);
      const rootGuess = cmd.endsWith("/bin/google-mcp")
        ? cmd.slice(0, -"/bin/google-mcp".length) : "";
      const entry = {
        name,
        config: cfg,
        binary: cmd,
        broker_port: brokerPort,
        version: rootGuess ? (readText(path.join(rootGuess, "VERSION")) || null) : null,
        deploy_id: rootGuess ? path.basename(rootGuess) : null,
      };
      entry.protected = isProtectedMcpClient(entry);
      out.push(entry);
    }
  }
  return out;
}

function detectDraftPr(branch) {
  const envPr = process.env.GWSA_DRAFT_PR || process.env.GWSA_PR;
  if (envPr && /^\d+$/.test(envPr)) return Number(envPr);
  if (!branch || branch === "HEAD" || branch === "main" || branch === "master") return null;
  try {
    const out = execFileSync("gh", [
      "pr", "list", "--head", branch, "--state", "open", "--json", "number,isDraft", "--limit", "1",
    ], { encoding: "utf8", timeout: 2500, stdio: ["ignore", "pipe", "ignore"] });
    const arr = JSON.parse(out);
    if (Array.isArray(arr) && arr[0] && arr[0].number) return arr[0].number;
  } catch {}
  return null;
}

function currentDeployId() {
  try {
    const cur = fs.readlinkSync(path.join(DEPLOY_ROOT, "current"));
    return path.basename(cur);
  } catch { return null; }
}

async function listDeployments() {
  const clients = scanMcpClients();
  const current = currentDeployId();
  let names = [];
  try {
    names = fs.readdirSync(DEPLOY_ROOT, { withFileTypes: true })
      .filter((e) => e.isDirectory() && e.name !== "current" && !e.name.startsWith(".tmp-"))
      .map((e) => e.name)
      .sort();
  } catch { return []; }

  const out = [];
  for (const name of names) {
    const dir = path.join(DEPLOY_ROOT, name);
    const mf = sandboxManifest(dir);
    const isSandbox = !!mf;
    const isCurrent = name === current;
    const brokerPort = isSandbox
      ? Number(mf.broker_port)
      : (isCurrent ? STABLE_BROKER_PORT : null);
    const adminPort = isSandbox
      ? Number(mf.admin_port)
      : (isCurrent ? STABLE_ADMIN_PORT : null);
    const brokerUp = brokerPort != null ? await portListening(brokerPort) : false;
    const adminUp = adminPort != null ? await portListening(adminPort) : false;
    const mcp = clients.filter((c) =>
      c.deploy_id === name
      || (brokerPort != null && c.broker_port === brokerPort && (isCurrent || isSandbox)));
    out.push({
      id: name,
      path: dir,
      version: readText(path.join(dir, "VERSION")) || (mf && mf.version) || null,
      kind: isSandbox ? "sandbox" : (isCurrent ? "stable-current" : "stable-archive"),
      is_current: isCurrent,
      is_sandbox: isSandbox,
      branch: mf && mf.branch || null,
      sha: mf && mf.sha || null,
      broker_port: brokerPort,
      admin_port: adminPort,
      broker_up: brokerUp,
      admin_up: adminUp,
      admin_url: adminPort != null ? `http://${HOST}:${adminPort}` : null,
      mcp_clients: mcp.map((c) => ({ name: c.name, config: c.config, broker_port: c.broker_port })),
      source_repo: mf && mf.source_repo || readText(path.join(dir, ".source")) || null,
    });
  }
  return out;
}

async function buildMeta() {
  const mf = sandboxManifest(REPO);
  const git = gitIdentity(REPO);
  const version = serverVersion();
  const brokerPort = mf && mf.broker_port != null
    ? Number(mf.broker_port)
    : Number.parseInt(process.env.GWSA_BROKER_PORT || String(STABLE_BROKER_PORT), 10);
  const sandboxId = (mf && mf.id) || null;
  const kind = sandboxId
    ? "sandbox"
    : (PORT === STABLE_ADMIN_PORT ? "worktree-or-stable" : "custom-port");
  const branch = (mf && mf.branch) || git.branch;
  const sha = (mf && mf.sha) || git.sha;
  const draftPr = detectDraftPr(branch);
  const lookingAtStablePort = PORT === STABLE_ADMIN_PORT;
  let corridorHint = null;
  if (sandboxId) {
    corridorHint = `sandbox ${sandboxId} (admin ${PORT})`;
  } else if (lookingAtStablePort) {
    corridorHint = `port ${STABLE_ADMIN_PORT} — admin du couloir stable / worktree (pas une sandbox dédiée)`;
  } else {
    corridorHint = `admin personnalisé sur le port ${PORT}`;
  }
  return {
    version,
    git_branch: branch,
    git_sha: sha,
    git_dirty: !!(mf && mf.dirty) || git.dirty,
    repo: REPO,
    worktree: REPO,
    gwsa_root: ROOT,
    deploy_root: DEPLOY_ROOT,
    sandbox_id: sandboxId,
    sandbox: mf || null,
    kind,
    broker_port: brokerPort,
    admin_port: PORT,
    stable_admin_port: STABLE_ADMIN_PORT,
    stable_broker_port: STABLE_BROKER_PORT,
    looking_at_stable_admin: lookingAtStablePort && !sandboxId,
    corridor_hint: corridorHint,
    draft_pr: draftPr,
    admin_url: `http://${HOST}:${PORT}`,
  };
}

const ALIAS_RE = /^[A-Za-z0-9][A-Za-z0-9_-]{0,31}$/;
const SESSION_ID_RE = /^[a-f0-9]{16,64}$/;
const EMAIL_RE = /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/;
const SERVICES = ["drive", "gmail", "calendar", "keep", "docs", "sheets", "tasks"];
const BOOL_KEYS = ["read", "create", "update", "delete", "send", "drafts", "labels", "share", "settings"];

const emailCache = new Map();

// Doc « Schémas » : assemblée depuis diagrams/*/ (triplets versionnés) — les
// sources restent les .mmd/explanation.md du repo, rien n'est dupliqué ici.
function buildSchemas() {
  const dir = path.join(REPO, "diagrams");
  const rdf = (f) => { try { return fs.readFileSync(f, "utf8"); } catch { return ""; } };
  let slugs = [];
  try {
    slugs = fs.readdirSync(dir, { withFileTypes: true })
      .filter((e) => e.isDirectory() && fs.existsSync(path.join(dir, e.name, "diagram.mmd")))
      .map((e) => e.name);
  } catch { return ""; }
  const PREF = ["onboarding-setup-initial", "lecture-donnees-elicitee",
    "onboarding-add-account-elicite", "onboarding-reparation-iam"];
  slugs.sort((a, b) => {
    const ia = PREF.indexOf(a); const ib = PREF.indexOf(b);
    return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib) || a.localeCompare(b);
  });
  const parts = ["# Les scénarios clés, en séquence",
    "> Schémas versionnés dans `diagrams/` (prose → mermaid → image) — rendus ici en local, sans service externe."];
  for (const s of slugs) {
    const m = rdf(path.join(dir, s, "meta.yaml")).match(/^title:\s*"?(.*?)"?\s*$/m);
    parts.push("## " + ((m && m[1]) || s));
    const expl = rdf(path.join(dir, s, "explanation.md")).trim();
    if (expl) parts.push(expl);
    const mmd = rdf(path.join(dir, s, "diagram.mmd")).trim();
    if (mmd) parts.push("```mermaid\n" + mmd + "\n```");
  }
  return slugs.length ? parts.join("\n\n") : "";
}

// Timeout court pour les commandes snappy (list/lock/…). Unlock/grant/add
// attendent Touch ID : 20 s tuait le child au milieu du dialogue → connexion
// HTTP coupée côté navigateur (« Failed to fetch ») si le process admin
// mourait/redémarrait dans la foulée, ou réponse 500 opaque sinon.
const GWSA_TIMEOUT_SHORT_MS = 20000;
const GWSA_TIMEOUT_AUTH_MS = 120000;

function gwsaExitCode(err) {
  if (!err) return 0;
  if (err.killed || err.code === "ETIMEDOUT") return 124;
  if (typeof err.code === "number") return err.code;
  if (err.code === undefined || err.code === null) return 1;
  return 1;
}

function gwsa(args, timeout = GWSA_TIMEOUT_SHORT_MS) {
  return new Promise((resolve) => {
    execFile(GWSA, args, { timeout, killSignal: "SIGTERM" }, (err, stdout, stderr) => {
      const timedOut = !!(err && (err.killed || err.code === "ETIMEDOUT"));
      resolve({
        code: gwsaExitCode(err),
        timedOut,
        stdout: String(stdout || ""),
        stderr: String(stderr || ""),
      });
    });
  });
}

function holdHttpForAuth(req, res) {
  // Empêche Node de couper la socket pendant l'attente Touch ID (humain).
  try { req.setTimeout(0); } catch {}
  try { res.setTimeout(0); } catch {}
}

function authGwsaResult(r) {
  if (r.timedOut) {
    return {
      status: 504,
      body: {
        ok: false,
        error: "délai dépassé — Touch ID non validé à temps (réessaie)",
        out: (r.stdout + r.stderr).trim(),
      },
    };
  }
  const out = (r.stdout + r.stderr).trim();
  if (r.code) {
    return {
      status: 500,
      body: { ok: false, error: out.slice(0, 300) || "action refusée", out },
    };
  }
  return { status: 200, body: { ok: true, out } };
}

// provision-gcp.sh — état du setup (status --json) et réparation IAM (sync-iam).
// Mutation IAM exécutée PAR l'humain qui clique dans l'admin local (pas le LLM) :
// même légitimité que les boutons unlock/grant, + Touch ID si strongauth (le
// script l'exige). Timeout large : le sync-iam attend Touch ID puis gcloud.
const PROVISION = path.join(REPO, "scripts", "provision-gcp.sh");
function provision(args, timeout = 20000) {
  return new Promise((resolve) => {
    execFile(PROVISION, args, { timeout }, (err, stdout, stderr) =>
      resolve({ code: err ? (err.code === undefined ? 1 : err.code) : 0, stdout: String(stdout), stderr: String(stderr) }));
  });
}

// Appels Drive en LECTURE SEULE pour le sélecteur de dossiers de l'admin.
// Passent par gws directement (panneau de l'utilisateur : le verrou 🔒, qui
// cible les LLM via gwsa, ne s'applique pas ici).
function gwsDrive(alias, params) {
  return new Promise((resolve) => {
    execFile("gws", ["drive", "files", "list", "--params", JSON.stringify(params)], {
      timeout: 15000,
      env: { ...process.env, GOOGLE_WORKSPACE_CLI_CONFIG_DIR: path.join(ROOT, alias) },
    }, (err, stdout) => {
      try { resolve(JSON.parse(String(stdout)).files || []); } catch { resolve([]); }
    });
  });
}

const folderMeta = new Map(); // id → {name, parents} (cache chemin, durée de vie du serveur)
function folderInfo(alias, id) {
  if (folderMeta.has(id)) return Promise.resolve(folderMeta.get(id));
  return new Promise((resolve) => {
    execFile("gws", ["drive", "files", "get", "--params", JSON.stringify({ fileId: id, fields: "id,name,parents" })], {
      timeout: 10000,
      env: { ...process.env, GOOGLE_WORKSPACE_CLI_CONFIG_DIR: path.join(ROOT, alias) },
    }, (err, stdout) => {
      let info = null;
      try { const j = JSON.parse(String(stdout)); info = { name: j.name, parents: j.parents || [] }; } catch {}
      if (info) folderMeta.set(id, info);
      resolve(info);
    });
  });
}

async function folderPath(alias, id, depth = 0) {
  if (depth > 12) return "…";
  const info = await folderInfo(alias, id);
  if (!info) return "?";
  if (!info.parents.length) return info.name;
  const parent = await folderPath(alias, info.parents[0], depth + 1);
  return parent + " / " + info.name;
}

async function folderAncestors(alias, id) {
  const chain = [];
  let cur = id;
  for (let d = 0; d < 16; d++) {
    const info = await folderInfo(alias, cur);
    if (!info) break;
    chain.unshift({ id: cur, name: info.name });
    if (!info.parents.length) break;
    const parent = info.parents[0];
    if (!parent || parent === cur) break;
    cur = parent;
  }
  return chain;
}

function gwsEmail(alias) {
  if (emailCache.has(alias)) return Promise.resolve(emailCache.get(alias));
  // Métadonnée .email écrite par gwsa add/list (ADR-0002) — évite d'exécuter gws.
  // Non autoritative si corrompue : un contenu non-email retombe sur le backfill
  // (sinon un mauvais .email resterait coincé — retour Codex, PR #18).
  try {
    const meta = fs.readFileSync(path.join(ROOT, alias, ".email"), "utf8").trim().split("\n")[0];
    if (/^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/.test(meta)) {
      emailCache.set(alias, meta);
      return Promise.resolve(meta);
    }
  } catch {}
  return new Promise((resolve) => {
    execFile("gws", ["auth", "status"], {
      timeout: 10000,
      env: { ...process.env, GOOGLE_WORKSPACE_CLI_CONFIG_DIR: path.join(ROOT, alias) },
    }, (err, stdout) => {
      const m = String(stdout).match(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/);
      const email = m ? m[0] : "";
      if (email) {
        emailCache.set(alias, email);
        try { fs.writeFileSync(path.join(ROOT, alias, ".email"), email + "\n"); } catch {}
      }
      resolve(email);
    });
  });
}

async function listProfiles() {
  let entries = [];
  try { entries = fs.readdirSync(ROOT, { withFileTypes: true }); } catch { return []; }
  const out = [];
  for (const e of entries) {
    if (!e.isDirectory()) continue;
    const alias = e.name;
    if (!ALIAS_RE.test(alias)) continue;
    const dir = path.join(ROOT, alias);
    const connected = fs.existsSync(path.join(dir, "credentials.enc"))
      || fs.existsSync(path.join(ROOT, ".vault", alias, "credentials.enc"));
    const hasLock = fs.existsSync(path.join(dir, ".locked"));
    let unlockedForMin = 0;
    // unlockedUntil : échéance du déverrouillage en epoch SECONDES (0 = verrouillé
    // ou pas de fenêtre). Le front en fait un décompte réel (fiche 0036) ; on ne
    // pré-formate pas en minutes côté serveur pour que le compte à rebours vive.
    let unlockedUntil = 0;
    if (hasLock) {
      try { unlockedUntil = parseInt(fs.readFileSync(path.join(dir, ".unlock-until"), "utf8"), 10) || 0; } catch {}
      unlockedForMin = Math.max(0, Math.floor((unlockedUntil - Date.now() / 1000) / 60));
    }
    let policy = null;
    try { policy = JSON.parse(fs.readFileSync(path.join(dir, "policy.json"), "utf8")); } catch {}
    let grants = [];
    try {
      const g = JSON.parse(fs.readFileSync(path.join(dir, "session-grants.json"), "utf8"));
      const now = Date.now() / 1000;
      grants = (g.drive || []).filter((e) => e.expiresAt > now)
        .map((e) => ({ id: e.id, name: e.name, minutesLeft: Math.floor((e.expiresAt - now) / 60) }));
    } catch {}
    const email = connected ? await gwsEmail(alias) : "";
    out.push({ alias, connected, email, locked: hasLock, unlockedForMin, unlockedUntil, policy, grants });
  }
  return out.sort((a, b) => a.alias.localeCompare(b.alias));
}

/** Sessions LLM (registre `.sessions/`, fiche 0040) — lecture directe, mutations via gwsa. */
function listSessions() {
  const dir = path.join(ROOT, ".sessions");
  let files = [];
  try { files = fs.readdirSync(dir).filter((f) => f.endsWith(".json")); } catch { return []; }
  const now = Date.now() / 1000;
  const raw = [];
  for (const f of files) {
    const data = readJson(path.join(dir, f));
    if (!data || typeof data !== "object") continue;
    const sid = String(data.session_id || "");
    if (!SESSION_ID_RE.test(sid)) continue;
    raw.push(data);
  }
  const childCount = {};
  for (const data of raw) {
    const pid = String(data.parent_id || "");
    if (pid) childCount[pid] = (childCount[pid] || 0) + 1;
  }
  const out = raw.map((data) => {
    const unlocks = {};
    for (const [alias, until] of Object.entries(data.unlocks || {})) {
      const u = Number(until) || 0;
      if (u > now) unlocks[alias] = { until: u, minutes_left: Math.max(0, Math.floor((u - now) / 60)) };
    }
    const drive_zones = {};
    for (const [alias, zones] of Object.entries(data.drive_zones || {})) {
      if (!Array.isArray(zones)) continue;
      const active = zones.filter((z) => z && Number(z.expires_at || z.expiresAt || 0) > now)
        .map((z) => {
          const exp = Number(z.expires_at || z.expiresAt || 0);
          return {
            id: String(z.id || ""),
            name: String(z.name || ""),
            expires_at: exp,
            minutes_left: Math.max(0, Math.floor((exp - now) / 60)),
          };
        });
      if (active.length) drive_zones[alias] = active;
    }
    const sid = String(data.session_id || "");
    return {
      session_id: sid,
      parent_id: data.parent_id || null,
      client: String(data.client || "mcp"),
      delegated: !!data.delegated,
      created_at: Number(data.created_at) || 0,
      last_seen_at: Number(data.last_seen_at) || 0,
      unlocks,
      drive_zones,
      child_count: childCount[sid] || 0,
    };
  });
  out.sort((a, b) => (b.last_seen_at || 0) - (a.last_seen_at || 0));
  return out;
}

function validPolicy(p) {
  if (p === null) return true;
  if (typeof p !== "object" || Array.isArray(p)) return false;
  for (const [svc, rules] of Object.entries(p)) {
    if (!SERVICES.includes(svc)) return false;
    if (typeof rules !== "object" || Array.isArray(rules)) return false;
    for (const [k, v] of Object.entries(rules)) {
      if (svc === "drive" && k === "mode") {
        if (!["open", "readonly", "restricted"].includes(v)) return false;
      } else if (svc === "drive" && k === "writeFolders") {
        if (!Array.isArray(v) || !v.every((x) => /^[A-Za-z0-9_-]{5,128}$/.test(x))) return false;
      } else if (svc === "drive" && k === "writeFolderNames") {
        if (typeof v !== "object" || Array.isArray(v)) return false;
        for (const [id, name] of Object.entries(v)) {
          if (!/^[A-Za-z0-9_-]{5,128}$/.test(id) || typeof name !== "string" || name.length > 300) return false;
        }
      } else if (svc === "drive" && k === "zonesOnly") {
        if (typeof v !== "boolean") return false;
      } else if (BOOL_KEYS.includes(k)) {
        if (typeof v !== "boolean") return false;
      } else return false;
    }
  }
  return true;
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = "";
    req.on("data", (c) => { data += c; if (data.length > 65536) { reject(new Error("trop gros")); req.destroy(); } });
    req.on("end", () => { try { resolve(data ? JSON.parse(data) : {}); } catch { reject(new Error("JSON invalide")); } });
  });
}

function send(res, code, obj, type) {
  const body = type ? obj : JSON.stringify(obj);
  res.writeHead(code, {
    "Content-Type": type || "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
  });
  res.end(body);
}

function tailFile(file, maxLines) {
  try {
    const lines = fs.readFileSync(file, "utf8").trim().split("\n");
    return lines.slice(-maxLines);
  } catch { return []; }
}

async function launchAdd(alias, email) {
  const logFile = path.join(ROOT, `.auth-${alias}.log`);
  try { fs.unlinkSync(logFile); } catch {}
  const out = fs.openSync(logFile, "a");
  const args = ["add", alias]; if (email) args.push(email);
  const child = spawn(GWSA, args, { detached: true, stdio: ["ignore", out, out] });
  child.unref();
  emailCache.delete(alias);
  try { fs.unlinkSync(path.join(ROOT, alias, ".email")); } catch {}
  for (let i = 0; i < 24; i++) {
    await new Promise((r) => setTimeout(r, 500));
    const txt = fs.existsSync(logFile) ? fs.readFileSync(logFile, "utf8") : "";
    const m = txt.match(/https:\/\/accounts\.google\.com[^\s"']+/);
    if (m) {
      let url = m[0];
      if (email) url += "&login_hint=" + encodeURIComponent(email);
      return { url };
    }
  }
  return { error: "URL OAuth non émise (voir " + logFile + ")" };
}

const server = http.createServer(async (req, res) => {
  const u = new URL(req.url, `http://${HOST}:${PORT}`);
  const p = u.pathname;

  if (p === "/" || p === "/index.html") {
    return send(res, 200, fs.readFileSync(path.join(__dirname, "index.html")), "text/html; charset=utf-8");
  }
  if (p.startsWith("/vendor/")) {
    const f = path.join(__dirname, "vendor", path.basename(p));
    if (!fs.existsSync(f)) return send(res, 404, { error: "introuvable" });
    return send(res, 200, fs.readFileSync(f), "application/javascript; charset=utf-8");
  }
  if (!p.startsWith("/api/")) return send(res, 404, { error: "introuvable" });

  // Anti-DNS-rebinding : n'accepter que l'hôte loopback sur lequel on écoute.
  // Une page attaquante rebindée garde SON header Host (ex. attacker.com:PORT),
  // donc ceci la rejette même quand l'Origin est omis sur un GET same-origin.
  const host = req.headers.host;
  if (host !== `127.0.0.1:${PORT}` && host !== `localhost:${PORT}`) {
    return send(res, 403, { error: "hôte refusé" });
  }

  const origin = req.headers.origin;
  if (origin && origin !== `http://${HOST}:${PORT}` && origin !== `http://localhost:${PORT}`) {
    return send(res, 403, { error: "origine refusée" });
  }
  if (req.headers["x-gwsa-admin"] !== "1") return send(res, 403, { error: "en-tête admin manquant" });

  try {
    if (req.method === "GET" && p === "/api/meta") {
      return send(res, 200, await buildMeta());
    }
    if (req.method === "GET" && p === "/api/dev") {
      const meta = await buildMeta();
      const deployments = await listDeployments();
      const sandboxes = deployments.filter((d) => d.is_sandbox);
      return send(res, 200, {
        ...meta,
        deployments,
        sandboxes,
        mcp_clients: scanMcpClients(),
        current_deploy: currentDeployId(),
      });
    }
    if (req.method === "POST" && p === "/api/dev/mcp-client/remove") {
      const b = await readBody(req);
      const r = removeMcpClientEntry(b.name, b.config, { force: !!b.force });
      return send(res, r.ok ? 200 : (r.protected ? 403 : 400), r);
    }
    if (req.method === "POST" && p === "/api/dev/sandbox/remove") {
      const b = await readBody(req);
      const id = String(b.id || "").trim();
      if (!/^[A-Za-z0-9._-]{1,120}$/.test(id) || id === "current") {
        return send(res, 400, { error: "id sandbox invalide" });
      }
      const r = await gwsa(["sandbox", "remove", id], 60000);
      return send(res, r.code ? 500 : 200, {
        ok: !r.code,
        out: (r.stdout + r.stderr).trim(),
      });
    }
    if (req.method === "GET" && p === "/api/profiles") {
      return send(res, 200, { profiles: await listProfiles() });
    }
    if (req.method === "GET" && p === "/api/sessions") {
      return send(res, 200, { sessions: listSessions() });
    }
    const sm = p.match(/^\/api\/sessions\/([^/]+)\/(unlock|grant|revoke-descendants|close)$/);
    if (req.method === "POST" && sm) {
      const [, sid, action] = sm;
      if (!SESSION_ID_RE.test(sid)) return send(res, 400, { error: "session_id invalide" });
      const sessFile = path.join(ROOT, ".sessions", sid + ".json");
      if (!fs.existsSync(sessFile) && action !== "close") {
        return send(res, 404, { error: "session inconnue" });
      }
      if (action === "unlock") {
        const b = await readBody(req);
        if (!ALIAS_RE.test(b.alias || "")) return send(res, 400, { error: "alias invalide" });
        const mins = String(Math.min(1440, Math.max(1, parseInt(b.minutes, 10) || 60)));
        const r = await gwsa(["session", "unlock", sid, b.alias, mins], 90000);
        return send(res, r.code ? 500 : 200, { ok: !r.code, out: (r.stdout + r.stderr).trim() });
      }
      if (action === "grant") {
        const b = await readBody(req);
        if (!ALIAS_RE.test(b.alias || "")) return send(res, 400, { error: "alias invalide" });
        const target = String(b.target || "").trim().replace(/[\x00-\x1f"'\\]/g, "");
        if (!target || target.length > 200) return send(res, 400, { error: "dossier invalide" });
        const h = Math.min(168, Math.max(1, parseInt(b.hours, 10) || 8));
        const r = await gwsa(["session", "grant", sid, b.alias, target, String(h)], 90000);
        return send(res, r.code ? 500 : 200, { ok: !r.code, out: (r.stdout + r.stderr).trim() });
      }
      if (action === "revoke-descendants") {
        const r = await gwsa(["session", "revoke-descendants", sid]);
        return send(res, r.code ? 500 : 200, { ok: !r.code, out: (r.stdout + r.stderr).trim() });
      }
      if (action === "close") {
        const r = await gwsa(["session", "close", sid]);
        return send(res, r.code ? 500 : 200, { ok: !r.code, out: (r.stdout + r.stderr).trim() });
      }
    }
    if (req.method === "GET" && p === "/api/log") {
      const lines = tailFile(path.join(ROOT, "usage.jsonl"), 300)
        .map((l) => { try { return JSON.parse(l); } catch { return null; } })
        .filter(Boolean).reverse();
      return send(res, 200, { entries: lines });
    }
    if (req.method === "GET" && p === "/api/setup") {
      const r = await provision(["status", "--json"], 30000);
      try {
        return send(res, 200, { ok: true, setup: JSON.parse(r.stdout) });
      } catch {
        return send(res, 200, { ok: false, error: "status --json indisponible (gcloud non connecté ?)", out: (r.stderr || r.stdout).slice(0, 500) });
      }
    }
    if (req.method === "POST" && p === "/api/sync-iam") {
      // Réparation IAM : accorde le rôle aux comptes manquants (idempotent).
      // Touch ID via le script si strongauth. Timeout large (attente humaine + gcloud).
      holdHttpForAuth(req, res);
      const r = await provision(["sync-iam", "--yes"], GWSA_TIMEOUT_AUTH_MS);
      return send(res, r.code ? 500 : 200, { ok: !r.code, out: (r.stdout + r.stderr).slice(-1500) });
    }
    if (req.method === "GET" && p === "/api/doc") {
      const rd = (f) => { try { return fs.readFileSync(path.join(REPO, f), "utf8"); } catch { return ""; } };
      return send(res, 200, {
        readme: rd("README.md"),
        oauth: rd("docs/setup-oauth.md"),
        mcp: rd("docs/mcp-setup.md"),
        schemas: buildSchemas(),
      });
    }
    const anc = p.match(/^\/api\/profiles\/([^/]+)\/ancestors$/);
    if (req.method === "GET" && anc) {
      const alias = anc[1];
      if (!ALIAS_RE.test(alias)) return send(res, 400, { error: "alias invalide" });
      const id = String(u.searchParams.get("id") || "").replace(/[^A-Za-z0-9_-]/g, "");
      if (!id) return send(res, 400, { error: "id requis" });
      const ancestors = await folderAncestors(alias, id);
      return send(res, 200, { ancestors });
    }
    const gm = p.match(/^\/api\/profiles\/([^/]+)\/(browse|search)$/);
    if (req.method === "GET" && gm) {
      const [, alias, what] = gm;
      if (!ALIAS_RE.test(alias)) return send(res, 400, { error: "alias invalide" });
      if (what === "browse") {
        const parent = (u.searchParams.get("parent") || "root").replace(/[^A-Za-z0-9_-]/g, "") || "root";
        const folders = await gwsDrive(alias, {
          q: `'${parent}' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false`,
          fields: "files(id,name)", orderBy: "name", pageSize: 60,
        });
        return send(res, 200, { folders });
      }
      const qtext = String(u.searchParams.get("q") || "").replace(/[\x00-\x1f\\']/g, "").slice(0, 100);
      if (!qtext) return send(res, 400, { error: "q requis" });
      const hits = await gwsDrive(alias, {
        q: `name contains '${qtext}' and mimeType='application/vnd.google-apps.folder' and trashed=false`,
        fields: "files(id,name)", pageSize: 8,
      });
      const results = [];
      for (const h of hits) {
        results.push({ id: h.id, name: h.name, path: await folderPath(alias, h.id) });
      }
      return send(res, 200, { results });
    }

    if (req.method === "GET" && p.startsWith("/api/authlog/")) {
      const alias = p.split("/")[3] || "";
      if (!ALIAS_RE.test(alias)) return send(res, 400, { error: "alias invalide" });
      return send(res, 200, { lines: tailFile(path.join(ROOT, `.auth-${alias}.log`), 10) });
    }

    if (req.method === "POST" && p === "/api/add") {
      const b = await readBody(req);
      if (!ALIAS_RE.test(b.alias || "")) return send(res, 400, { error: "alias invalide" });
      if (b.email && !EMAIL_RE.test(b.email)) return send(res, 400, { error: "email invalide" });
      return send(res, 200, await launchAdd(b.alias, b.email || ""));
    }
    if (req.method === "POST" && p === "/api/lockall") {
      const profiles = await listProfiles();
      for (const pr of profiles) await gwsa(["lock", pr.alias]);
      return send(res, 200, { ok: true });
    }

    const m = p.match(/^\/api\/profiles\/([^/]+)\/(lock|unlock|revoke|policy|drive-folder|drive-folder-remove|grant|grant-revoke)$/);
    if (req.method === "POST" && m) {
      const [, alias, action] = m;
      if (!ALIAS_RE.test(alias)) return send(res, 400, { error: "alias invalide" });
      if (!fs.existsSync(path.join(ROOT, alias))) return send(res, 404, { error: "profil inconnu" });
      if (action === "lock") {
        const r = await gwsa(["lock", alias]);
        return send(res, r.code ? 500 : 200, { ok: !r.code, out: r.stdout + r.stderr });
      }
      if (action === "unlock") {
        holdHttpForAuth(req, res);
        const b = await readBody(req);
        const arg = b.minutes === "off" ? "off"
          : String(Math.min(1440, Math.max(1, parseInt(b.minutes, 10) || 60)));
        const r = await gwsa(["unlock", alias, arg], GWSA_TIMEOUT_AUTH_MS);
        const packed = authGwsaResult(r);
        return send(res, packed.status, packed.body);
      }
      if (action === "revoke") {
        const r = await gwsa(["remove", alias]);
        emailCache.delete(alias);
        return send(res, r.code ? 500 : 200, { ok: !r.code, out: r.stdout + r.stderr });
      }
      if (action === "drive-folder" || action === "grant") {
        const b = await readBody(req);
        const target = String(b.target || "").trim().replace(/[\x00-\x1f"'\\]/g, "");
        if (!target || target.length > 200) return send(res, 400, { error: "dossier invalide" });
        let args;
        let timeout = GWSA_TIMEOUT_SHORT_MS;
        if (action === "grant") {
          holdHttpForAuth(req, res);
          const h = Math.min(168, Math.max(1, parseInt(b.hours, 10) || 8));
          args = ["grant", alias, target, String(h)];
          timeout = GWSA_TIMEOUT_AUTH_MS;
        } else {
          args = ["policy", alias, "allow", target];
        }
        const r = await gwsa(args, timeout);
        if (action === "grant") {
          const packed = authGwsaResult(r);
          return send(res, packed.status, packed.body);
        }
        return send(res, r.code ? 500 : 200, { ok: !r.code, out: (r.stdout + r.stderr).trim() });
      }
      if (action === "drive-folder-remove" || action === "grant-revoke") {
        const b = await readBody(req);
        const id = String(b.id || "");
        if (!/^[A-Za-z0-9_-]{5,128}$/.test(id)) return send(res, 400, { error: "id invalide" });
        const args = action === "grant-revoke" ? ["grant", alias, "revoke", id] : ["policy", alias, "revoke", id];
        const r = await gwsa(args);
        return send(res, r.code ? 500 : 200, { ok: !r.code, out: (r.stdout + r.stderr).trim() });
      }
      if (action === "policy") {
        const b = await readBody(req);
        if (!validPolicy(b.policy === undefined ? false : b.policy)) {
          return send(res, 400, { error: "policy invalide" });
        }
        const file = path.join(ROOT, alias, "policy.json");
        if (b.policy === null || Object.keys(b.policy).length === 0) {
          try { fs.unlinkSync(file); } catch {}
          return send(res, 200, { ok: true, removed: true });
        }
        const tmp = file + ".tmp";
        fs.writeFileSync(tmp, JSON.stringify(b.policy, null, 2));
        fs.renameSync(tmp, file);
        return send(res, 200, { ok: true });
      }
    }
    return send(res, 404, { error: "route inconnue" });
  } catch (e) {
    return send(res, 500, { error: String(e.message || e) });
  }
});

server.on("error", (err) => {
  // Sans handler, un EADDRINUSE (course au démarrage) plantait en « Unhandled
  // 'error' event » — pidfile orphelin, UI « Failed to fetch ».
  console.error(`admin listen error: ${err && err.code ? err.code : err}`);
  process.exit(1);
});
server.requestTimeout = Math.max(server.requestTimeout || 0, GWSA_TIMEOUT_AUTH_MS + 30000);
server.headersTimeout = Math.max(server.headersTimeout || 0, GWSA_TIMEOUT_AUTH_MS + 60000);
server.listen(PORT, HOST, () => {
  console.log(`Admin gws multi-comptes : http://${HOST}:${PORT} (local uniquement)`);
});
