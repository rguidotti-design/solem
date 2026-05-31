{ config, pkgs, lib, ... }:

# SOLEM HARDWARE DETECT — Step 42: auto-detect + driver wizard.
#
# Single responsibility: SOLO orchestrazione nixos-hardware + lspci/lsusb
# detection + suggerimento moduli da abilitare in flake.
#
# Approccio: SOLEM NON installa driver automaticamente nel sistema attivo
# (sarebbe imperative, contro filosofia NixOS). Invece, SCOPRE hardware
# + suggerisce CONFIG NIX da aggiungere al flake + l'utente fa rebuild.
#
# Friday-like: "ho rilevato GPU NVIDIA RTX 3060. Aggiungo driver?
# (richiede rebuild)" — l'utente conferma, modulo genera snippet,
# utente lo aggiunge a configuration.nix.

let
  cfg = config.solem.hardwareDetect;
in {
  options.solem.hardwareDetect = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Installa solem-hw CLI per detect + suggerimenti driver";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      lshw pciutils usbutils dmidecode hwinfo nvme-cli smartmontools
      (pkgs.writeShellApplication {
        name = "solem-hw";
        runtimeInputs = with pkgs; [ coreutils lshw pciutils usbutils dmidecode gnugrep gawk ];
        text = ''
          ACTION="''${1:-detect}"

          case "$ACTION" in
            detect)
              echo "── SOLEM Hardware Auto-Detect ──"
              echo
              echo "── System ──"
              VENDOR=$(sudo dmidecode -s system-manufacturer 2>/dev/null || echo "?")
              MODEL=$(sudo dmidecode -s system-product-name 2>/dev/null || echo "?")
              BIOS=$(sudo dmidecode -s bios-version 2>/dev/null || echo "?")
              echo "  Vendor: $VENDOR"
              echo "  Model:  $MODEL"
              echo "  BIOS:   $BIOS"
              echo
              echo "── CPU ──"
              CPU=$(awk -F: '/model name/ {print $2; exit}' /proc/cpuinfo | xargs)
              CORES=$(nproc)
              echo "  $CPU"
              echo "  Cores: $CORES"
              echo
              echo "── GPU ──"
              GPU=$(lspci | grep -iE 'vga|3d|display' | head -3)
              echo "$GPU" | sed 's/^/  /'
              echo
              echo "── Network ──"
              lspci | grep -iE 'network|ethernet|wireless' | sed 's/^/  /'
              echo
              echo "── Storage ──"
              lsblk -d -o NAME,SIZE,MODEL,TRAN 2>/dev/null | head -10 | sed 's/^/  /'
              echo
              echo "── USB devices ──"
              lsusb | head -10 | sed 's/^/  /'
              ;;

            suggest)
              # Suggerisce moduli Nix da abilitare in base hw detect
              echo "── Suggerimenti config Nix ──"
              echo
              # nixos-hardware vendor specifico
              VENDOR=$(sudo dmidecode -s system-manufacturer 2>/dev/null | tr '[:upper:]' '[:lower:]')
              MODEL=$(sudo dmidecode -s system-product-name 2>/dev/null | tr '[:upper:]' '[:lower:]')
              if echo "$VENDOR" | grep -q "lenovo"; then
                echo "Aggiungi a flake.nix inputs:"
                echo "  inputs.nixos-hardware.url = \"github:NixOS/nixos-hardware\";"
                echo "Poi in modules:"
                echo "  imports = [ nixos-hardware.nixosModules.lenovo-thinkpad ];"
                echo
              elif echo "$VENDOR" | grep -q "dell"; then
                echo "imports = [ nixos-hardware.nixosModules.dell-xps-13-9310 ]; # adatta al modello"
                echo
              elif echo "$VENDOR" | grep -q "framework"; then
                echo "imports = [ nixos-hardware.nixosModules.framework-13-7040-amd ]; # adatta"
                echo
              elif echo "$MODEL" | grep -q "macbook"; then
                echo "imports = [ nixos-hardware.nixosModules.apple-t2 ]; # MacBook con T2"
                echo
              fi

              # GPU
              if lspci | grep -qi nvidia; then
                echo "## GPU NVIDIA rilevata ##"
                cat <<NIX

  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    modesetting.enable = true;
    powerManagement.enable = true;
    open = false;  # proprietary, abilita open per GPU Turing+
  };
  hardware.opengl.enable = true;
NIX
                echo
              fi
              if lspci | grep -qi "amd\|ati.*radeon"; then
                echo "## GPU AMD rilevata ##"
                echo "  services.xserver.videoDrivers = [ \"amdgpu\" ];"
                echo "  hardware.opengl.enable = true;"
                echo
              fi
              if lspci | grep -qi "intel.*graphics"; then
                echo "## GPU Intel rilevata ##"
                echo "  hardware.opengl = { enable = true; extraPackages = [ pkgs.intel-media-driver ]; };"
                echo
              fi

              # Wireless
              if lspci | grep -qi "broadcom.*wireless"; then
                echo "## Broadcom WiFi (driver proprietario richiesto) ##"
                echo "  boot.kernelModules = [ \"wl\" ];"
                echo "  boot.extraModulePackages = with config.boot.kernelPackages; [ broadcom_sta ];"
                echo "  nixpkgs.config.allowUnfree = true;"
                echo
              fi

              # Bluetooth
              if lsusb | grep -qi bluetooth || dmesg 2>/dev/null | grep -qi bluetooth; then
                echo "## Bluetooth ##"
                echo "  hardware.bluetooth.enable = true;"
                echo "  hardware.bluetooth.powerOnBoot = true;"
                echo "  services.blueman.enable = true;"
                echo
              fi

              # SSD/NVMe TRIM
              if ls /dev/nvme* 2>/dev/null | head -1 >/dev/null; then
                echo "## NVMe SSD: abilita TRIM ##"
                echo "  services.fstrim.enable = true;"
                echo
              fi

              # Battery (laptop)
              if [ -d /sys/class/power_supply/BAT0 ] || [ -d /sys/class/power_supply/BAT1 ]; then
                echo "## Laptop battery rilevata ##"
                echo "  services.tlp.enable = true;        # power management"
                echo "  services.upower.enable = true;     # battery status"
                echo "  powerManagement.cpuFreqGovernor = \"ondemand\";"
                echo
              fi

              # Touchpad
              if grep -qi touchpad /proc/bus/input/devices 2>/dev/null; then
                echo "## Touchpad ##"
                echo "  services.libinput.enable = true;"
                echo "  services.libinput.touchpad.tapping = true;"
                echo "  services.libinput.touchpad.naturalScrolling = true;"
                echo
              fi
              ;;

            generate-config)
              # Esegue nixos-generate-config (rigenera hardware-configuration.nix)
              echo "── Rigenera hardware-configuration.nix ──"
              sudo nixos-generate-config --show-hardware-config
              echo
              echo "Per salvare: sudo nixos-generate-config (sovrascrive /etc/nixos/hardware-configuration.nix)"
              ;;

            help|--help|-h|*)
              cat <<'HELP'
solem-hw — hardware auto-detect + driver suggestions

  detect             vendor + CPU + GPU + network + storage + USB
  suggest            snippet Nix config per hw rilevato (copy/paste)
  generate-config    nixos-generate-config (rigenera hw-config)

Workflow:
  1. solem-hw detect              # cosa hai
  2. solem-hw suggest             # cosa aggiungere a flake.nix
  3. Edit flake.nix con snippet suggeriti
  4. sudo nixos-rebuild switch
  5. Reboot se driver kernel-level

Threat coperto:
  - User non-tecnico non sa cosa abilitare per HW vendor specifico
  - Driver proprietari (NVIDIA, Broadcom) richiedono config esplicita

Tutto FOSS (lshw GPL, pciutils GPL).
HELP
              ;;
          esac
        '';
      })
    ];
  };
}
