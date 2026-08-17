"""Policy prudente écrite à la création d'un profil (mag add / docs)."""
from __future__ import annotations

import json
from typing import Any

# Aligné sur le préréglage « prudent » de l'admin + docs/sheets/tasks en lecture.
DEFAULT_POLICY: dict[str, Any] = {
    "drive": {
        "read": True,
        "create": True,
        "update": True,
        "delete": False,
        "share": False,
        "zonesOnly": True,
        "writeFolders": [],
    },
    "gmail": {
        "read": True,
        "drafts": True,
        "send": False,
        "labels": True,
        "update": False,
        "delete": False,
        "settings": False,
    },
    "calendar": {
        "read": True,
        "create": False,
        "update": False,
        "delete": False,
        "share": False,
    },
    "keep": {
        "read": True,
        "create": True,
        "update": False,
        "delete": False,
    },
    "docs": {"read": True, "create": False, "update": False},
    "sheets": {"read": True, "create": False, "update": False},
    "tasks": {"read": True, "create": False, "update": False, "delete": False},
}


def write_default_policy(path) -> None:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(DEFAULT_POLICY, f, indent=2, ensure_ascii=False)
        f.write("\n")
