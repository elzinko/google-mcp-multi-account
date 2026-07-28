"""Vault credentials — hors répertoire profil lisible (fiche 0003 / 0040).

Les tokens OAuth (`credentials.enc`) vivent sous `GWSA_ROOT/.vault/<alias>/`.
Le répertoire profil (`GWSA_ROOT/<alias>/`) ne contient que policy, verrous et
métadonnées — un appel `gws` nu avec CONFIG_DIR=profil ne trouve plus les tokens
après migration.
"""
from __future__ import annotations

import os
import shutil
from pathlib import Path

from .config import gwsa_root, profile_dir

VAULT_DIR_NAME = ".vault"
CREDENTIALS_NAME = "credentials.enc"


def vault_root() -> Path:
    d = gwsa_root() / VAULT_DIR_NAME
    d.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(d, 0o700)
    except OSError:
        pass
    return d


def vault_dir(alias: str) -> Path:
    d = vault_root() / alias
    d.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(d, 0o700)
    except OSError:
        pass
    return d


def credentials_path(alias: str) -> Path:
    return vault_dir(alias) / CREDENTIALS_NAME


def profile_credentials_legacy(alias: str) -> Path:
    return profile_dir(alias) / CREDENTIALS_NAME


def is_migrated(alias: str) -> bool:
    return credentials_path(alias).is_file()


def migrate_alias(alias: str) -> bool:
    """Déplace credentials.enc vers le vault si encore dans le profil. Retourne True si déplacé."""
    src = profile_credentials_legacy(alias)
    dst = credentials_path(alias)
    vdir = vault_dir(alias)
    prof = profile_dir(alias)
    for name in ("client_secret.json",):
        extra = prof / name
        if extra.is_file() and not (vdir / name).is_file():
            shutil.copy2(str(extra), str(vdir / name))
            try:
                os.chmod(vdir / name, 0o600)
            except OSError:
                pass
    if not src.is_file():
        return False
    if dst.is_file():
        try:
            src.unlink()
        except OSError:
            pass
        return False
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(src), str(dst))
    try:
        os.chmod(dst, 0o600)
    except OSError:
        pass
    return True


def migrate_all() -> list[str]:
    """Migre tous les profils qui ont encore credentials.enc dans le dossier alias."""
    root = gwsa_root()
    moved: list[str] = []
    if not root.is_dir():
        return moved
    for entry in root.iterdir():
        if not entry.is_dir() or entry.name.startswith("."):
            continue
        alias = entry.name
        if migrate_alias(alias):
            moved.append(alias)
    return moved


def gws_config_dir(alias: str) -> Path:
    """Répertoire passé à GOOGLE_WORKSPACE_CLI_CONFIG_DIR pour exécuter gws.

    Priorité : vault (tokens) ; le profil alias reste la source policy/lock.
    On assemble via un répertoire « runtime » dans le vault qui symlink ou
    copie les fichiers nécessaires — gws attend tout au même CONFIG_DIR.

    Stratégie : le vault dir contient credentials.enc ; on copie à la volée
    les fichiers non-secrets du profil dans un sous-dossier `.runtime/<alias>`
    pour les appels broker (policy reste lue depuis profile_dir séparément).
    """
    migrate_alias(alias)
    vdir = vault_dir(alias)
    if credentials_path(alias).is_file():
        return vdir
    # Legacy : pas encore migré
    return profile_dir(alias)


def ensure_vault_layout(alias: str) -> None:
    """Après gwsa add : rapatrier credentials dans le vault."""
    migrate_alias(alias)
