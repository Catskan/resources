# Raccourcis pour lancer Ansible depuis le MacBook contrôleur.
# Toutes les cibles prompt le master password KeePass via scripts/run.sh.

.PHONY: help windows windows-vm linux macos check-macos windows-sshd check-windows-sshd wyse check-wyse claude-code check-claude-code uninstall-bloat ping-windows check-windows check-windows-vm check-linux test-keepass inspect-keepass keepass-autotype verify-windows headscale check-headscale lint

help:
	@echo "Cibles disponibles :"
	@echo "  make test-keepass     — Vérifie la résolution KeePass de chaque secret (offline)"
	@echo "  make verify-windows   — Vérifie l'état post-run des optimisations gaming (offline)"
	@echo "  make inspect-keepass  — Diagnostic offline : vérifie les paths + dumpe l'arbo de la DB"
	@echo "  make keepass-autotype — Ajoute les Window Associations Auto-Type aux entrées launchers (dry-run; --apply pour écrire)"
	@echo "  make windows          — Run complet sur aurelien-gaming + w11-vm-aurel"
	@echo "  make windows-vm       — Run uniquement sur w11-vm-aurel (test sur UTM avant bare-metal)"
	@echo "  make check-windows-vm — Dry-run sur w11-vm-aurel (--check --diff)"
	@echo "  make linux            — Run sur arch-linux-laptop"
	@echo "  make macos            — Durcissement SSH des Macs (M2 + Air)"
	@echo "  make check-macos      — Dry-run durcissement SSH Macs (--check --diff)"
	@echo "  make windows-sshd     — Durcissement SSH Windows seul (main_windows --tags sshd)"
	@echo "  make check-windows-sshd — Dry-run durcissement SSH Windows (--tags sshd --check)"
	@echo "  make wyse             — Déploiement complet Wyse : crée le CT + provisionne (Docker)"
	@echo "  make check-wyse       — Dry-run déploiement Wyse (--check --diff)"
	@echo "  make claude-code      — Provisionne le CT seul (main_wyse --limit claude_code_hosts)"
	@echo "  make check-claude-code — Dry-run provisioning CT seul (--check --diff)"
	@echo "  make uninstall-bloat  — Désinstalle les AppX bloatware sur aurelien-gaming"
	@echo "  make ping-windows     — win_ping sur les hosts Windows"
	@echo "  make check-windows    — Dry-run Windows (--check --diff)"
	@echo "  make check-linux      — Dry-run Linux"
	@echo "  make lint             — yamllint + ansible-lint"
	@echo ""
	@echo "Override KEEPASS_LOCATION pour pointer une autre DB :"
	@echo "  KEEPASS_LOCATION=/tmp/test.kdbx make windows"
	@echo ""
	@echo "Tags : passe-les en variable, ex :"
	@echo "  make windows ARGS='--tags rdp,wol'"
	@echo "  make windows ARGS='--skip-tags softwares_winget'"

ARGS ?=

test-keepass:
	./scripts/run.sh ansible-playbook playbooks/test_keepass.yml $(ARGS)

verify-windows:
	./scripts/run.sh ansible-playbook playbooks/verify_gaming_optim.yml $(ARGS)

inspect-keepass:
	./scripts/run.sh ./scripts/inspect_keepass.py $(ARGS)

keepass-autotype:
	./scripts/run.sh ./scripts/keepass_apply_autotype.py $(ARGS)

windows:
	./scripts/run.sh ansible-playbook main_windows_playbook.yml $(ARGS)

windows-vm:
	./scripts/run.sh ansible-playbook main_windows_playbook.yml --limit w11-vm-aurel $(ARGS)

check-windows-vm:
	./scripts/run.sh ansible-playbook main_windows_playbook.yml --limit w11-vm-aurel --check --diff $(ARGS)

linux:
	./scripts/run.sh ansible-playbook main_linux_playbook.yml $(ARGS)

macos:
	./scripts/run.sh ansible-playbook main_macos_playbook.yml $(ARGS)

check-macos:
	./scripts/run.sh ansible-playbook main_macos_playbook.yml --check --diff $(ARGS)

windows-sshd:
	./scripts/run.sh ansible-playbook main_windows_playbook.yml --tags sshd $(ARGS)

check-windows-sshd:
	./scripts/run.sh ansible-playbook main_windows_playbook.yml --tags sshd --check --diff $(ARGS)

wyse:
	./scripts/run.sh ansible-playbook main_wyse_playbook.yml $(ARGS)

check-wyse:
	./scripts/run.sh ansible-playbook main_wyse_playbook.yml --check --diff $(ARGS)

claude-code:
	./scripts/run.sh ansible-playbook main_wyse_playbook.yml --limit claude_code_hosts $(ARGS)

check-claude-code:
	./scripts/run.sh ansible-playbook main_wyse_playbook.yml --limit claude_code_hosts --check --diff $(ARGS)

uninstall-bloat:
	./scripts/run.sh ansible-playbook main_remove_softwares.yml $(ARGS)

ping-windows:
	./scripts/run.sh ansible windows_hosts -m ansible.windows.win_ping $(ARGS)

check-windows:
	./scripts/run.sh ansible-playbook main_windows_playbook.yml --check --diff $(ARGS)

check-linux:
	./scripts/run.sh ansible-playbook main_linux_playbook.yml --check --diff $(ARGS)

lint:
	yamllint .
	ansible-lint main_*.yml

headscale:
	./scripts/run.sh ansible-playbook main_headscale_playbook.yml $(ARGS)

check-headscale:
	./scripts/run.sh ansible-playbook main_headscale_playbook.yml --check --diff $(ARGS)
