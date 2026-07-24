#!/usr/bin/env node
// Interface d'admin gws multi-comptes — serveur local (127.0.0.1 uniquement).
// Zéro dépendance : Node stdlib. Toute action passe par bin/gwsa (source de vérité).
// Sécurité : bind loopback, en-tête X-GWSA-Admin obligatoire sur /api (anti-CSRF,
// un site tiers ne peut pas l'envoyer sans déclencher un préflight CORS refusé),
// contrôle d'Origin, execFile sans shell, validation stricte des entrées.
"use strict";
const http = require("http");
const fs = require("fs");
const path = require("path");
const os = require("os");
const { execFile, spawn } = require("child_process");

const PORT = 4877;
const HOST = "127.0.0.1";
const REPO = path.resolve(__dirname, "..");
const GWSA = path.join(REPO, "bin", "gwsa");
const ROOT = process.env.GWSA_ROOT || path.join(os.homedir(), ".config", "gws-accounts");

const ALIAS_RE = /^[A-Za-z0-9][A-Za-z0-9_-]{0,31}$/;
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

function gwsa(args) {
  return new Promise((resolve) => {
    execFile(GWSA, args, { timeout: 20000 }, (err, stdout, stderr) =>
      resolve({ code: err ? (err.code === undefined ? 1 : err.code) : 0, stdout: String(stdout), stderr: String(stderr) }));
  });
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

function gwsEmail(alias) {
  if (emailCache.has(alias)) return Promise.resolve(emailCache.get(alias));
  // Métadonnée .email écrite par gwsa add/list (ADR-0002) — évite d'exécuter gws.
  try {
    const meta = fs.readFileSync(path.join(ROOT, alias, ".email"), "utf8").trim().split("\n")[0];
    if (meta) { emailCache.set(alias, meta); return Promise.resolve(meta); }
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
    const connected = fs.existsSync(path.join(dir, "credentials.enc"));
    const hasLock = fs.existsSync(path.join(dir, ".locked"));
    let unlockedForMin = 0;
    if (hasLock) {
      let until = 0;
      try { until = parseInt(fs.readFileSync(path.join(dir, ".unlock-until"), "utf8"), 10) || 0; } catch {}
      unlockedForMin = Math.max(0, Math.floor((until - Date.now() / 1000) / 60));
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
    out.push({ alias, connected, email, locked: hasLock, unlockedForMin, policy, grants });
  }
  return out.sort((a, b) => a.alias.localeCompare(b.alias));
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

  const origin = req.headers.origin;
  if (origin && origin !== `http://${HOST}:${PORT}` && origin !== `http://localhost:${PORT}`) {
    return send(res, 403, { error: "origine refusée" });
  }
  if (req.headers["x-gwsa-admin"] !== "1") return send(res, 403, { error: "en-tête admin manquant" });

  try {
    if (req.method === "GET" && p === "/api/profiles") {
      return send(res, 200, { profiles: await listProfiles() });
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
      const r = await provision(["sync-iam", "--yes"], 120000);
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
        const b = await readBody(req);
        const arg = b.minutes === "off" ? "off"
          : String(Math.min(1440, Math.max(1, parseInt(b.minutes, 10) || 60)));
        const r = await gwsa(["unlock", alias, arg]);
        return send(res, r.code ? 500 : 200, { ok: !r.code, out: r.stdout + r.stderr });
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
        if (action === "grant") {
          const h = Math.min(168, Math.max(1, parseInt(b.hours, 10) || 8));
          args = ["grant", alias, target, String(h)];
        } else {
          args = ["policy", alias, "allow", target];
        }
        const r = await gwsa(args);
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

server.listen(PORT, HOST, () => {
  console.log(`Admin gws multi-comptes : http://${HOST}:${PORT} (local uniquement)`);
});
