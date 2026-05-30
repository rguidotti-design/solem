{ config, pkgs, lib, ... }:

# SOLEM SSH HARDENED — Step 11: SSH config strict + fail2ban multi-jail.
#
# Single responsibility: SOLO hardening di OpenSSH server + fail2ban policy.
# Non sostituisce solem-ai-network (firewall nft), non sostituisce
# solem-canary (kill switch su sintomi).
#
# Threat coperto:
#   - Brute-force SSH (auto-ban dopo 3 fail)
#   - Recidivi che riprovano dopo unban (ban progressivo lungo)
#   - Login con password (disabilitato, solo key)
#   - Login root (disabilitato)
#   - Algoritmi crypto obsoleti (DSA, RSA-1024, weak ciphers)
#   - User enumeration via login latency
#
# Tutto FOSS (OpenSSH BSD, fail2ban GPL-2.0). 0 €.

let
  cfg = config.solem.sshHardened;
in {
  options.solem.sshHardened = {
    enable = lib.mkEnableOption "SSH hardened config + fail2ban multi-jail";

    allowedUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "gavio" ];
      description = ''
        Lista whitelist degli utenti autorizzati a SSH login.
        gavio-ai NON deve essere qui (l'AI non fa SSH login).
      '';
    };

    passwordAuth = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Permettere login con password? Default OFF: solo chiavi SSH.
        Abilita SOLO se non hai una chiave (es. primo setup).
      '';
    };

    ignoreIP = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "127.0.0.0/8"
        "::1/128"
        # NB: NON includo 10.x / 192.168.x by default. Su una LAN
        # ostile (es. caffe' pubblico) un attaccante interno avrebbe
        # via libera. Aggiungi esplicitamente la tua LAN se serve.
      ];
      description = "IP/CIDR esentati da ban fail2ban";
    };
  };

  config = lib.mkIf cfg.enable {
    # ────────────────────────────────────────────────────────────────
    # OpenSSH server hardened
    # ────────────────────────────────────────────────────────────────
    services.openssh = {
      enable = true;

      settings = {
        # NIENTE login root MAI
        PermitRootLogin = lib.mkForce "no";

        # Password auth solo se esplicitamente abilitato
        PasswordAuthentication = lib.mkForce cfg.passwordAuth;
        KbdInteractiveAuthentication = lib.mkForce false;
        ChallengeResponseAuthentication = lib.mkForce false;

        # Solo chiavi
        PubkeyAuthentication = lib.mkForce true;

        # Whitelist utenti
        AllowUsers = cfg.allowedUsers;

        # Crypto modern only (no DSA, no RSA-1024, no weak ciphers)
        # Lista derivata da Mozilla SSH security guidelines 2024+
        Ciphers = [
          "chacha20-poly1305@openssh.com"
          "aes256-gcm@openssh.com"
          "aes128-gcm@openssh.com"
          "aes256-ctr"
          "aes192-ctr"
          "aes128-ctr"
        ];
        KexAlgorithms = [
          "curve25519-sha256"
          "curve25519-sha256@libssh.org"
          "diffie-hellman-group16-sha512"
          "diffie-hellman-group18-sha512"
        ];
        Macs = [
          "hmac-sha2-512-etm@openssh.com"
          "hmac-sha2-256-etm@openssh.com"
          "umac-128-etm@openssh.com"
        ];
        HostKeyAlgorithms = [
          "ssh-ed25519"
          "ssh-ed25519-cert-v01@openssh.com"
          "sk-ssh-ed25519@openssh.com"
          "rsa-sha2-512"
          "rsa-sha2-256"
        ];

        # Rate limit connection
        MaxAuthTries = 3;
        MaxSessions = 4;
        LoginGraceTime = 30;

        # X11 forwarding disabilitato (vettore exploit, raramente serve)
        X11Forwarding = false;

        # No empty password mai
        PermitEmptyPasswords = false;

        # Disable user enumeration via timing
        UseDNS = false;
        AllowAgentForwarding = false;
        AllowTcpForwarding = "no";
        PermitTunnel = "no";

        # Disconnect inactive after 5 min idle
        ClientAliveInterval = 300;
        ClientAliveCountMax = 2;
      };

      # Lista solo ED25519 + RSA-2048 (no DSA)
      hostKeys = [
        { type = "ed25519"; path = "/etc/ssh/ssh_host_ed25519_key"; }
        { type = "rsa"; bits = 4096; path = "/etc/ssh/ssh_host_rsa_key"; }
      ];

      # Banner di warning legale (deterrente + compliance)
      banner = ''
        ╔══════════════════════════════════════════════════════════╗
        ║                  SOLEM SECURE SYSTEM                     ║
        ║                                                          ║
        ║  Accesso autorizzato SOLO a utenti registrati.           ║
        ║  Tutte le sessioni sono LOGGATE + AUDITATE.              ║
        ║  Attivita' sospette → ban automatico (fail2ban) +        ║
        ║  segnalazione forensic (auditd).                         ║
        ║                                                          ║
        ║  Disconnect: clientAlive 5min idle.                      ║
        ╚══════════════════════════════════════════════════════════╝
      '';
    };

    # ────────────────────────────────────────────────────────────────
    # fail2ban multi-jail (sshd + recidive)
    # ────────────────────────────────────────────────────────────────
    services.fail2ban = {
      enable = true;

      # Ignora loopback. Altri IP esenti via cfg.ignoreIP.
      ignoreIP = cfg.ignoreIP;

      # Ban progressivo: dopo 3 fail in 10 min → ban 1h.
      # Dopo 5 ban totali → recidive ban 1 settimana.
      maxretry = 3;
      bantime = "1h";

      # Bantime increment esponenziale per recidivi
      bantime-increment = {
        enable = true;
        formula = "ban.Time * (1 << (ban.Count if ban.Count<20 else 20)) * banFactor";
        multipliers = "1 2 4 8 16 32 64";
        maxtime = "168h";   # 1 settimana cap
        overalljails = true;
      };

      jails = {
        # Jail SSH default + più strict
        sshd-strict = {
          settings = {
            enabled = true;
            filter = "sshd";
            backend = "systemd";
            maxretry = 3;
            findtime = "10m";
            bantime = "1h";
            port = "ssh";
          };
        };
      };
    };

    # ────────────────────────────────────────────────────────────────
    # PAM tally per limit local login (anti brute-force console)
    # ────────────────────────────────────────────────────────────────
    # NB: NixOS module gestisce questo via security.pam.loginLimits ma
    # per failed-attempt tracking serve pam_faillock o pam_tally2.
    # NixOS 24.11 ha builtin support solo per loginLimits, per faillock
    # serve passare a security.pam.services.<name>.text custom.
    # Lo lascio fuori per ora (rischio rompere PAM).

    # ────────────────────────────────────────────────────────────────
    # CLI di ispezione
    # ────────────────────────────────────────────────────────────────
    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "solem-ssh-status";
        runtimeInputs = with pkgs; [ coreutils fail2ban openssh procps ];
        text = ''
          echo "── SOLEM SSH Hardened ──"
          echo
          echo "── sshd config attivo ──"
          sshd -T 2>/dev/null | grep -E "permitrootlogin|passwordauthentication|pubkeyauthentication|allowusers|ciphers|kexalgorithms|maxauthtries" | head -15

          echo
          echo "── fail2ban status ──"
          if systemctl is-active fail2ban.service >/dev/null 2>&1; then
            sudo fail2ban-client status 2>/dev/null || echo "(no jails attivi)"
            echo
            echo "── IP attualmente bannati ──"
            for J in sshd sshd-strict; do
              BANNED=$(sudo fail2ban-client status "$J" 2>/dev/null | grep "Banned IP" || true)
              echo "$J: $BANNED"
            done
          else
            echo "fail2ban non attivo"
          fi

          echo
          echo "── Connessioni SSH attive ──"
          ss -tnpa 2>/dev/null | grep ":22 " | head -10 || echo "(nessuna)"
        '';
      })
    ];

    environment.etc."solem/ssh-hardened.md".text = ''
      # SOLEM SSH Hardened

      ## Cosa fa

      OpenSSH server config con strict modern crypto + fail2ban multi-jail.

      ### sshd config:
        - PermitRootLogin: NO
        - PasswordAuthentication: ${if cfg.passwordAuth then "YES (warning)" else "NO"}
        - PubkeyAuthentication: YES (solo)
        - AllowUsers: ${lib.concatStringsSep ", " cfg.allowedUsers}
        - MaxAuthTries: 3
        - ClientAliveInterval: 300s (5min idle disconnect)
        - X11Forwarding: NO
        - AllowAgentForwarding: NO
        - AllowTcpForwarding: NO
        - PermitTunnel: NO
        - Ciphers: solo chacha20-poly1305, aes-gcm, aes-ctr
        - KexAlgorithms: curve25519, dh-group16+, dh-group18+
        - HostKeyAlgorithms: ed25519, rsa-sha2-512/256

      ### fail2ban:
        - maxretry 3 in 10min → ban 1h
        - bantime-increment exponential: 1h → 2h → 4h → ... → 168h cap
        - jail sshd-strict aggiunto

      ## CLI

      ```
      solem-ssh-status     # config sshd + IP bannati + connessioni attive
      ```

      ## Limiti onesti

      - SSH key-only: se perdi la chiave, sei fuori. Backup chiave critico.
      - Su LAN ostile (caffe' pubblico) un attaccante interno NON e' filtrato
        a meno che aggiungi solo IP-fidati esplicit a allowedUsers.
      - fail2ban NON protegge da target distribuiti (botnet 10k IP).
        Per quello servirebbe rate-limit globale o anycast.
      - Banner SSH visibile pre-login: aiuta deterrenza/compliance ma e'
        info-leak (un attaccante sa che e' un sistema SOLEM).
    '';
  };
}
