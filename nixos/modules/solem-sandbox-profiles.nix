{ config, pkgs, lib, ... }:

# SOLEM SANDBOX PROFILES — bubblewrap wrapper per app comuni.
#
# Single responsibility: SOLO definire wrapper bwrap per browser/editor
# untrusted. Niente regole runtime (è nel kernel hardening module).
#
# Filosofia: ogni app untrusted gira sandboxed per default. L'utente
# può comunque eseguire l'app raw se vuole (binario originale resta in PATH).
#
# 100% FOSS, costo 0 €.

let
  cfg = config.solem.sandboxProfiles;

  # Helper: crea wrapper bwrap che fa override del binario originale
  mkSandbox = { name, exec, extraArgs ? [] }: pkgs.writeShellApplication {
    name = "${name}-sandboxed";
    runtimeInputs = with pkgs; [ bubblewrap ];
    text = ''
      exec ${pkgs.bubblewrap}/bin/bwrap \
        --ro-bind /nix /nix \
        --ro-bind /etc /etc \
        --ro-bind /usr /usr \
        --ro-bind /run/current-system /run/current-system \
        --proc /proc \
        --dev /dev \
        --tmpfs /tmp \
        --bind "$HOME/Downloads" "$HOME/Downloads" \
        --ro-bind /run/user/$(id -u)/wayland-0 /run/user/$(id -u)/wayland-0 \
        --setenv WAYLAND_DISPLAY wayland-0 \
        --setenv XDG_RUNTIME_DIR /run/user/$(id -u) \
        --unshare-all --share-net \
        ${lib.concatStringsSep " \\\n        " extraArgs} \
        -- ${exec} "$@"
    '';
  };

  firefoxSandbox = mkSandbox {
    name = "firefox";
    exec = "${pkgs.firefox}/bin/firefox";
    extraArgs = [
      ''--bind "$HOME/.mozilla" "$HOME/.mozilla"''
      ''--bind "$HOME/.cache/mozilla" "$HOME/.cache/mozilla"''
    ];
  };

  chromiumSandbox = mkSandbox {
    name = "chromium";
    exec = "${pkgs.chromium}/bin/chromium";
    extraArgs = [
      ''--bind "$HOME/.config/chromium" "$HOME/.config/chromium"''
    ];
  };

  vscodeSandbox = mkSandbox {
    name = "vscode";
    exec = "${pkgs.vscodium}/bin/codium";
    extraArgs = [
      ''--bind "$HOME/code" "$HOME/code"''
      ''--bind "$HOME/.config/VSCodium" "$HOME/.config/VSCodium"''
    ];
  };
in {
  options.solem.sandboxProfiles = {
    enable = lib.mkEnableOption "Wrapper sandboxed (bwrap) per app comuni";

    profiles = lib.mkOption {
      type = lib.types.listOf (lib.types.enum [ "firefox" "chromium" "vscode" ]);
      default = [ "firefox" "chromium" ];
      description = "App da fornire come *-sandboxed wrappers";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages =
      (lib.optional (builtins.elem "firefox" cfg.profiles) firefoxSandbox)
      ++ (lib.optional (builtins.elem "chromium" cfg.profiles) chromiumSandbox)
      ++ (lib.optional (builtins.elem "vscode" cfg.profiles) vscodeSandbox)
      ++ (with pkgs; [ bubblewrap ]);
  };
}
