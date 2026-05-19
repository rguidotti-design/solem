# Tail log GAVIO dalla VM senza entrarci.
#
# Uso:
#   .\scripts\logs.ps1              → log gavio.service
#   .\scripts\logs.ps1 ollama       → log ollama.service
#   .\scripts\logs.ps1 docker       → log docker.service

param(
    [string]$Service = "gavio"
)

$ErrorActionPreference = "Stop"

Write-Host "[solem] tail journalctl -u $Service (Ctrl-C per uscire)" -ForegroundColor Cyan

ssh -t -p 2222 `
    -o StrictHostKeyChecking=no `
    -o UserKnownHostsFile=NUL `
    -o LogLevel=ERROR `
    gavio@localhost `
    "sudo journalctl -u $Service -f --no-pager"
