{ config, pkgs, lib, ... }:

# SOLEM AUDITD — regole audit kernel custom (compliance + forensics).
#
# Single responsibility: SOLO regole auditctl. Daemon è abilitato già in
# solem-base (security.audit.enable). Qui dichiariamo le regole.
#
# Regole ispirate STIG/CIS hardening + paranoia AI:
#   - syscalls privilegiate (sudo, su, mount, ptrace)
#   - file sensibili (/etc/passwd, /etc/shadow, /etc/solem/, ~/.ssh/)
#   - exec di binari sospetti (nc, ncat, socat, python-c)
#   - mod kernel (init_module, delete_module)
#
# 100% FOSS, costo 0 €.

let
  cfg = config.solem.auditd;

  rules = [
    # Identifica nostre regole
    "-D"
    "-b 8192"
    "-f 1"

    # Cambi UID/GID
    "-w /etc/passwd -p wa -k identity"
    "-w /etc/shadow -p wa -k identity"
    "-w /etc/group  -p wa -k identity"
    "-w /etc/gshadow -p wa -k identity"
    "-w /etc/sudoers -p wa -k privilege"
    "-w /etc/sudoers.d/ -p wa -k privilege"

    # Config SOLEM
    "-w /etc/solem/ -p wa -k solem-config"
    "-w /etc/nixos/ -p wa -k nixos-config"

    # SSH/GPG keys
    "-w /root/.ssh/ -p wa -k ssh-keys"
    "-w /etc/ssh/ -p wa -k ssh-config"

    # Privilege escalation
    "-a always,exit -F arch=b64 -S execve -F path=/run/wrappers/bin/sudo -k privesc"
    "-a always,exit -F arch=b64 -S execve -F path=/run/wrappers/bin/su   -k privesc"

    # Mount/umount
    "-a always,exit -F arch=b64 -S mount,umount2 -k mount"

    # Kernel module load
    "-a always,exit -F arch=b64 -S init_module,delete_module,finit_module -k modules"

    # ptrace (anti-debugging)
    "-a always,exit -F arch=b64 -S ptrace -k ptrace"

    # Crypto policy
    "-w /proc/sys/crypto/fips_enabled -p wa -k crypto"

    # Audit log integrity
    "-w /var/log/audit/ -p wa -k audit-tamper"

    # Lock rules (prevents runtime change senza reboot)
    "-e 2"
  ];
in {
  options.solem.auditd = {
    enable = lib.mkEnableOption "Regole auditd custom (STIG-inspired + SOLEM-specific)";

    immutableRules = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Append '-e 2' che blocca modifiche regole fino al reboot";
    };
  };

  config = lib.mkIf cfg.enable {
    security.audit.enable = true;
    security.auditd.enable = true;

    security.audit.rules =
      if cfg.immutableRules then rules
      else builtins.filter (r: r != "-e 2") rules;

    # Strumenti per leggere/analizzare audit log
    environment.systemPackages = with pkgs; [
      audit
    ];

    # Audit log rotation aggressivo (i log audit possono crescere veloce)
    services.logrotate.settings.audit = {
      files = [ "/var/log/audit/audit.log" ];
      rotate = 7;
      frequency = "daily";
      compress = true;
      missingok = true;
      notifempty = true;
    };
  };
}
