"""Entry point crosspost.

Maintient une file d'articles à reposter sur Leboncoin (queue.json).
Le userscript Tampermonkey lit ce fichier (sync via Synology Drive)
et pré-remplit le formulaire "Déposer une annonce" quand l'utilisateur
ouvre la page.

Usage :
    docker exec vinted-bot python -m vinted_bot.crosspost.runner --add 12345 67890
    docker exec vinted-bot python -m vinted_bot.crosspost.runner --refresh-queue
"""

import click


@click.command()
@click.option("--add", multiple=True, type=int, help="Item IDs Vinted à ajouter à la queue")
@click.option("--refresh-queue", is_flag=True, help="Régénère queue.json depuis la DB")
def main(add: tuple[int, ...], refresh_queue: bool) -> None:
    raise NotImplementedError("Phase 4")


if __name__ == "__main__":
    main()
