# SOLEM — operazioni comuni.
# Da WSL: make <target>. Da Windows nativo: usa scripts/*.ps1.

.PHONY: help vm build check eval ssh logs status restart-gavio setup-env clean

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
