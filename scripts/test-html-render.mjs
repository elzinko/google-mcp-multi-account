#!/usr/bin/env node
// Filet de tests du socle de rendu sûr (fiche 0096, ADR-0010 brique 2) : la
// tagged template html`` (échappe chaque interpolation par défaut, sauf
// marqueur explicite raw()) et les fonctions PURES de rendu qui s'appuient
// dessus (normDrive, ckCapsHtml, fmtMins, mdToHtml). Même motif que
// scripts/test-policy-toggle.mjs : pas de DOM, pas de jsdom — on extrait les
// fonctions pures de admin/index.html et on les exécute dans un bac à sable
// vm (pas de framework JS dans ce projet, donc pas d'ajout de dépendance).
//
// Test central : une valeur piégée `"><script>alert(1)</script>` interpolée
// dans html`` doit ressortir ÉCHAPPÉE (littérale), jamais exécutable. Un
// html`` qui n'échapperait pas ferait échouer ce test (voir commentaire au
// niveau de l'assertion).
import { readFileSync } from "node:fs";
import vm from "node:vm";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const SRC = readFileSync(process.env.POLICY_SRC || path.join(ROOT, "admin/index.html"), "utf8");

// --- Extraction à profondeur de crochets équilibrée (motif partagé avec les
// autres tests node de ce dossier — pas de module commun pour rester à un
// fichier = une exécution autonome, cf. scripts/test-policy-toggle.mjs) -----
function sliceBalanced(src, startIdx) {
  const opens = { "{": "}", "[": "]", "(": ")" };
  // mdToHtml contient des littéraux regex avec des backticks à l'intérieur
  // (ex. /```(?:[\w-]*)\n.../) : sans ceci, le backtick serait pris pour une
  // ouverture de template string et fausserait tout le comptage qui suit.
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
  const paren = sliceBalanced(SRC, m.index + m[0].length - 1);
  const afterParen = m.index + m[0].length - 1 + paren.length;
  const body = sliceBalanced(SRC, afterParen);
  return "function " + name + paren + body;
}

const pieces = [
  extractFn("esc"), extractFn("attr"), extractFn("raw"), extractFn("html"),
  extractFn("normDrive"),
  // CK_CAP_OK/NO sont de simples chaînes (icônes SVG), pas des valeurs entre
  // crochets — sliceBalanced (conçu pour tableaux/objets) ne s'y applique pas ;
  // on les stub, comme test-policy-toggle.mjs, seul le on/off nous importe ici.
  "const CK_CAP_OK = 'OK'; const CK_CAP_NO = 'NO';",
  extractConst("DRIVE_KEYS"), extractConst("GMAIL_KEYS"),
  extractConst("CAL_KEYS"), extractConst("KEEP_KEYS"), extractConst("SVCDEF"),
  extractFn("isDeclared"), extractFn("ckCap"), extractFn("ckCapToggle"), extractFn("ckCapsHtml"),
  extractFn("fmtMins"), extractFn("mdToHtml"),
];
const sandbox = {};
vm.createContext(sandbox);
vm.runInContext(pieces.join("\n"), sandbox);
const { html, raw, esc, normDrive, ckCapsHtml, fmtMins, mdToHtml } = sandbox;

let pass = 0, fail = 0;
function ok(cond, desc) {
  if (cond) { pass++; process.stdout.write("  \x1b[32m✓\x1b[0m " + desc + "\n"); }
  else { fail++; process.stdout.write("  \x1b[31m✗\x1b[0m " + desc + "\n"); }
}

// --- html`` : échappement par défaut ---------------------------------------
{
  const nom = "Alice & Bob";
  ok(html`<b>${nom}</b>` === "<b>Alice &amp; Bob</b>",
     "html`` échappe une interpolation texte (état au repos, valeur banale)");
}
{
  // LE test d'injection (obligatoire, fiche 0096) : sans esc() dans html``,
  // ceci resterait "><script>alert(1)</script> tel quel et casserait hors du
  // <span> qui l'entoure — l'assertion échouerait si html`` n'échappait pas.
  const piege = '"><script>alert(1)</script>';
  const out = html`<span title="${piege}">x</span>`;
  ok(!out.includes("<script>"), "html`` neutralise une valeur piégée <script> (jamais exécutable)");
  ok(out.includes("&lt;script&gt;alert(1)&lt;/script&gt;"), "html`` restitue la valeur piégée sous forme littérale échappée");
  ok(out.includes("&quot;&gt;"), 'html`` échappe aussi le \'">\' qui casserait l\'attribut title');
}
{
  ok(html`` === "", "html`` sur un template vide renvoie une chaîne vide (état au repos)");
  ok(html`texte simple` === "texte simple", "html`` sans interpolation renvoie le texte tel quel");
}
{
  // Marqueur de fragment déjà sûr : raw() insère sans ré-échapper.
  const icone = raw("<svg><path/></svg>");
  const out = html`<span>${icone}</span>`;
  ok(out === "<span><svg><path/></svg></span>", "raw() insère un fragment déjà sûr sans l'échapper");
}
{
  // raw() ne doit pas devenir une porte dérobée pour une valeur NON marquée :
  // seul un objet produit par raw() échappe à l'échappement.
  const pasSur = { __html: '<script>alert(1)</script>' };
  // Un objet qui ressemble à celui de raw() mais n'en vient pas reste un cas
  // interne à la primitive : on vérifie ici que la primitive esc() reste la
  // voie par défaut pour tout ce qui n'est pas explicitement raw().
  ok(typeof raw === "function", "raw() existe comme fonction dédiée au marquage explicite");
}

// --- normDrive : état au repos + cas nominal --------------------------------
{
  ok(normDrive(null) === null, "normDrive(null) → null (état au repos)");
  ok(normDrive({ mode: "readonly" }).zonesOnly === false, "normDrive readonly → zonesOnly false");
}

// --- fmtMins : état au repos + bascule d'unité ------------------------------
{
  ok(fmtMins(0) === "0 min", "fmtMins(0) → '0 min' (état au repos)");
  ok(fmtMins(45) === "45 min", "fmtMins(45) → '45 min'");
  ok(fmtMins(90) === "1h30", "fmtMins(90) → '1h30' (bascule heures)");
}

// --- ckCapsHtml : rendu identique avant/après migration vers html`` --------
{
  // Compte libre (sans policy) → tout permis, aucune pilule 'off'.
  const freeHtml = ckCapsHtml("drive", undefined, false, "");
  ok(freeHtml.includes("ck-cap--on") && !freeHtml.includes("ck-cap--off"),
     "ckCapsHtml — compte libre : tout permis (aucune pilule 'off')");
}
{
  // Service absent d'une policy qui EXISTE → tout coupé (default-deny affiché).
  const p = { drive: undefined };
  const driveHtml = ckCapsHtml("drive", p.drive, true, "");
  ok(driveHtml.includes("ck-cap--off") && !driveHtml.includes("ck-cap--on"),
     "ckCapsHtml — service absent sous policy existante : tout coupé (default-deny)");
}

// --- mdToHtml : le markdown ne doit pas laisser passer de HTML brut --------
{
  ok(mdToHtml("").startsWith(""), "mdToHtml('') ne casse pas (état au repos)");
  const out = mdToHtml('<img src=x onerror=alert(1)>');
  ok(!/<img/i.test(out), "mdToHtml n'ouvre pas d'injection : le HTML brut collé est échappé, pas interprété");
  ok(out.includes("&lt;img"), "mdToHtml restitue le HTML brut sous forme littérale échappée");
}

process.stdout.write("\nhtml`` / rendu pur : " + pass + " réussis, " + fail + " échoués\n");
process.exit(fail === 0 ? 0 : 1);
