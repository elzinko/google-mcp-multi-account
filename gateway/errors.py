"""Erreurs structurées de la gateway (lock, policy, alias, exécution)."""


class GatewayError(Exception):
    """Échec contrôlé — message destiné au LLM / client MCP (élicitation)."""

    def __init__(self, message: str, code: str = "error"):
        super().__init__(message)
        self.code = code  # locked | policy | alias | not_found | exec | error

    def to_dict(self):
        return {"ok": False, "code": self.code, "error": str(self)}
