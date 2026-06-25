"""Setup loguru: stderr + fichier rotatif quotidien.

Le file handler est best-effort : si LOG_PATH n'est pas writable (cas d'un
dev Mac local où /app n'existe pas), on log uniquement vers stderr sans crash.
"""

import sys

from loguru import logger

from .config import settings


def setup_logging() -> None:
    logger.remove()
    logger.add(
        sys.stderr,
        level=settings.log_level,
        format=(
            "<green>{time:HH:mm:ss}</green> "
            "<level>{level: <7}</level> "
            "<cyan>{name}</cyan> | <level>{message}</level>"
        ),
    )
    try:
        settings.log_path.mkdir(parents=True, exist_ok=True)
        logger.add(
            settings.log_path / "vinted-bot.log",
            level=settings.log_level,
            rotation="00:00",
            retention="30 days",
            compression="gz",
            format="{time:YYYY-MM-DD HH:mm:ss} {level: <7} {name}:{function}:{line} | {message}",
        )
    except (OSError, PermissionError) as e:
        # En dev local hors container, /app/data/logs n'existe pas — on s'en passe
        logger.debug(f"File logger non initialisé ({e.__class__.__name__}: {e})")


setup_logging()
