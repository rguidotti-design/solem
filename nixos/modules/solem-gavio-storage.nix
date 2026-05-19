{ config, pkgs, lib, ... }:

{
  # ──────────────────────────────────────────────────────────────────────
  # SOLEM GAVIO STORAGE — `/var/lib/gavio/` strutturato (M1.2)
  # ──────────────────────────────────────────────────────────────────────
  # Allineamento Prompt Master v4.0 sez. 2.3:
  #
  #   /var/lib/gavio/
  #   ├── models/   → modelli AI gestiti via Nix (content-addressable hash)
  #   ├── memory/   → vector DB embedded (LanceDB — ADR-009)
  #   │   └── lance/<table>/  → tabelle per topic (chat, documents, code, ...)
  #   ├── cache/    → KV-cache persistente cross-session + embedding cache
  #   ├── audit/    → log immutabile append-only firmato ed25519
  #   └── state/    → stato conversazionale, contesti, granted_capabilities
  #
  # Tutti i path:
  # - owner: gavio:users
  # - mode: 0750 (gavio rw, users r, others -)
  # - eccetto audit/ che è 0700 (solo gavio, nessuno legge log altrui)
  # - eccetto state/ che è 0700 (può contenere secret runtime)

  systemd.tmpfiles.rules = [
    # Directory principali
    "d /var/lib/gavio              0750 gavio users -"

    # Sottocartelle strutturate
    "d /var/lib/gavio/models       0750 gavio users -"
    "d /var/lib/gavio/memory       0750 gavio users -"
    "d /var/lib/gavio/memory/lance 0750 gavio users -"
    "d /var/lib/gavio/cache        0750 gavio users -"
    "d /var/lib/gavio/cache/kv     0750 gavio users -"
    "d /var/lib/gavio/cache/embed  0750 gavio users -"
    "d /var/lib/gavio/audit        0700 gavio users -"
    "d /var/lib/gavio/state        0700 gavio users -"
    "d /var/lib/gavio/state/granted_caps 0700 gavio users -"

    # File README in ogni cartella (autodocumentazione per chi guarda manualmente)
    "f /var/lib/gavio/models/README.txt 0644 gavio users - Modelli AI gestiti via Nix (Step 3+) — content-addressable hash"
    "f /var/lib/gavio/memory/README.txt 0644 gavio users - Vector DB embedded (LanceDB — ADR-009). Backup automatico via solem-backup."
    "f /var/lib/gavio/cache/README.txt 0644 gavio users - Cache rigenerabile. Pulizia sicura. NON inserire dati persistenti qui."
    "f /var/lib/gavio/audit/README.txt 0644 gavio users - Audit log append-only firmato ed25519. NON cancellare manualmente."
    "f /var/lib/gavio/state/README.txt 0644 gavio users - Stato conversazionale e capabilities granted. Backup automatico."
  ];

  # Esporta path via /etc/solem/gavio-storage.json per consumo da AI/script
  environment.etc."solem/gavio-storage.json".text = builtins.toJSON {
    base = "/var/lib/gavio";
    paths = {
      models = "/var/lib/gavio/models";
      memory = "/var/lib/gavio/memory";
      memory_lance = "/var/lib/gavio/memory/lance";
      cache = "/var/lib/gavio/cache";
      cache_kv = "/var/lib/gavio/cache/kv";
      cache_embed = "/var/lib/gavio/cache/embed";
      audit = "/var/lib/gavio/audit";
      state = "/var/lib/gavio/state";
      granted_caps = "/var/lib/gavio/state/granted_caps";
    };
    permissions = {
      audit = "0700 — solo gavio, audit privato";
      state = "0700 — solo gavio, può contenere secret runtime";
      default = "0750 — gavio rw, users r";
    };
    notes = "Allineamento ADR-009 LanceDB + Prompt Master v4.0 sez. 2.3";
  };

  # Backup automatico esteso: solem-backup.nix include già /var/lib/gavio nella
  # lista SOURCES. Non serve modifica — verifica solo che paths esistano.
}
