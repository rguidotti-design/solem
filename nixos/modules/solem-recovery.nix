{ config, pkgs, lib, ... }:

# SOLEM RECOVERY — recovery mode boot entry per troubleshooting.
#
# Single responsibility: SOLO entry GRUB "Recovery" che bootta in
# single-user emergency shell con tool diagnostici.
#
# Senza questo, se il sistema si rompe l'utente deve usare USB live.
# Con questo: tasto al boot → recovery shell con strumenti pronti.

let
  cfg = config.solem.recovery;
in {
  options.solem.recovery = {
    enable = lib.mkEnableOption "Recovery mode boot entry + tool diagnostici";

    autoMountReadonly = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Mount root in read-only di default in recovery (anti-incidente)";
    };
  };

  config = lib.mkIf cfg.enable {
    # Tool diagnostici sempre presenti
    environment.systemPackages = with pkgs; [
      btrfs-progs
      e2fsprogs
      cryptsetup
      gptfdisk
      parted
      smartmontools
      memtester
      stress-ng
      iperf3
      mtr
      tcpdump
      ncat
      socat
      ddrescue
      testdisk
    ];

    # Boot loader: aggiungi entry "Recovery"
    boot.loader.grub.extraEntries = lib.mkIf config.boot.loader.grub.enable ''
      menuentry "SOLEM Recovery (single-user)" {
          search --set=drive1 --label nixos
          linux ($drive1)/run/current-system/kernel \
            init=/run/current-system/sw/bin/bash \
            ${if cfg.autoMountReadonly then "ro" else "rw"} \
            systemd.unit=rescue.target loglevel=4
          initrd ($drive1)/run/current-system/initrd
      }
    '';

    # systemd-boot equivalent (UEFI)
    boot.loader.systemd-boot.extraEntries = lib.mkIf config.boot.loader.systemd-boot.enable {
      "solem-recovery.conf" = ''
        title SOLEM Recovery (single-user)
        linux /efi/nixos/kernel
        initrd /efi/nixos/initrd
        options init=/run/current-system/sw/bin/bash ${if cfg.autoMountReadonly then "ro" else "rw"} systemd.unit=rescue.target loglevel=4
      '';
    };

    # Banner che spiega come usare
    environment.etc."solem/recovery.md".text = ''
      # SOLEM Recovery Mode

      Quando il sistema non bootta normalmente:
        1. Riavvia
        2. Tieni premuto SHIFT (o ESC su systemd-boot)
        3. Scegli "SOLEM Recovery (single-user)"
        4. Bash shell di emergenza con root mount RO

      Strumenti diagnostici disponibili:
        - cryptsetup, parted, gptfdisk (disk)
        - e2fsprogs, btrfs-progs (filesystem)
        - smartmontools, ddrescue, testdisk (recovery dati)
        - memtester, stress-ng (test hardware)
        - mtr, tcpdump, iperf3 (network debug)

      Per rendere root writable (cautamente):
        mount -o remount,rw /

      Per fare un rebuild:
        cd /etc/nixos
        nixos-rebuild boot --flake .

      Per tornare al boot normale:
        reboot
    '';
  };
}
