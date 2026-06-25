#!/usr/bin/env python3
"""Test le scheduler + selector en simulation Monte-Carlo.

Vérifie que les params produisent ~5 bumps/jour en moyenne et 2 jours OFF/semaine,
sans pattern temporel détectable.

Usage:
    python3 scripts/test-scheduler.py
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "src"))

from vinted_bot.bumper.scheduler import simulate  # noqa: E402
from vinted_bot.config import settings  # noqa: E402


def main() -> int:
    print("═" * 70)
    print("  Simulation Monte-Carlo du scheduler (params actuels)")
    print("═" * 70)
    print()
    print(f"  Config :")
    print(f"    BUMP_MAX_PER_DAY              = {settings.bump_max_per_day}")
    print(f"    BUMP_ACTIVE_HOURS             = {settings.bump_active_hours_start}h-{settings.bump_active_hours_end}h")
    print(f"    BUMP_MIN_DELAY_HOURS          = {settings.bump_min_delay_hours}")
    print(f"    BUMP_MAX_DELAY_HOURS          = {settings.bump_max_delay_hours}")
    print(f"    BUMP_OFF_DAYS_PER_WEEK        = {settings.bump_off_days_per_week}")
    print()

    print("  Simulation : 100 runs × 30 jours...")
    stats = simulate(n_days=30, n_runs=100)
    print()
    print(f"  Résultats :")
    print(f"    Moyenne bumps/jour            : {stats['mean_per_day']:.2f}")
    print(f"    Écart-type bumps/jour         : {stats['stdev_per_day']:.2f}")
    print(f"    Min/Max bumps/jour            : {stats['min_per_day']} / {stats['max_per_day']}")
    print(f"    Moyenne bumps/semaine         : {stats['mean_per_week']:.1f}")
    print(f"    Jours OFF observés / semaine  : {stats['off_days_per_week_observed']:.2f}")
    print()

    print("─" * 70)
    print("  Distribution des bumps par heure (sur toute la simulation) :")
    print("─" * 70)
    dist = stats["hour_distribution"]
    if dist:
        max_count = max(dist.values())
        for hour in sorted(dist):
            count = dist[hour]
            pct = count / sum(dist.values()) * 100
            bar = "█" * int(40 * count / max_count)
            print(f"    {hour:2}h  {bar:<40} {count:5} ({pct:5.1f}%)")

    print()
    print("─" * 70)
    print("  Sanity checks :")
    target = settings.bump_max_per_day
    mean = stats["mean_per_day"]
    expected_mean = target * (1 - settings.bump_off_days_per_week / 7)
    delta = abs(mean - expected_mean) / expected_mean * 100

    if delta < 15:
        print(f"    ✅ Moyenne {mean:.2f}/jour proche de la cible {expected_mean:.2f} (Δ {delta:.1f}%)")
    else:
        print(f"    ⚠️  Moyenne {mean:.2f}/jour loin de la cible {expected_mean:.2f} (Δ {delta:.1f}%)")

    if stats["max_per_day"] <= target:
        print(f"    ✅ Quota max respecté ({stats['max_per_day']} ≤ {target})")
    else:
        print(f"    ❌ Quota DÉPASSÉ ({stats['max_per_day']} > {target})")

    # Vérifie que les pics 12-14h et 19-22h concentrent bien les bumps
    peak_hours = {12, 13, 19, 20, 21, 22}
    peak_bumps = sum(dist.get(h, 0) for h in peak_hours)
    total_bumps = sum(dist.values())
    if total_bumps:
        peak_pct = peak_bumps / total_bumps * 100
        if peak_pct >= 60:
            print(f"    ✅ Pics 12-14h+19-22h concentrent {peak_pct:.1f}% des bumps")
        else:
            print(f"    ⚠️  Pics 12-14h+19-22h ne concentrent que {peak_pct:.1f}% des bumps")

    return 0


if __name__ == "__main__":
    sys.exit(main())
