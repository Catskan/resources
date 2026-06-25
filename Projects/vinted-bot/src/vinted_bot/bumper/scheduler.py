"""Politique de timing probabiliste pour le bumper.

Appelé à chaque tick horaire (9h-22h) par DSM Task Scheduler.
Décide "republier maintenant ?" sans pattern temporel fixe.

Garanties :
  - Jamais hors plage 9h-22h
  - Jamais > BUMP_MAX_PER_DAY/jour
  - Toujours ≥ BUMP_MIN_DELAY_HOURS entre 2 bumps successifs
  - Force un bump si on dépasse BUMP_MAX_DELAY_HOURS sans rien faire (sauf si quota atteint)
  - ~BUMP_OFF_DAYS_PER_WEEK jours OFF par semaine en moyenne (random)
  - Jamais d'heure fixe : proba calculée à partir du budget restant
"""

from __future__ import annotations

import random
from dataclasses import dataclass
from datetime import datetime

from .. import db
from ..config import settings


# Poids par heure pour l'Option D — concentration 100% sur les pics.
# - Pic lunch  : 12h et 13h  → 2 bumps attendus
# - Zone morte : 14h-18h     → weight 0 = aucun bump
# - Pic soirée : 19h-22h     → 4 bumps attendus
# Total expected bumps/jour = 6 (= BUMP_MAX_PER_DAY)
HOUR_WEIGHTS: dict[int, float] = {
    12: 1.0,   # 🔥 Pic déjeuner
    13: 1.0,   # 🔥 Pic déjeuner
    14: 0.0,   # zone morte
    15: 0.0,
    16: 0.0,
    17: 0.0,
    18: 0.0,
    19: 1.0,   # 🔥 Pic soirée
    20: 1.0,   # 🔥 Pic soirée
    21: 1.0,   # 🔥 Pic soirée
    22: 1.0,   # 🔥 Pic soirée
}


@dataclass
class ScheduleDecision:
    should_bump: bool
    reason: str

    def __bool__(self) -> bool:
        return self.should_bump


def should_bump_now(now: datetime | None = None) -> ScheduleDecision:
    """Décide si on doit republier maintenant. Lit la DB en lecture seule."""
    now = now or datetime.now()

    # 1. Active hours
    if not (settings.bump_active_hours_start <= now.hour < settings.bump_active_hours_end):
        return ScheduleDecision(False, f"hors plage active ({now.hour}h)")

    with db.connect() as conn:
        today_row = db.get_or_create_today_counter(conn)
        n_today = today_row["n_republications"]
        is_off_day = bool(today_row["is_off_day"])
        last_bump = db.get_last_successful_bump_time(conn)

    # 2. Jour OFF
    if is_off_day:
        return ScheduleDecision(False, f"jour OFF (proba {settings.bump_off_days_per_week}/7)")

    # 3. Quota quotidien atteint
    if n_today >= settings.bump_max_per_day:
        return ScheduleDecision(
            False, f"quota atteint ({n_today}/{settings.bump_max_per_day})"
        )

    # 4. Délai minimum depuis le dernier bump
    if last_bump:
        delta_h = (now - last_bump).total_seconds() / 3600.0
        if delta_h < settings.bump_min_delay_hours:
            return ScheduleDecision(
                False,
                f"dernier bump il y a {delta_h:.1f}h (min {settings.bump_min_delay_hours}h)",
            )
        # 5. Force si dernier bump trop vieux (et il reste du quota)
        if delta_h > settings.bump_max_delay_hours and n_today < settings.bump_max_per_day:
            return ScheduleDecision(
                True,
                f"force (pas de bump depuis {delta_h:.1f}h > max {settings.bump_max_delay_hours}h)",
            )

    # 6. Probabilité pondérée par les heures restantes :
    #      proba = quota_restant × poids_heure / Σ(poids des heures restantes incluant celle-ci)
    #    → concentre naturellement les bumps sur les pics (12-14h, 19-22h)
    remaining_quota = settings.bump_max_per_day - n_today
    hour_w = HOUR_WEIGHTS.get(now.hour, 1.0)
    remaining_weights = sum(
        HOUR_WEIGHTS.get(h, 1.0)
        for h in range(now.hour, settings.bump_active_hours_end)
    )
    if remaining_weights <= 0:
        proba = 0.0
    else:
        base_proba = (remaining_quota * hour_w) / remaining_weights
        jitter = random.uniform(0.85, 1.20)
        proba = min(0.95, base_proba * jitter)

    roll = random.random()
    decision = roll < proba

    return ScheduleDecision(
        decision,
        f"proba={proba:.2%} (h{now.hour}h, w={hour_w}, quota_rest={remaining_quota}/"
        f"{settings.bump_max_per_day}, Σw_rest={remaining_weights:.1f}) → roll={roll:.2f} "
        f"→ {'BUMP' if decision else 'skip'}",
    )


def simulate(n_days: int = 30, n_runs: int = 100) -> dict:
    """Simulation Monte-Carlo (in-memory) avec les poids horaires courants.

    Renvoie des stats agrégées + la distribution heure-par-heure des bumps.
    """
    import statistics
    from collections import Counter
    from datetime import timedelta

    daily_counts: list[int] = []
    off_days_total = 0
    weekly_counts: list[int] = []
    hour_distribution: Counter = Counter()

    for run in range(n_runs):
        last_bump: datetime | None = None
        random.seed(run)

        for day_offset in range(n_days):
            day = datetime(2026, 1, 1, 0, 0) + timedelta(days=day_offset)
            n_today = 0

            is_off = (
                settings.bump_off_days_per_week > 0
                and random.random() < settings.bump_off_days_per_week / 7.0
            )
            if is_off:
                off_days_total += 1
                daily_counts.append(0)
                continue

            for hour in range(settings.bump_active_hours_start, settings.bump_active_hours_end):
                now = day.replace(hour=hour)
                if n_today >= settings.bump_max_per_day:
                    break
                if last_bump:
                    delta_h = (now - last_bump).total_seconds() / 3600.0
                    if delta_h < settings.bump_min_delay_hours:
                        continue
                    if delta_h > settings.bump_max_delay_hours:
                        last_bump = now
                        n_today += 1
                        hour_distribution[hour] += 1
                        continue

                remaining_quota = settings.bump_max_per_day - n_today
                hour_w = HOUR_WEIGHTS.get(hour, 1.0)
                remaining_weights = sum(
                    HOUR_WEIGHTS.get(h, 1.0)
                    for h in range(hour, settings.bump_active_hours_end)
                )
                if remaining_weights <= 0:
                    proba = 0.0
                else:
                    base_proba = (remaining_quota * hour_w) / remaining_weights
                    jitter = random.uniform(0.85, 1.20)
                    proba = min(0.95, base_proba * jitter)
                if random.random() < proba:
                    last_bump = now
                    n_today += 1
                    hour_distribution[hour] += 1

            daily_counts.append(n_today)

        for w in range(0, n_days - 6, 7):
            weekly_counts.append(sum(daily_counts[w:w + 7]))

    return {
        "runs": n_runs,
        "days_per_run": n_days,
        "mean_per_day": statistics.mean(daily_counts),
        "stdev_per_day": statistics.stdev(daily_counts),
        "max_per_day": max(daily_counts),
        "min_per_day": min(daily_counts),
        "off_days_per_week_observed": off_days_total / n_runs / (n_days / 7),
        "mean_per_week": statistics.mean(weekly_counts) if weekly_counts else 0,
        "hour_distribution": dict(hour_distribution),
    }
