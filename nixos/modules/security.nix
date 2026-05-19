{ config, pkgs, lib, ... }:

{
  # Hardening minimo Step 0. Step 1+: sops-nix per secret, LUKS, AppArmor selettivo.

  # Audit kernel: traccia syscall sensibili per audit log
  security.audit.enable = true;
  security.auditd.enable = true;

  # Fail2ban: rate-limit SSH bruteforce
  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "1h";
    ignoreIP = [
      "127.0.0.0/8"
      "10.0.0.0/8"
      "192.168.0.0/16"
    ];
  };

  # PAM: aumenta limiti file descriptor (GAVIO apre molti socket)
  security.pam.loginLimits = [
    { domain = "*"; type = "soft"; item = "nofile"; value = "65536"; }
    { domain = "*"; type = "hard"; item = "nofile"; value = "131072"; }
  ];

  # NB IMPORTANTE: NON abilitiamo AppArmor né SELinux in Step 0.
  # SOLEM è AI-native: l'AI (GAVIO) deve operare senza MAC restrittivi.
  # I confini di sicurezza sono:
  #   1. Firewall (network)
  #   2. Filesystem permissions (user/group)
  #   3. Audit log (visibilità)
  #   4. Sandboxing solo per Extensions di terze parti (Step 4+)
}
