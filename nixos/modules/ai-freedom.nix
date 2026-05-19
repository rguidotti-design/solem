{ config, pkgs, lib, ... }:

{
  # AI-FREEDOM MODULE
  # ─────────────────
  # SOLEM è OS AI-native: l'AI è cittadino di prima classe. Questo modulo
  # configura permessi MASSIMI per l'utente "gavio" (= incarnazione AI).
  #
  # Filosofia Step 0 (single-tenant):
  #   - L'AI ha gli stessi diritti dell'utente umano
  #   - Zero attriti su azioni di sistema
  #   - I confini sono concettuali (Identity Engine + Capabilities manifest),
  #     non MAC kernel-level
  #
  # Quando arriverà multi-tenant (Step 4), polkit rules + per-AI capabilities
  # introdurranno permessi granulari per-utente, per-AI, per-azione.

  # ── 1. SUDO SENZA PASSWORD ─────────────────────────────────────────
  # gavio può eseguire qualsiasi comando di sistema senza prompt.
  # L'AI decide → l'AI agisce.
  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;
    extraRules = [
      {
        users = [ "gavio" ];
        commands = [
          { command = "ALL"; options = [ "NOPASSWD" "SETENV" ]; }
        ];
      }
    ];
  };

  # ── 2. POLKIT: ZERO PROMPT GRAFICI ────────────────────────────────
  # Per azioni privilegiate via D-Bus (montare device, gestire servizi,
  # impostare timezone, ecc.) — l'AI procede senza modal di conferma.
  security.polkit = {
    enable = true;
    extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (subject.user == "gavio") {
          return polkit.Result.YES;
        }
      });
    '';
  };

  # ── 3. ACCESSO HARDWARE COMPLETO ──────────────────────────────────
  # I gruppi (video/audio/dialout/input/plugdev) sono già assegnati in
  # solem-core.nix. Qui aggiungiamo udev rules permissive.
  services.udev.extraRules = ''
    # Accesso completo a tutti i device USB/seriali per gavio
    SUBSYSTEM=="usb", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="tty", MODE="0666", GROUP="dialout"
  '';

  # ── 4. FILESYSTEM: directory pre-create con ownership gavio ──────
  systemd.tmpfiles.rules = [
    "d /opt/gavio              0755 gavio users -"
    "d /var/lib/gavio          0755 gavio users -"
    "d /var/lib/gavio/venv     0755 gavio users -"
    "d /var/lib/gavio/data     0755 gavio users -"
    "d /var/log/gavio          0755 gavio users -"
    "d /etc/gavio              0755 gavio users -"
  ];

  # ── 5. PORTE BASSE LIBERE ─────────────────────────────────────────
  # gavio può bindare porte < 1024 (es. 80, 443) senza root.
  # Utile se l'AI decide di esporre servizi web senza reverse proxy.
  boot.kernel.sysctl."net.ipv4.ip_unprivileged_port_start" = 0;

  # ── 6. CAPABILITIES PROCESS ───────────────────────────────────────
  # I processi avviati da gavio possono fare raw socket (ping, traceroute)
  # e leggere process di altri utenti (introspection).
  # NB: lo facciamo a livello di systemd unit (gavio.service) per non
  # propagare a tutto il sistema.
}
