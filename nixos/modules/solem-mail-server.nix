{ config, pkgs, lib, ... }:

# SOLEM MAIL SERVER — postfix + dovecot + rspamd + DKIM/SPF/DMARC.
#
# Single responsibility: SOLO orchestrare stack mail completo, opt-in.
# Per chi vuole tenere la PROPRIA email su SOLEM (no Gmail, no iCloud).
#
# Stack:
#   postfix     → SMTP (relay + submission 587)
#   dovecot     → IMAP/POP3 + Sieve filtri
#   rspamd      → antispam + DKIM signing
#   opendkim    → fallback DKIM
#   redis       → cache rspamd
#
# Setup richiede:
#   - Dominio proprio + DNS (MX, SPF TXT, DKIM TXT, DMARC TXT)
#   - TLS cert (Let's Encrypt via acme)
#   - Porte 25/465/587/993 aperte sul router
#
# 100% FOSS. Costo: 0 €.

let
  cfg = config.solem.mailServer;
in {
  options.solem.mailServer = {
    enable = lib.mkEnableOption "Mail server self-host (postfix + dovecot + rspamd)";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "solem.local";
      description = "Dominio mail (es. example.com)";
    };

    hostname = lib.mkOption {
      type = lib.types.str;
      default = "mail.solem.local";
      description = "FQDN del server mail";
    };

    enableTls = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "TLS via Let's Encrypt ACME";
    };
  };

  config = lib.mkIf cfg.enable {
    # ── Postfix SMTP ──
    services.postfix = {
      enable = true;
      hostname = cfg.hostname;
      domain = cfg.domain;
      origin = cfg.domain;
      destination = [ cfg.hostname cfg.domain "localhost" ];
      relayDomains = [];
      enableSubmission = true;
      enableSubmissions = true;       # 465 con TLS implicito
      sslCert = lib.mkIf cfg.enableTls "/var/lib/acme/${cfg.hostname}/fullchain.pem";
      sslKey  = lib.mkIf cfg.enableTls "/var/lib/acme/${cfg.hostname}/key.pem";
      config = {
        smtpd_tls_security_level = "may";
        smtp_tls_security_level = "may";
        smtpd_sasl_type = "dovecot";
        smtpd_sasl_path = "private/auth";
        smtpd_sasl_auth_enable = "yes";
        smtpd_sender_login_maps = "regexp:/etc/postfix/sender_login_maps";
        smtpd_relay_restrictions = "permit_sasl_authenticated, reject_unauth_destination";
        smtpd_recipient_restrictions = "permit_sasl_authenticated, reject_unauth_destination";
        virtual_mailbox_domains = "/etc/postfix/virtual_mailbox_domains";
        virtual_mailbox_maps = "hash:/etc/postfix/virtual_mailbox_maps";
        virtual_transport = "lmtp:unix:private/dovecot-lmtp";
        # rspamd milter
        smtpd_milters = "inet:localhost:11332";
        non_smtpd_milters = "inet:localhost:11332";
      };
    };

    # ── Dovecot IMAP + Sieve ──
    services.dovecot2 = {
      enable = true;
      enableImap = true;
      enableImaps = true;
      enablePop3 = false;
      enableLmtp = true;
      sslServerCert = lib.mkIf cfg.enableTls "/var/lib/acme/${cfg.hostname}/fullchain.pem";
      sslServerKey  = lib.mkIf cfg.enableTls "/var/lib/acme/${cfg.hostname}/key.pem";
      mailUser = "vmail";
      mailGroup = "vmail";
      mailLocation = "maildir:/var/vmail/%d/%n";
      enableQuota = true;
      modules = [ pkgs.dovecot_pigeonhole ];
      protocols = [ "sieve" ];
      sieveScripts = {
        before = pkgs.writeText "sieve-before" ''
          require ["fileinto", "imap4flags"];
          # Default: smista in cartelle in base a header
          if header :contains "X-Spam-Flag" "YES" {
            fileinto "Junk";
            stop;
          }
        '';
      };
    };

    # ── rspamd antispam + DKIM ──
    services.rspamd = {
      enable = true;
      locals = {
        "milter_headers.conf".text = ''
          use = ["x-spamd-bar", "x-spam-level", "authentication-results"];
        '';
        "dkim_signing.conf".text = ''
          enabled = true;
          domain {
            ${cfg.domain} {
              path = "/var/lib/rspamd/dkim/${cfg.domain}.key";
              selector = "solem";
            }
          }
        '';
      };
    };

    services.redis.servers.rspamd = {
      enable = true;
      port = 6379;
    };

    # ── ACME (Let's Encrypt) ──
    security.acme = lib.mkIf cfg.enableTls {
      acceptTerms = true;
      defaults.email = "admin@${cfg.domain}";
      certs.${cfg.hostname} = {
        webroot = "/var/lib/acme/acme-challenge";
        group = "nginx";
      };
    };

    # ── Firewall ──
    networking.firewall.allowedTCPPorts = [
      25     # SMTP
      465    # SMTPS
      587    # Submission
      993    # IMAPS
    ];

    # ── Users vmail ──
    users.users.vmail = {
      isSystemUser = true;
      group = "vmail";
      home = "/var/vmail";
      createHome = true;
    };
    users.groups.vmail = {};

    # ── Banner setup DNS ──
    environment.etc."solem/mail-server-dns.md".text = ''
      # SOLEM Mail Server — DNS records richiesti

      Sul tuo provider DNS (Cloudflare, OVH, ecc.) aggiungi:

      ## MX
      ${cfg.domain}   MX 10 ${cfg.hostname}.

      ## A/AAAA
      ${cfg.hostname}  A    <IP-PUBBLICO>
      ${cfg.hostname}  AAAA <IPv6-PUBBLICO>

      ## SPF (TXT su @)
      v=spf1 mx -all

      ## DMARC (TXT su _dmarc)
      v=DMARC1; p=quarantine; rua=mailto:postmaster@${cfg.domain}

      ## DKIM (dopo prima generazione chiave)
      rspamadm dkim_keygen -s solem -b 2048 -d ${cfg.domain} \\
        -k /var/lib/rspamd/dkim/${cfg.domain}.key

      Aggiungi al DNS la pubkey TXT su solem._domainkey.${cfg.domain}
      che il comando ha stampato.

      ## Porta in uscita 25
      Molti provider bloccano la 25 in uscita per default (anti-spam).
      Se il tuo non lo fa: ok.
      Altrimenti usa un relay smarthost (rspamd può inoltrare via 587 auth).

      ## Test
      Dopo DNS propagato:
        nc -vz ${cfg.hostname} 25
        nc -vz ${cfg.hostname} 587
        nc -vz ${cfg.hostname} 993
      E manda mail di test → mail-tester.com (check SPF/DKIM/DMARC score).
    '';
  };
}
