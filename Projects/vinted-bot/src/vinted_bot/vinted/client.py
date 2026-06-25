"""Client HTTP Vinted authentifié.

Voir endpoints.py pour la doc complète des endpoints supportés.

Auth :
  - Cookies du navigateur (exportés via extension)
  - `Authorization: Bearer <access_token_web>` (JWT du cookie)
  - `X-CSRF-Token` extrait du HTML de la home page (cache 30 min)
  - `X-Anon-Id`, Referer, User-Agent réaliste
"""

from __future__ import annotations

import base64
import json
import re
import time
import uuid
from pathlib import Path
from typing import Any

import httpx
from loguru import logger

from ..config import settings
from .errors import (
    VintedAuthError,
    VintedCsrfError,
    VintedError,
    VintedNotFoundError,
    VintedRateLimitError,
    VintedServerError,
)


_CSRF_PATTERNS = [
    # Pattern actuel Vinted 2026 : embedded dans un blob JS échappé
    # Forme : \"CSRF_TOKEN\":\"75f6c9fa-dc8e-4e52-a000-e09dd4084b3e\"
    re.compile(r'CSRF_TOKEN\\?["\']?\s*[:=]\s*\\?["\']([0-9a-f-]{20,})'),
    re.compile(r'"CSRF_TOKEN"\s*:\s*"([0-9a-f-]{20,})"'),
    re.compile(r'<meta\s+name="csrf-token"\s+content="([^"]+)"'),
    re.compile(r'"csrf_token"\s*:\s*"([^"]+)"'),
    re.compile(r"csrfToken['\"]?\s*[:=]\s*['\"]([0-9a-f-]{20,})['\"]"),
]


def _decode_jwt_payload(token: str) -> dict:
    try:
        _, b64, _ = token.split(".", 2)
        return json.loads(base64.urlsafe_b64decode(b64 + "=" * (-len(b64) % 4)))
    except Exception:
        return {}


class VintedClient:
    """Client haut-niveau pour Vinted v2.

    Usage:
        with VintedClient() as v:
            items = v.list_active_items(page=1, per_page=20)
    """

    def __init__(self) -> None:
        self._cookies_raw: list[dict] = []  # liste brute pour persistance
        self._cookies, self._bearer = self._load_cookies_and_token()
        self._csrf: str | None = None
        self._csrf_fetched_at: float = 0.0

        self._client = httpx.Client(
            base_url=settings.vinted_base_url,
            cookies=self._cookies,
            headers={
                "User-Agent": settings.vinted_user_agent,
                "Accept": "application/json, text/plain, */*",
                "Accept-Language": "fr-FR,fr;q=0.9,en;q=0.8",
                "Authorization": f"Bearer {self._bearer}",
                "Referer": "https://www.vinted.fr/",
                "X-Anon-Id": self._cookies.get("anon_id", ""),
                "Origin": "https://www.vinted.fr",
            },
            timeout=30.0,
            follow_redirects=True,
        )

        # Refresh proactif si JWT proche d'expirer (< 5 min)
        payload = _decode_jwt_payload(self._bearer)
        exp = payload.get("exp", 0)
        if exp:
            remaining_min = (exp - time.time()) / 60
            if remaining_min < 5:
                logger.info(f"JWT expire dans {remaining_min:.1f} min → refresh préventif")
                self._refresh_access_token()

    # ─────────────────────────────────────────────────────────────
    # Auth / cookies
    # ─────────────────────────────────────────────────────────────

    def _load_cookies_and_token(self) -> tuple[dict[str, str], str]:
        path = settings.vinted_cookies_path
        if not path.exists():
            raise VintedAuthError(
                f"Cookies introuvables à {path}. Exporte-les depuis ton navigateur "
                "(extension 'Get cookies.txt LOCALLY', format JSON)."
            )
        self._cookies_raw = json.loads(Path(path).read_text())
        cookies = {c["name"]: c["value"] for c in self._cookies_raw if c.get("value")}
        bearer = cookies.get("access_token_web")
        if not bearer:
            raise VintedAuthError("Cookie `access_token_web` manquant.")

        payload = _decode_jwt_payload(bearer)
        exp = payload.get("exp", 0)
        # On accepte un JWT expiré : on tentera un refresh juste après l'init
        if exp:
            remaining_min = (exp - time.time()) / 60
            if remaining_min < 0:
                logger.warning(f"JWT expiré depuis {-remaining_min:.1f} min → refresh sera tenté")
            else:
                logger.debug(f"JWT valide encore {remaining_min:.1f} min")

        return cookies, bearer

    def _refresh_access_token(self) -> None:
        """Refresh le JWT via POST /oauth/token. Met à jour le cookies file."""
        from urllib.parse import urlencode

        refresh = self._cookies.get("refresh_token_web")
        if not refresh:
            raise VintedAuthError(
                "Cookie refresh_token_web absent — impossible de refresh, "
                "réexporte les cookies."
            )

        body = urlencode({
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "client_id": "web",
        })
        # Note : on n'envoie PAS le header Authorization (le but est d'en obtenir un nouveau)
        # On utilise httpx directement sans les headers du client persistant
        with httpx.Client(
            cookies=self._cookies,
            headers={
                "User-Agent": settings.vinted_user_agent,
                "Accept": "application/json",
                "Content-Type": "application/x-www-form-urlencoded",
                "Referer": "https://www.vinted.fr/",
                "Origin": "https://www.vinted.fr",
            },
            timeout=15.0,
        ) as c:
            r = c.post(f"{settings.vinted_base_url}/oauth/token", content=body.encode())

        if r.status_code != 200:
            raise VintedAuthError(
                f"Refresh OAuth échoué : HTTP {r.status_code} — {r.text[:200]}. "
                "Le refresh_token est peut-être expiré, réexporte les cookies."
            )
        data = r.json()
        new_access = data["access_token"]
        new_refresh = data.get("refresh_token", refresh)
        expires_in = data.get("expires_in", 7200)

        # Update in-memory
        self._bearer = new_access
        self._cookies["access_token_web"] = new_access
        self._cookies["refresh_token_web"] = new_refresh
        if hasattr(self, "_client"):
            self._client.headers["Authorization"] = f"Bearer {new_access}"
            self._client.cookies.set("access_token_web", new_access, domain=".www.vinted.fr")
            self._client.cookies.set("refresh_token_web", new_refresh, domain=".www.vinted.fr")

        # Persist le fichier cookies sur disque (sécurité : on update juste les 2 tokens)
        self._persist_cookies_update({
            "access_token_web": new_access,
            "refresh_token_web": new_refresh,
        })

        logger.success(f"✓ JWT refresh OK — valide {expires_in / 60:.0f} min")

    def _persist_cookies_update(self, updates: dict[str, str]) -> None:
        """Met à jour les valeurs de cookies dans le fichier JSON sur disque."""
        path = settings.vinted_cookies_path
        for c in self._cookies_raw:
            if c.get("name") in updates:
                c["value"] = updates[c["name"]]
        path.write_text(json.dumps(self._cookies_raw, indent=2))
        logger.debug(f"Cookies persistés à {path}")

    def _get_csrf_token(self, force_refresh: bool = False) -> str:
        # Re-fetch toutes les 30 min max
        if self._csrf and not force_refresh and (time.time() - self._csrf_fetched_at) < 1800:
            return self._csrf

        logger.debug("Fetch X-CSRF-Token depuis la home page Vinted")
        r = self._client.get("/", headers={"Accept": "text/html"})
        if r.status_code != 200:
            raise VintedCsrfError(f"Home page HTTP {r.status_code} — impossible d'extraire csrf")

        for pat in _CSRF_PATTERNS:
            m = pat.search(r.text)
            if m:
                self._csrf = m.group(1)
                self._csrf_fetched_at = time.time()
                logger.debug(f"X-CSRF-Token extrait: {self._csrf[:8]}…")
                return self._csrf

        raise VintedCsrfError(
            "Aucun X-CSRF-Token trouvé dans la home page (patterns connus n'ont pas matché)."
        )

    def _write_headers(self) -> dict[str, str]:
        return {
            "X-CSRF-Token": self._get_csrf_token(),
            "Content-Type": "application/json",
        }

    # ─────────────────────────────────────────────────────────────
    # Helpers HTTP avec retries
    # ─────────────────────────────────────────────────────────────

    def _request(
        self,
        method: str,
        path: str,
        *,
        params: dict | None = None,
        json_body: Any = None,
        files: list | None = None,
        data: dict | None = None,
        extra_headers: dict | None = None,
        max_retries: int = 3,
    ) -> httpx.Response:
        url = path if path.startswith("http") else path
        headers = dict(extra_headers or {})
        refreshed_once = False

        for attempt in range(max_retries):
            try:
                resp = self._client.request(
                    method, url,
                    params=params,
                    json=json_body,
                    files=files,
                    data=data,
                    headers=headers,
                )
            except httpx.RequestError as e:
                if attempt == max_retries - 1:
                    raise VintedError(f"RequestError after {max_retries} tries: {e}") from e
                wait = 2 ** attempt
                logger.warning(f"{method} {path} network error, retry in {wait}s: {e}")
                time.sleep(wait)
                continue

            if resp.status_code == 401:
                # Auto-refresh + retry une fois
                if not refreshed_once:
                    logger.info(f"401 sur {method} {path} → tentative de refresh")
                    self._refresh_access_token()
                    refreshed_once = True
                    continue
                raise VintedAuthError(
                    f"401 persistant sur {method} {path} après refresh : {resp.text[:200]}"
                )
            if resp.status_code == 403:
                raise VintedAuthError(
                    f"403 on {method} {path} (DataDome? CSRF? ACL?): {resp.text[:200]}"
                )
            if resp.status_code == 404:
                raise VintedNotFoundError(f"404 on {method} {path}")
            if resp.status_code == 429:
                wait = 2 ** (attempt + 3)  # 8, 16, 32s
                logger.warning(f"{method} {path} HTTP 429, sleeping {wait}s")
                time.sleep(wait)
                continue
            if resp.status_code >= 500:
                if attempt == max_retries - 1:
                    raise VintedServerError(f"{resp.status_code} on {method} {path}")
                wait = 2 ** attempt
                logger.warning(f"{method} {path} HTTP {resp.status_code}, retry in {wait}s")
                time.sleep(wait)
                continue
            return resp

        raise VintedError(f"{method} {path} exhausted retries")

    # ─────────────────────────────────────────────────────────────
    # GET endpoints
    # ─────────────────────────────────────────────────────────────

    def list_active_items(
        self, page: int = 1, per_page: int = 20, user_id: int | None = None
    ) -> dict:
        """Liste les items actifs du dressing (paginés)."""
        uid = user_id or settings.vinted_user_id
        if not uid:
            raise VintedError("VINTED_USER_ID non configuré et user_id non passé en arg")
        resp = self._request(
            "GET",
            f"/api/v2/wardrobe/{uid}/items",
            params={"page": page, "per_page": per_page},
        )
        return resp.json()

    def iter_all_active_items(self, user_id: int | None = None, per_page: int = 50):
        """Itère sur tous les items actifs (pagination automatique)."""
        page = 1
        while True:
            data = self.list_active_items(page=page, per_page=per_page, user_id=user_id)
            items = data.get("items", [])
            if not items:
                break
            yield from items
            if len(items) < per_page:
                break
            page += 1

    def get_item_photos(self, item_id: int) -> list[dict]:
        """Récupère les photos d'un item (avec full_size_url pour DL)."""
        resp = self._request("GET", f"/api/v2/items/{item_id}/photos")
        return resp.json().get("photos", [])

    def get_item_for_edit(self, item_id: int) -> dict:
        """Récupère le payload complet d'un item (tous les IDs numériques).

        C'est l'endpoint utilisé par le formulaire d'édition Vinted. Renvoie
        un dict avec : id, title, description, color1_id, color2_id, size_id,
        catalog_id, brand_id, package_size_id, item_attributes, etc.
        """
        resp = self._request("GET", f"/api/v2/item_upload/items/{item_id}")
        data = resp.json()
        # La réponse est {"item": {...}} ou parfois directement {...}
        return data.get("item", data)

    def download_image(self, url: str) -> bytes:
        """Télécharge une image (photo Vinted) en bytes."""
        with httpx.Client(
            headers={"User-Agent": settings.vinted_user_agent}, timeout=30.0
        ) as c:
            r = c.get(url)
            r.raise_for_status()
            return r.content

    def get_item_description(self, item_path: str) -> str | None:
        """Récupère la description complète via le HTML de la page item.

        item_path : ex. "/items/8050147948-pantalon-cargo-homme-brandit-adven"

        Parse le JSON-LD embedded dans le HTML. Retourne None si introuvable.
        """
        resp = self._request(
            "GET",
            item_path,
            extra_headers={"Accept": "text/html,application/xhtml+xml"},
        )
        html = resp.text

        # 1. JSON-LD
        m = re.search(
            r'<script[^>]+type="application/ld\+json"[^>]*>(.+?)</script>',
            html, re.DOTALL,
        )
        if m:
            try:
                ld = json.loads(m.group(1))
                desc = ld.get("description")
                if desc:
                    return desc.strip()
            except json.JSONDecodeError:
                pass

        # 2. og:description (fallback)
        m = re.search(r'<meta\s+property="og:description"\s+content="([^"]+)"', html)
        if m:
            # Format: "Titre - Description"
            content = m.group(1)
            if " - " in content:
                return content.split(" - ", 1)[1].strip()
            return content.strip()

        logger.warning(f"Description introuvable dans le HTML de {item_path}")
        return None

    # ─────────────────────────────────────────────────────────────
    # Write endpoints
    # ─────────────────────────────────────────────────────────────

    def upload_photo(
        self,
        image_bytes: bytes,
        filename: str,
        upload_session_id: str,
        photo_type: str = "item",
    ) -> dict:
        """Upload une photo. Renvoie le dict de la réponse (avec `id` à utiliser
        dans `assigned_photos` lors de la création/update d'item).

        upload_session_id : doit être le MÊME uuid v4 partagé entre toutes les
        photos d'un même item ET avec le subsequent POST item_upload/items.
        """
        files = [
            ("photo[file]", (filename, image_bytes, "image/jpeg")),
        ]
        data = {
            "photo[type]": photo_type,
            "photo[temp_uuid]": upload_session_id,
        }
        # Pour multipart, httpx gère content-type automatiquement
        headers = {"X-CSRF-Token": self._get_csrf_token()}
        resp = self._request(
            "POST",
            "/api/v2/photos",
            files=files,
            data=data,
            extra_headers=headers,
        )
        return resp.json()

    def create_item(self, item_payload: dict, upload_session_id: str) -> dict:
        """Crée un nouvel item. Renvoie {item: {id: X}, code: 0, ...}.

        item_payload : le dict `item.*` (sans la clé "id" qui sera mise à null).
                       Voir endpoints.py pour le format complet.
        upload_session_id : même uuid que pour les photos.
        """
        payload = {
            "item": {**item_payload, "id": None, "temp_uuid": upload_session_id},
            "feedback_id": None,
            "push_up": False,
            "parcel": None,
            "upload_session_id": upload_session_id,
        }
        resp = self._request(
            "POST",
            "/api/v2/item_upload/items",
            json_body=payload,
            extra_headers=self._write_headers(),
        )
        return resp.json()

    def update_item(self, item_id: int, item_payload: dict, upload_session_id: str) -> dict:
        """Met à jour un item existant (utilisé par l'optimizer + bumper republish)."""
        payload = {
            "item": {**item_payload, "id": item_id, "temp_uuid": upload_session_id},
            "feedback_id": None,
            "push_up": False,
            "parcel": None,
            "upload_session_id": upload_session_id,
        }
        resp = self._request(
            "PUT",
            f"/api/v2/item_upload/items/{item_id}",
            json_body=payload,
            extra_headers=self._write_headers(),
        )
        return resp.json()

    def delete_item(self, item_id: int) -> dict:
        """Supprime un item. ⚠️ Endpoint: POST /api/v2/items/{id}/delete (pas DELETE)."""
        resp = self._request(
            "POST",
            f"/api/v2/items/{item_id}/delete",
            extra_headers=self._write_headers(),
        )
        return resp.json()

    # ─────────────────────────────────────────────────────────────
    # Lifecycle
    # ─────────────────────────────────────────────────────────────

    def close(self) -> None:
        self._client.close()

    def __enter__(self) -> "VintedClient":
        return self

    def __exit__(self, *args) -> None:
        self.close()


def new_upload_session_id() -> str:
    """Génère un upload_session_id (uuid v4) pour grouper photos + item create."""
    return str(uuid.uuid4())
