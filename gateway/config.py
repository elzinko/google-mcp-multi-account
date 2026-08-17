"""Chemins et constantes partagés (alignés sur bin/mag)."""
from __future__ import annotations

import os
import re
from pathlib import Path

ALIAS_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]*$")
RESERVED = {
    "add", "list", "remove", "status", "help", "lock", "unlock",
    "policy", "grant", "grants", "strongauth", "admin", "broker",
    "session", "vault", "elicitation",
}

# Services gws non soumis à la policy données (auth locale, introspection).
PASSTHROUGH_SERVICES = frozenset({"auth", "schema"})

REPO_DIR = Path(__file__).resolve().parent.parent
POLICY_CHECKER = REPO_DIR / "scripts" / "policy-check.py"
USAGE_LOGGER = REPO_DIR / "scripts" / "log-usage.py"
SYS_PYTHON = "/usr/bin/python3"

# Nom « produit » du projet — SOURCE DE VÉRITÉ unique.
# Réutilisé partout dans le code (jamais ré-écrit en dur) :
#   • basename du binaire de signature → nom affiché dans le dialogue Touch ID ;
#   • à garder aligné avec le nom du serveur MCP (docs/mcp-setup.md).
# bin/mag et scripts/test.sh le lisent via cette constante (import Python).
# Rebrand (ex. « googlez ») = changer CETTE SEULE LIGNE.
PRODUCT_SLUG = "google-multi-account"


def gwsa_root() -> Path:
    return Path(os.environ.get("GWSA_ROOT") or Path.home() / ".config" / "gws-accounts")


def profile_dir(alias: str) -> Path:
    return gwsa_root() / alias


def upload_spool() -> Path:
    """Répertoire de dépôt des médias `--upload` — ET répertoire courant de gws
    côté broker (ADR-0003).

    gws refuse tout `--upload` dont le chemin résolu sort de son cwd : le
    contenu doit donc être écrit ici, et nulle part ailleurs. Le point en tête
    le tient hors des énumérations de profils (`ALIAS_RE`).
    """
    d = gwsa_root() / ".uploads"
    d.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(d, 0o700)
    except OSError:
        pass
    return d


def download_dir() -> Path:
    """Répertoire des fichiers REÇUS (pièces jointes Gmail) — ADR-0006.

    Les tools qui écrivent en local n'écrivent QUE là : jamais de chemin de
    destination choisi par le LLM, jamais d'écrasement (noms uniques). Le point
    en tête le tient hors des énumérations de profils (`ALIAS_RE`).
    """
    d = gwsa_root() / ".downloads"
    d.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(d, 0o700)
    except OSError:
        pass
    return d


def upload_roots() -> list[Path]:
    """Dossiers locaux autorisés comme SOURCE de `drive_upload` (liste blanche).

    `.downloads` est toujours autorisé (re-téléverser une PJ reçue). Pour
    téléverser un fichier situé ailleurs (un devis généré localement), déclarer
    son dossier — deux voies cumulables :

    - fichier `<GWSA_ROOT>/.upload-roots` (recommandé) : un chemin absolu par
      ligne, `#` = commentaire. Il vit avec le reste de la config, donc
      **survit aux redéploiements** (contrairement à l'env, réécrit par les
      installeurs) ;
    - variable d'environnement `GWSA_UPLOAD_ROOTS` (chemins séparés par
      `os.pathsep`), pour un réglage par client MCP.

    Volontairement HORS du dépôt git et HORS de `GWSA_ROOT` (tokens) : l'humain
    ouvre explicitement ce que le LLM peut lire. Le fichier n'est PAS modifiable
    par le LLM — aucun tool n'écrit sous `GWSA_ROOT`. Le point en tête le tient
    hors des énumérations de profils. Défaut vide → seul `.downloads` est
    lisible (ADR-0006).
    """
    parts: list[str] = os.environ.get("GWSA_UPLOAD_ROOTS", "").split(os.pathsep)
    conf = gwsa_root() / ".upload-roots"
    try:
        if conf.is_file():
            parts = parts + conf.read_text(encoding="utf-8").splitlines()
    except OSError:
        pass
    roots: list[Path] = []
    seen: set[str] = set()
    for part in parts:
        part = part.strip()
        if not part or part.startswith("#"):
            continue
        try:
            p = Path(part).expanduser()
            if p.is_dir():
                r = p.resolve()
                if str(r) not in seen:
                    seen.add(str(r))
                    roots.append(r)
        except OSError:
            continue
    return roots


def client_id() -> str:
    return os.environ.get("GWSA_CLIENT") or "mcp"
