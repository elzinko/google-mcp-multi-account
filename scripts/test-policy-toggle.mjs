#!/usr/bin/env node
// Garde-fou de la logique de matérialisation de policy côté navigateur
// (admin/index.html : buildTogglePolicy / ckCapsHtml). Fiche 0107, suite au
// NO-GO de revue #1 : basculer UNE opération ne doit JAMAIS en activer ou en
// perdre une AUTRE en douce. Ce chemin n'a pas de DOM ; on extrait les fonctions
// pures de la page et on les exécute dans un bac à sable vm — pas de framework JS
// dans ce projet, donc pas d'ajout de dépendance.
//
// Piège couvert : « service absent d'une policy qui EXISTE » = default-deny
// (scripts/policy-check.py), à matérialiser tout-refusé — pas tout-permis.
import { readFileSync } from "node:fs";
import vm from "node:vm";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
// POLICY_SRC permet de pointer une autre copie (ex. version pré-fix) pour
// vérifier que ce garde-fou n'est pas vide ; défaut = la page courante.
const SRC = readFileSync(process.env.POLICY_SRC || path.join(ROOT, "admin/index.html"), "utf8");

// --- Extraction à profondeur de crochets équilibrée ------------------------
function sliceBalanced(src, startIdx) {
  // À partir du 1er ( { [ rencontré ≥ startIdx, renvoie la tranche jusqu'à sa
  // fermeture équilibrée incluse. Ignore chaînes ET commentaires (les
  // apostrophes françaises « l'écriture » dans un // ne sont pas des chaînes).
  const opens = { "{": "}", "[": "]", "(": ")" };
  let i = startIdx;
  while (i < src.length && !opens[src[i]]) i++;
  const open = src[i], close = opens[open];
  let depth = 0, inStr = null;
  for (; i < src.length; i++) {
    const c = src[i], n = src[i + 1];
    if (inStr) { if (c === inStr && src[i - 1] !== "\\") inStr = null; continue; }
    if (c === "/" && n === "/") { while (i < src.length && src[i] !== "\n") i++; continue; }
    if (c === "/" && n === "*") { i += 2; while (i < src.length && !(src[i] === "*" && src[i + 1] === "/")) i++; i++; continue; }
    if (c === '"' || c === "'" || c === "`") { inStr = c; continue; }
    if (c === open) depth++;
    else if (c === close) { depth--; if (depth === 0) return src.slice(startIdx, i + 1); }
  }
  throw new Error("crochets non équilibrés depuis " + startIdx);
}
function extractConst(name) {
  const m = SRC.match(new RegExp("const\\s+" + name + "\\s*=\\s*"));
  if (!m) throw new Error("const introuvable : " + name);
  const eq = m.index + m[0].length;
  const val = sliceBalanced(SRC, eq);
  return "const " + name + " = " + val + ";";
}
function extractFn(name) {
  const m = SRC.match(new RegExp("function\\s+" + name + "\\s*\\("));
  if (!m) throw new Error("fonction introuvable : " + name);
  const paren = sliceBalanced(SRC, m.index + m[0].length - 1); // (...)
  const afterParen = m.index + m[0].length - 1 + paren.length;
  const body = sliceBalanced(SRC, afterParen); // {...}
  return "function " + name + paren + body;
}

const pieces = [
  // Stubs des dépendances hors-sujet pour ces tests (attr contient une regex avec
  // guillemet qui piège l'extracteur ; les icônes n'affectent pas la classe on/off).
  "const attr = (s) => String(s); const CK_CAP_OK = 'OK'; const CK_CAP_NO = 'NO';",
  extractConst("DRIVE_KEYS"), extractConst("GMAIL_KEYS"),
  extractConst("CAL_KEYS"), extractConst("KEEP_KEYS"), extractConst("SVCDEF"),
  extractFn("normDrive"), extractFn("isDeclared"), extractFn("currentEffectiveBlock"),
  extractFn("svcFreeBlock"), extractFn("svcDeniedBlock"), extractFn("svcFreeDisplay"),
  extractFn("buildTogglePolicy"),
  extractFn("ckCap"), extractFn("ckCapToggle"), extractFn("ckCapsHtml"),
];
const sandbox = {};
vm.createContext(sandbox);
vm.runInContext(pieces.join("\n"), sandbox);
const build = sandbox.buildTogglePolicy;
const caps = sandbox.ckCapsHtml;

// --- Assertions ------------------------------------------------------------
let pass = 0, fail = 0;
function ok(cond, desc) {
  if (cond) { pass++; process.stdout.write("  \x1b[32m✓\x1b[0m " + desc + "\n"); }
  else { fail++; process.stdout.write("  \x1b[31m✗\x1b[0m " + desc + "\n"); }
}

// A — policy PARTIELLE (gmail seul) : couper gmail 'read' n'ouvre aucune autre
// op de gmail, et NE matérialise PAS drive/agenda/keep en permissif.
{
  const p = { policy: { gmail: { read: true, drafts: true, send: false, labels: true, update: false, delete: false, settings: false } } };
  const out = build(p, "gmail", "read");
  ok(out.gmail.read === false && out.gmail.send === false && out.gmail.delete === false && out.gmail.settings === false,
     "policy partielle — couper gmail 'read' n'active aucune autre op gmail (send/delete/settings restent false)");
  ok(out.drive.share === false && out.drive.create === false && out.drive.update === false,
     "policy partielle — drive absent matérialisé tout-refusé (share/create/update = false), pas 'libre'");
}

// B — LE P0 : policy partielle (gmail seul), basculer DRIVE 'read' (affiché
// coupé) ne doit ouvrir QUE 'read' — jamais share/create/update/delete.
{
  const p = { policy: { gmail: { read: true, send: false } } };
  const out = build(p, "drive", "read");
  ok(out.drive.read === true && out.drive.share === false && out.drive.create === false && out.drive.update === false && out.drive.delete === false,
     "P0 — basculer drive 'read' sur policy existante n'ouvre QUE read (share/create/update/delete restent false)");
}

// E — symétrique du P0 côté non-drive : gmail ABSENT d'une policy existante
// (ex. policy drive-seule), basculer gmail 'send' n'ouvre QUE send.
{
  const p = { policy: { drive: { read: true, create: false, update: false, delete: false, share: false, zonesOnly: true, writeFolders: [] } } };
  const out = build(p, "gmail", "send");
  ok(out.gmail.send === true && out.gmail.read === false && out.gmail.delete === false && out.gmail.labels === false && out.gmail.settings === false,
     "gmail absent sous policy — basculer 'send' n'ouvre QUE send (read/delete/labels/settings restent false)");
}

// C — compte LIBRE (aucune policy) : basculer gmail 'send' préserve l'état
// libre des autres services (drive reste mode:open, pas de fail-close subit).
{
  const p = { policy: null };
  const out = build(p, "gmail", "send");
  ok(out.gmail.read === true && out.gmail.send === false && out.gmail.drafts === true,
     "compte libre — basculer gmail 'send' n'éteint que send, le reste reste permis");
  ok(out.drive && out.drive.mode === "open",
     "compte libre — drive non touché reste 'open' (pas de fail-close en douce)");
}

// D — drive déclaré mode:open : basculer 'share' part de tout-permis zoné
// (AC2 : zonesOnly, jamais wildcard), pas d'un bloc tout-refusé.
{
  const p = { policy: { drive: { mode: "open" } } };
  const out = build(p, "drive", "share");
  ok(out.drive.read === true && out.drive.create === true && out.drive.update === true && out.drive.share === false && out.drive.zonesOnly === true,
     "drive mode:open — basculer 'share' garde les autres ops permises + pose zonesOnly (pas de fail-close)");
}

// F — AFFICHAGE (ckCapsHtml, mode bascule) : un service absent d'une policy qui
// EXISTE se lit tout-COUPÉ (jamais « tout vert »), sinon la page ment sur l'état
// courant et matérialiser ce faux vert ouvre le service (jumeau du P0).
{
  const p = { policy: { gmail: { read: true, send: false } } }; // drive absent
  const driveHtml = caps("drive", p.policy.drive, true, "perso");
  ok(driveHtml.includes("ck-cap--off") && !driveHtml.includes("ck-cap--on"),
     "affichage — drive absent sous policy se lit TOUT COUPÉ (aucune pilule 'on')");
  const freeHtml = caps("drive", undefined, false, "x"); // compte libre
  ok(freeHtml.includes("ck-cap--on") && !freeHtml.includes("ck-cap--off"),
     "affichage — compte libre (sans policy) se lit TOUT PERMIS (aucune pilule 'off')");
}

process.stdout.write("\nbuildTogglePolicy : " + pass + " réussis, " + fail + " échoués\n");
process.exit(fail === 0 ? 0 : 1);
