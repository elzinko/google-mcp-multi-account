#!/usr/bin/env node
// Filet de tests du micro-routeur de vues (fiche 0098, ADR-0010 brique 3) :
// go(mode, params) est le SEUL endroit qui fixe VIEW et démarre le poll de la
// route active ; les render*() ne doivent plus réassigner VIEW (c'est la
// régression que ce refactor corrige). Même motif que les autres tests node
// de ce dossier (scripts/test-policy-toggle.mjs, scripts/test-html-render.mjs) :
// pas de DOM/jsdom, on extrait les fonctions/objets pertinents de
// admin/index.html et on les exécute dans un bac à sable vm avec des stubs
// pour tout ce qui touche le DOM (rendu réel, hors-scope de ce filet).
import { readFileSync } from "node:fs";
import vm from "node:vm";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const SRC = readFileSync(process.env.POLICY_SRC || path.join(ROOT, "admin/index.html"), "utf8");

// --- Extraction à profondeur de crochets équilibrée (motif partagé, cf.
// scripts/test-policy-toggle.mjs / scripts/test-html-render.mjs) -----------
function sliceBalanced(src, startIdx) {
  const opens = { "{": "}", "[": "]", "(": ")" };
  const REGEX_STARTS_AFTER = /[([{,=:!&|?;\n]|^$/;
  let i = startIdx;
  while (i < src.length && !opens[src[i]]) i++;
  const open = src[i], close = opens[open];
  let depth = 0, inStr = null, inCharClass = false, lastSig = "";
  for (; i < src.length; i++) {
    const c = src[i], n = src[i + 1];
    if (inStr === "regex") {
      if (c === "\\") { i++; continue; }
      if (c === "[") inCharClass = true;
      else if (c === "]") inCharClass = false;
      else if (c === "/" && !inCharClass) { inStr = null; lastSig = "/"; }
      continue;
    }
    if (inStr) { if (c === inStr && src[i - 1] !== "\\") inStr = null; continue; }
    if (c === "/" && n === "/") { while (i < src.length && src[i] !== "\n") i++; continue; }
    if (c === "/" && n === "*") { i += 2; while (i < src.length && !(src[i] === "*" && src[i + 1] === "/")) i++; i++; continue; }
    if (c === "/" && REGEX_STARTS_AFTER.test(lastSig)) { inStr = "regex"; inCharClass = false; continue; }
    if (c === '"' || c === "'" || c === "`") { inStr = c; continue; }
    if (c === open) depth++;
    else if (c === close) { depth--; if (depth === 0) return src.slice(startIdx, i + 1); }
    if (!/\s/.test(c)) lastSig = c;
  }
  throw new Error("crochets non équilibrés depuis " + startIdx);
}
function extractFn(name) {
  const m = SRC.match(new RegExp("function\\s+" + name + "\\s*\\("));
  if (!m) throw new Error("fonction introuvable : " + name);
  const paren = sliceBalanced(SRC, m.index + m[0].length - 1);
  const afterParen = m.index + m[0].length - 1 + paren.length;
  const body = sliceBalanced(SRC, afterParen);
  return "function " + name + paren + body;
}
function rawFnSource(name) { return extractFn(name); }

let pass = 0, fail = 0;
function ok(cond, desc) {
  if (cond) { pass++; process.stdout.write("  \x1b[32m✓\x1b[0m " + desc + "\n"); }
  else { fail++; process.stdout.write("  \x1b[31m✗\x1b[0m " + desc + "\n"); }
}

// --- AC1 : les render*() ne réassignent plus VIEW --------------------------
// Contrôle statique sur la SOURCE (pas d'exécution) : la fonction ne doit
// contenir aucune affectation "VIEW = ...". C'est exactement la régression
// visée par la fiche (« rendre a l'effet de bord de naviguer »).
for (const name of ["renderList", "renderDetail"]) {
  const src = rawFnSource(name);
  ok(!/\bVIEW\s*=[^=]/.test(src), name + "() ne réassigne plus VIEW (rendre n'est plus naviguer)");
}

// --- go() : seul point qui fixe VIEW et pilote le poll de route -----------
// On exécute go() en isolation avec des stubs pour tout ce qui dépend du DOM
// (syncChrome, ROUTES.enter/tick) : ce test verrouille le CONTRAT de go()
// (fixe VIEW, dispatche vers la route, gère un seul timer actif), pas le
// rendu réel (hors-scope, DOM non disponible en node:vm).
const goSrc = extractFn("go");
const stopPollSrc = extractFn("stopRoutePoll");
const startPollSrc = (() => { try { return extractFn("startRoutePoll"); } catch { return ""; } })();

const sandbox = {
  clearInterval: (id) => { sandbox.__cleared.push(id); },
  setInterval: (fn, ms) => { sandbox.__intervals.push({ fn, ms }); return sandbox.__intervals.length; },
  __cleared: [],
  __intervals: [],
};
vm.createContext(sandbox);
vm.runInContext(
  [
    // var (pas let/const) : seule une déclaration `var` de premier niveau
    // devient une propriété du contexte vm, lisible ensuite via sandbox.xxx.
    "var VIEW = { mode: 'boot', alias: null };",
    "var routeTimer = null;",
    "var syncChromeCalls = 0;",
    "function syncChrome() { syncChromeCalls++; }",
    "var entered = [];",
    "const ROUTES = {",
    "  list: {},",
    "  detail: {},",
    "  sessions: { ownsPoll: true, tick: () => {}, every: 3000 },",
    "  journal: { ownsPoll: true, tick: () => {}, every: 5000 },",
    "};",
    "function renderList() { entered.push(['list', null]); }",
    "function renderDetail(alias) { entered.push(['detail', alias]); }",
    "function enterSessions() { entered.push(['sessions', null]); }",
    "function enterJournal(p) { entered.push(['journal', p]); }",
    stopPollSrc,
    startPollSrc,
    goSrc,
  ].join("\n"),
  sandbox
);

sandbox.go("detail", { alias: "perso" });
ok(sandbox.VIEW.mode === "detail" && sandbox.VIEW.alias === "perso",
   "go('detail', {alias}) fixe VIEW sur la route et l'alias demandés");
ok(sandbox.syncChromeCalls === 1, "go() accorde le chrome (syncChrome) à chaque navigation");
ok(sandbox.entered.at(-1)[0] === "detail" && sandbox.entered.at(-1)[1] === "perso",
   "go() dispatche vers le rendu de la route (renderDetail)");

sandbox.go("list", {});
ok(sandbox.VIEW.mode === "list" && sandbox.VIEW.alias === null,
   "go('list') repasse VIEW en liste (alias remis à null) — c'est le retour « ← Comptes »");

sandbox.go("sessions", {});
ok(sandbox.__intervals.length === 1, "go('sessions') démarre le poll de la route (une seule route active à la fois)");
const sessionsIntervalId = sandbox.__intervals.length;

sandbox.go("journal", {});
ok(sandbox.__cleared.includes(sessionsIntervalId),
   "go('journal') coupe le timer de la route précédente avant d'ouvrir la suivante (jamais deux polls en parallèle)");

sandbox.go("list", {});
ok(sandbox.__intervals.length === 2, "go('list') ne redémarre pas de poll de route dédié (liste/détail = pas de poll propre)");

process.stdout.write("\nmicro-routeur de vues : " + pass + " réussis, " + fail + " échoués\n");
process.exit(fail === 0 ? 0 : 1);
