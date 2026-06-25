class VintedError(Exception):
    """Erreur générique côté Vinted client."""


class VintedAuthError(VintedError):
    """Cookies invalides, expirés, ou JWT access_token expiré et refresh impossible."""


class VintedRateLimitError(VintedError):
    """429 ou détection anti-bot (DataDome)."""


class VintedNotFoundError(VintedError):
    """404 sur une ressource Vinted."""


class VintedCsrfError(VintedError):
    """Impossible de récupérer le X-CSRF-Token depuis la home page."""


class VintedServerError(VintedError):
    """5xx — erreur transitoire côté Vinted."""
