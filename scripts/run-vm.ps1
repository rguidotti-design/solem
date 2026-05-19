# Lancia SOLEM VM da Windows nativo (PowerShell).
#
# Prerequisiti:
#   - WSL2 installato e configurato (wsl --install)
#   - Nix installato in WSL: sh <(curl -L https://nixos.org/nix/install) --daemon
#
# Lo script delega a WSL perché Nix non gira nativamente su Windows.
#
# Uso: .\scripts\run-vm.ps1

$ErrorActionPreference = "Stop"

$SolemRoot = Split-Path -Parent $PSScriptRoot
$WslPath = ($SolemRoot -replace '^([A-Za-z]):', '/mnt/$1' -replace '\\', '/').ToLower()

Write-Host "[solem] Avvio VM da WSL…"
Write-Host "[solem] Path WSL: $WslPath"
Write-Host ""

wsl bash -c "cd '$WslPath' && nix run .#vm"
