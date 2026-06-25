"""Envoi de notifications selon NOTIF_TYPE.

Backends prévus :
  - email    : SMTP local Synology (port 25, sans auth)
  - telegram : bot HTTP
  - webhook  : POST JSON sur une URL custom
"""

from loguru import logger

from ..config import settings


def send(title: str, body: str) -> None:
    if not settings.notif_enabled or settings.notif_type == "none":
        logger.debug(f"notif désactivée — {title}")
        return

    if settings.notif_type == "email":
        _send_email(title, body)
    elif settings.notif_type == "telegram":
        _send_telegram(title, body)
    elif settings.notif_type == "webhook":
        _send_webhook(title, body)


def _send_email(title: str, body: str) -> None:
    # TODO Phase 1+ : smtplib vers settings.smtp_host
    logger.info(f"[EMAIL stub] {title}\n{body}")


def _send_telegram(title: str, body: str) -> None:
    raise NotImplementedError


def _send_webhook(title: str, body: str) -> None:
    raise NotImplementedError
