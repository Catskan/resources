"""Configuration centralisée via Pydantic Settings.

Toutes les variables sont chargées depuis .env (ou variables d'environnement).
Voir .env.example pour la liste complète et la documentation de chaque champ.
"""

from pathlib import Path
from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # --- Vinted ---
    vinted_base_url: str = "https://www.vinted.fr"
    vinted_cookies_path: Path = Path("/app/data/cookies/vinted-cookies.json")
    vinted_user_id: int = 0
    vinted_user_agent: str = (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) "
        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
    )

    # --- Bumper ---
    bump_max_per_day: int = 6
    bump_min_delay_hours: int = 1
    bump_max_delay_hours: int = 10
    bump_active_hours_start: int = 12
    bump_active_hours_end: int = 23
    bump_min_days_between_rebump: int = 5
    bump_off_days_per_week: int = 0
    # Jitter aléatoire entre le tick DSM (HH:00) et l'action réelle.
    # Évite que 2 comptes (ou un compte régulier) tirent toujours à HH:00 pile.
    bump_jitter_min_min: int = 0
    bump_jitter_max_min: int = 45
    # Sélection pondérée par saison ('auto' = saison du jour, 'summer'/'winter'/
    # 'spring'/'autumn' pour forcer, 'off' pour random uniforme)
    bump_prefer_season: str = "off"

    # --- Optimizer LLM ---
    optimizer_enabled: bool = False
    optimizer_batch_size: int = 20
    optimizer_min_price_eur: float = 15.0
    optimizer_min_days_between_optimizations: int = 90
    optimizer_proposals_path: Path = Path("/app/data/proposals")

    # --- Photos ---
    photo_crop_px_max: int = 8
    photo_rotation_max_deg: float = 0.6
    photo_jpeg_quality_min: int = 84
    photo_jpeg_quality_max: int = 92
    photo_noise_sigma: float = 3.0
    photo_brightness_pct_max: float = 3.0

    # --- LLM ---
    llm_base_url: str = "http://192.168.1.42:1234/v1"
    llm_model_id: str = "mistral-small"
    llm_timeout_sec: int = 120
    llm_max_tokens: int = 600

    # --- PC Windows ---
    pc_mac: str = "AA:BB:CC:DD:EE:FF"
    pc_ip: str = "192.168.1.42"
    pc_ssh_user: str = "aurelien"
    pc_ssh_key_path: Path = Path("/root/.ssh/id_ed25519")
    pc_boot_timeout_sec: int = 180
    pc_llm_ready_timeout_sec: int = 120

    # --- Home Assistant (pilotage prise Zigbee du PC LLM) ---
    # Si HA_URL + HA_TOKEN + HA_PC_SWITCH_ENTITY définis : la prise est allumée
    # avant le WoL, et éteinte après le shutdown Windows (zéro vampire draw PSU).
    # Si vides : la prise n'est pas pilotée (PC supposé sous tension permanente).
    ha_url: str = ""                          # ex. http://192.168.1.20:8123
    ha_token: str = ""                        # Long-lived access token (Profile HA → Security)
    ha_pc_switch_entity: str = ""             # entity_id, ex. switch.pc_aurel
    ha_post_shutdown_wait_sec: int = 45       # délai après shutdown Windows avant coupure prise

    # --- Stockage ---
    db_path: Path = Path("/app/data/db/vinted-bot.sqlite")
    log_path: Path = Path("/app/data/logs")
    log_level: Literal["DEBUG", "INFO", "WARNING", "ERROR"] = "INFO"

    # --- Notifications ---
    notif_enabled: bool = True
    notif_type: Literal["email", "telegram", "webhook", "none"] = "email"
    notif_email_to: str = ""
    smtp_host: str = "localhost"
    smtp_port: int = 25

    # --- Crosspost ---
    crosspost_queue_path: Path = Path("/app/data/crosspost/queue.json")


settings = Settings()
