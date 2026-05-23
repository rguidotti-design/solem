# SOLEM — operazioni comuni.
# Da WSL: make <target>. Da Windows nativo: usa scripts/*.ps1.

.PHONY: help vm vm-full build build-iso build-aarch64 check check-quick eval eval-iso eval-raspberry test test-list ssh logs status restart-gavio setup-env clean clean-store fmt lint deadnix-check tests-all dev-loop

WSL_SOLEM := /mnt/c/Users/guido/Desktop/solem
SSH_OPTS  := -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null

help:               ## mostra questo help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  %-18s %s\n", $$1, $$2}'

# ── Build / lancio ────────────────────────────────────────────────────
vm:                 ## build + lancia VM (alias di nix run .#vm)
	nix run .#vm

build:              ## solo build (non lancia)
	nix build .#vm

check:              ## verifica flake (lint)
	nix flake check

eval:               ## eval-only (becca errori senza scaricare)
	nix eval .#nixosConfigurations.solem-vm.config.system.build.vm.drvPath

# ── Accesso VM running ────────────────────────────────────────────────
ssh:                ## SSH dentro la VM (password: gavio)
	ssh $(SSH_OPTS) gavio@localhost

logs:               ## tail log GAVIO
	ssh $(SSH_OPTS) gavio@localhost 'sudo journalctl -u gavio -f --no-pager'

logs-ollama:        ## tail log Ollama
	ssh $(SSH_OPTS) gavio@localhost 'sudo journalctl -u ollama -f --no-pager'

status:             ## status dei servizi SOLEM
	ssh $(SSH_OPTS) gavio@localhost 'systemctl status gavio ollama --no-pager'

restart-gavio:      ## restart servizio GAVIO
	ssh $(SSH_OPTS) gavio@localhost 'sudo systemctl restart gavio'

# ── Setup ─────────────────────────────────────────────────────────────
setup-env:          ## apri editor su /etc/gavio/env nella VM
	ssh -t $(SSH_OPTS) gavio@localhost 'sudo cp -n /etc/gavio/env.example /etc/gavio/env; sudo vim /etc/gavio/env'

health:             ## curl http://localhost:8000/health
	@curl -sS http://localhost:8000/health || echo "GAVIO non risponde su :8000"

# ── Pulizia ───────────────────────────────────────────────────────────
clean:              ## rimuovi result/ e build artifacts
	rm -rf result result-*

clean-store:        ## GC Nix store (libera spazio in /nix)
	nix-collect-garbage -d

# ── Multi-target build ─────────────────────────────────────────────
vm-full:            ## build VM con TUTTI i moduli (può rompersi)
	nix build .#nixosConfigurations.solem-vm-full.config.system.build.vm

build-iso:          ## build ISO live x86_64 (con Calamares)
	nix build .#iso

build-aarch64:      ## cross-build SD image Raspberry Pi
	nix build .#raspberry

# ── Eval-only (veloce, no build) ───────────────────────────────────
eval-iso:           ## eval ISO senza buildare
	nix eval .#nixosConfigurations.solem-iso.config.system.build.isoImage.drvPath

eval-raspberry:     ## eval Raspberry senza buildare
	nix eval .#nixosConfigurations.solem-raspberry.config.system.build.sdImage.drvPath

# ── Test ───────────────────────────────────────────────────────────
check-quick:        ## solo eval (più veloce di check)
	nix flake check --no-build

test:               ## esegui un singolo VM test (TEST=basic-boot)
	@test -n "$(TEST)" || (echo "Usa: make test TEST=basic-boot"; exit 1)
	nix build .#checks.x86_64-linux.$(TEST) -L

test-list:          ## lista tutti i VM test disponibili
	@nix flake show --json 2>/dev/null | \
	  python3 -c "import json,sys; d=json.load(sys.stdin); \
	    tests=d.get('checks',{}).get('x86_64-linux',{}).keys(); \
	    [print(' -',t) for t in sorted(tests)]" 2>/dev/null || \
	  ls nixos/tests/ | grep -v default.nix | sed 's/.nix//' | sed 's/^/ - /'

tests-all:          ## esegui TUTTI i VM tests (lento ~ 30 min)
	nix flake check -L --keep-going

# ── Lint / Format ──────────────────────────────────────────────────
fmt:                ## formatta tutti i .nix con nixpkgs-fmt
	nix fmt

lint:               ## statix + deadnix
	nix run nixpkgs#statix -- check .
	nix run nixpkgs#deadnix -- .

# ── Dev loop: il ciclo iterativo veloce ────────────────────────────
dev-loop:           ## ciclo: eval → fix → eval → ... (rapido)
	@echo "── SOLEM dev-loop ──"
	@echo "1. Esegue eval rapido di vm/iso/raspberry"
	@echo "2. Se errore, mostra solo il modulo colpevole"
	@echo "3. Fixa, premi Enter, ricomincia"
	@while true; do \
	  clear; \
	  echo "── Eval $(shell date +%H:%M:%S) ──"; \
	  nix eval .#nixosConfigurations.solem-vm.config.system.build.vm.drvPath 2>&1 | tail -20; \
	  echo ""; \
	  read -p "Premi Enter per ri-eval (Ctrl+C per uscire)..."; \
	done
