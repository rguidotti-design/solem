# SSH dentro la VM SOLEM running.
#
# La VM forwarda :22 → host :2222 (vedi nixos/hardware-vm.nix forwardPorts).
# Password iniziale: gavio (cambiala dopo primo login con `passwd`).
#
# Uso: .\scripts\ssh.ps1

$ErrorActionPreference = "Stop"

ssh -p 2222 `
    -o StrictHostKeyChecking=no `
    -o UserKnownHostsFile=NUL `
    -o LogLevel=ERROR `
    gavio@localhost
