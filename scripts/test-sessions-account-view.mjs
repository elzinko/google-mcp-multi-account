#!/usr/bin/env node
// Garde-fou de la logique de vue compte orientée sessions (fiche 0106) : les
// fonctions PURES de admin/index.html qui décident quelles sessions comptent
// pour un compte, et ce que compte le compteur X déverrouillées / Y verrouillées.
// Même motif que scripts/test-policy-toggle.mjs (fiche 0107) : pas de DOM ici,
// on extrait les fonctions pures et on les exécute dans un bac à sable vm — pas
// de framework JS dans ce projet, donc pas d'ajout de dépendance.
import { readFileSync } from "node:fs";
import vm from "node:vm";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const SRC = readFileSync(process.env.POLICY_SRC || path.join(ROOT, "admin/index.html"), "utf8");

function extractFn(name) {
  const m = SRC.match(new RegExp("function\\s+" + name + "\\s*\\("));
  if (!m) throw new Error("fonction introuvable : " + name);
  // Profondeur de parenthèses/accolades équilibrée, en ignorant chaînes et commentaires.
  const sliceBalanced = (src, startIdx) => {
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
  };
  const paren = sliceBalanced(SRC, m.index + m[0].length - 1);
  const afterParen = m.index + m[0].length - 1 + paren.length;
  const body = sliceBalanced(SRC, afterParen);
  return "function " + name + paren + body;
}

const pieces = [
  extractFn("sessionsForAccount"),
  extractFn("accountSessionCounts"),
  extractFn("sessDisplayName"),
  extractFn("sessionAccounts"),
];
const sandbox = {};
vm.createContext(sandbox);
vm.runInContext(pieces.join("\n"), sandbox);
const sessionsForAccount = sandbox.sessionsForAccount;
const accountSessionCounts = sandbox.accountSessionCounts;
const sessDisplayName = sandbox.sessDisplayName;
const sessionAccounts = sandbox.sessionAccounts;

let pass = 0, fail = 0;
function ok(cond, desc) {
  if (cond) { pass++; process.stdout.write("  \x1b[32m✓\x1b[0m " + desc + "\n"); }
  else { fail++; process.stdout.write("  \x1b[31m✗\x1b[0m " + desc + "\n"); }
}

// A — compte sans aucune session : 0 total / 0 déverrouillée / 0 verrouillée.
{
  const c = accountSessionCounts([], "perso");
  ok(c.total === 0 && c.unlocked === 0 && c.locked === 0, "compte sans session — compteur 0/0/0");
  ok(sessionsForAccount([], "perso").length === 0, "compte sans session — liste filtrée vide");
}

// B — session avec un déverrouillage ACTIF sur le compte : compte « déverrouillée ».
{
  const sessions = [{ session_id: "abc123def456", client: "mcp", unlocks: { perso: { until: 999, minutes_left: 20 } } }];
  const list = sessionsForAccount(sessions, "perso");
  ok(list.length === 1, "session avec unlock actif — apparaît dans la liste filtrée du compte");
  const c = accountSessionCounts(sessions, "perso");
  ok(c.total === 1 && c.unlocked === 1 && c.locked === 0, "session avec unlock actif — comptée déverrouillée (1/1/0)");
}

// C — session avec SEULEMENT une zone Drive (pas d'unlock) : référence le compte
// mais compte « verrouillée » (pas de déverrouillage général accordé).
{
  const sessions = [{ session_id: "zzz999yyy888", client: "cursor", drive_zones: { perso: [{ id: "f1", name: "Rapports", minutes_left: 480 }] } }];
  const c = accountSessionCounts(sessions, "perso");
  ok(c.total === 1 && c.unlocked === 0 && c.locked === 1, "session avec zone Drive seule — comptée verrouillée (1/0/1)");
  ok(sessionsForAccount(sessions, "perso").length === 1, "session avec zone Drive seule — référence bien le compte");
}

// D — session sur un AUTRE compte : exclue du filtre et du compteur de "perso".
{
  const sessions = [{ session_id: "aut111res222", client: "mcp", unlocks: { boulot: { until: 999, minutes_left: 5 } } }];
  ok(sessionsForAccount(sessions, "perso").length === 0, "session sur un autre compte — exclue du filtre");
  const c = accountSessionCounts(sessions, "perso");
  ok(c.total === 0, "session sur un autre compte — n'entre pas dans le compteur du compte visé");
}

// E — mélange : plusieurs sessions, certaines pertinentes certaines non, pour
// vérifier que le compteur agrège juste sans confondre les alias.
{
  const sessions = [
    { session_id: "s1s1s1s1s1s1", client: "mcp", unlocks: { perso: { until: 1, minutes_left: 1 } } },
    { session_id: "s2s2s2s2s2s2", client: "mcp", drive_zones: { perso: [{ id: "f", minutes_left: 1 }] } },
    { session_id: "s3s3s3s3s3s3", client: "mcp", unlocks: { boulot: { until: 1, minutes_left: 1 } } },
  ];
  const c = accountSessionCounts(sessions, "perso");
  ok(c.total === 2 && c.unlocked === 1 && c.locked === 1, "mélange de sessions — n'agrège que celles qui référencent le bon alias (2/1/1)");
}

// F — nom lisible (critère D) : fallback id court + client tant que 0101 (nom
// fourni par le client) n'est pas livré ; si `name` est présent, il prime.
{
  ok(sessDisplayName({ session_id: "abcdef123456", client: "mcp" }) === "abcdef · mcp",
     "fallback — id court (6) + client quand aucun nom n'est fourni");
  ok(sessDisplayName({ session_id: "abcdef123456", client: "cursor", name: "Session VS Code" }) === "Session VS Code",
     "un futur champ `name` prime sur le fallback, sans autre changement");
  ok(sessDisplayName({ session_id: "abcdef123456" }) === "abcdef · mcp",
     "client absent — fallback sur 'mcp' (valeur par défaut de listSessions())");
}

// G — comptes d'une session (critère E depuis la page Sessions, revue Codex #132) :
// union unlocks ∪ drive_zones, triée, dédoublonnée.
{
  ok(JSON.stringify(sessionAccounts({ unlocks: { perso: {} }, drive_zones: { perso: [], boulot: [] } })) === JSON.stringify(["boulot", "perso"]),
     "sessionAccounts — union unlocks∪zones, triée et dédoublonnée");
  ok(sessionAccounts({}).length === 0 && sessionAccounts(null).length === 0,
     "sessionAccounts — session vide ou nulle → aucun compte");
  ok(JSON.stringify(sessionAccounts({ drive_zones: { perso: [] } })) === JSON.stringify(["perso"]),
     "sessionAccounts — zone Drive seule (sans unlock) référence bien le compte");
}

process.stdout.write("\nvue compte orientée sessions (0106) : " + pass + " réussis, " + fail + " échoués\n");
process.exit(fail === 0 ? 0 : 1);
