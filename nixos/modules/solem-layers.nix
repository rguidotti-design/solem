{ config, pkgs, lib, ... }:

{
  # I 7 LAYER SOLEM — placeholder Step 0.
  #
  # Questi layer vivranno come moduli Python + servizi systemd separati da
  # GAVIO. In Step 0 ne creiamo solo le ancore filesystem e il manifest.
  #
  #   L1 IDENTITY ENGINE     — chi è l'utente (ruoli, valori, obiettivi)
  #   L2 CONTEXT ENGINE      — dove, quando, cosa, ruolo attivo
  #   L3 ORCHESTRATION + EB  — coordinamento richieste + event bus
  #   L4 CAPABILITIES POOL   — cosa SOLEM sa fare (manifest per AI)
  #   L5 MEMORY & KNOWLEDGE  — 3 livelli (SOLEM + Utente + Contestuale)
  #   L6 INTEROP             — email, calendar, IoT, device targeting
  #   L7 EXTENSIONS          — marketplace AI + capabilities di terze parti

  # Versione SOLEM esposta come file
  environment.etc."solem/version".text = "0.1.0-step0";

  # Manifest machine-readable — letto da GAVIO + future AI per scoprire
  # le capabilities disponibili nel sistema
  environment.etc."solem/manifest.json".text = builtins.toJSON {
    name = "SOLEM";
    version = "0.1.0-step0";
    description = "OS AI-native che ospita GAVIO";
    primary_ai = "gavio";
    step = 0;

    layers = {
      L1_identity      = "stub (api /solem/identity/me)";
      L2_context       = "stub";
      L3_orchestration = "partial (in gavio)";
      L4_capabilities  = "partial (api /solem/capabilities + 9 nodi gavio)";
      L5_memory        = "partial (in gavio)";
      L6_interop       = "stub";
      L7_extensions    = "stub";
    };

    # Endpoints pianificati (porte allocate in networking.nix)
    services = {
      gavio_api    = "http://localhost:8000";
      solem_api    = "http://localhost:8001";  # L1-L4 stub
      ollama       = "http://localhost:11434";
    };

    # Hardware targets (per future migrazioni)
    targets = [ "vm" "beelink-mini" ];
  };

  # Directory di stato persistente per i futuri layer (ownership gavio)
  systemd.tmpfiles.rules = [
    "d /var/lib/solem            0755 gavio users -"
    "d /var/lib/solem/identity   0755 gavio users -"
    "d /var/lib/solem/context    0755 gavio users -"
    "d /var/lib/solem/eventbus   0755 gavio users -"
    "d /var/lib/solem/memory     0755 gavio users -"
  ];
}
