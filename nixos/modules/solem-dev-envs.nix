{ config, pkgs, lib, ... }:

# SOLEM DEV ENVS — toolchain dev preconfigurate (profile developer).
#
# Single responsibility: SOLO installazione toolchain. Niente editor
# config (è in solem-code-assistant.nix).
#
# Linguaggi attivabili individualmente. 100% FOSS, 0 €.
#
# Pattern: ogni linguaggio aggiunge il proprio "module manager":
#   python  → uv (10x faster di pip) + ruff (linter) + mypy
#   rust    → rustup + cargo + clippy + rust-analyzer
#   go      → go + gopls + delve
#   node    → nodejs lts + pnpm + biome
#   java    → temurin JDK + maven + gradle
#   c/c++   → gcc + clang + cmake + ninja + lldb
#   nix     → nil + nixfmt + statix + deadnix

let
  cfg = config.solem.devEnvs;
in {
  options.solem.devEnvs = {
    python = lib.mkEnableOption "Python dev (uv + ruff + mypy)";
    rust   = lib.mkEnableOption "Rust dev (rustup + cargo + rust-analyzer)";
    go     = lib.mkEnableOption "Go dev (gopls + delve)";
    node   = lib.mkEnableOption "Node.js LTS (pnpm + biome)";
    java   = lib.mkEnableOption "Java (Temurin JDK + Maven + Gradle)";
    cpp    = lib.mkEnableOption "C/C++ (gcc + clang + cmake + ninja + lldb)";
    nix    = lib.mkEnableOption "Nix dev (nil + nixfmt-rfc-style + statix + deadnix)";

    direnv = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "direnv + nix-direnv (auto-load nix-shell per dir)";
    };
  };

  config = lib.mkIf (cfg.python || cfg.rust || cfg.go || cfg.node || cfg.java || cfg.cpp || cfg.nix) {
    environment.systemPackages = with pkgs; lib.flatten [
      # Common dev tools (sempre presenti)
      [ git gh lazygit jq yq-go ripgrep fd bat eza fzf tmux zellij htop btop ]

      (lib.optionals cfg.python [
        python312
        python312Packages.uv
        ruff
        python312Packages.mypy
        python312Packages.pytest
      ])

      (lib.optionals cfg.rust [
        rustc cargo clippy rustfmt rust-analyzer
      ])

      (lib.optionals cfg.go [
        go gopls delve gotools
      ])

      (lib.optionals cfg.node [
        nodejs_22 pnpm biome
      ])

      (lib.optionals cfg.java [
        temurin-bin-21 maven gradle
      ])

      (lib.optionals cfg.cpp [
        gcc clang cmake ninja gdb lldb meson pkg-config
      ])

      (lib.optionals cfg.nix [
        nil nixfmt-rfc-style statix deadnix nix-tree nh
      ])
    ];

    # direnv auto-load nix-shell
    programs.direnv = lib.mkIf cfg.direnv {
      enable = true;
      nix-direnv.enable = true;
      loadInNixShell = true;
    };
  };
}
