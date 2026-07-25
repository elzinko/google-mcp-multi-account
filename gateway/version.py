"""Version réellement exécutée par le serveur — pas une constante codée en dur.

Le fichier `VERSION` est **généré au déploiement** (`scripts/deploy-local.sh`) et
n'est jamais commité : un clone de développement n'en a donc pas et s'annonce
`dev`. C'est ce qui distingue à l'œil nu le couloir stable (une version taggée)
du couloir de travail — cf. fiche 0023.
"""
from __future__ import annotations

from .config import REPO_DIR

DEV_VERSION = "dev"
VERSION_FILE = "VERSION"


def server_version() -> str:
    """Contenu de VERSION s'il existe et n'est pas vide, sinon « dev »."""
    try:
        value = (REPO_DIR / VERSION_FILE).read_text(encoding="utf-8").strip()
    except OSError:
        return DEV_VERSION
    return value or DEV_VERSION
