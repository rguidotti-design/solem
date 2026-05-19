# SOLEM Mesh — VPN tra device SOLEM

> Tutti i tuoi device che ospitano SOLEM si parlano in una rete privata
> WireGuard, fuori da Internet pubblico, senza passare per cloud terzi.

---

## Modello

```
              ┌──────────────────────────────┐
              │  SOLEM coordinator           │
              │  (Beelink mini-PC casa)      │
              │  10.42.0.1                   │
              └──────┬──────────┬────────────┘
                     │          │
              ┌──────┴───┐  ┌──┴──────────┐  ┌─────────────┐
              │ Phone    │  │ Laptop work │  │ Smartglass  │
              │ 10.42.0.10│ │ 10.42.0.11  │  │ 10.42.0.12  │
              └──────────┘  └─────────────┘  └─────────────┘
```

- **Coordinator** = server SOLEM principale, registry dei peer
- **Peer** = device secondari, si parlano col coordinator e (in routing
  permitted) tra loro
- **Subnet privata** 10.42.0.0/24 (configurabile)
- **DNS interno** `*.solem.mesh` (es. `phone.solem.mesh` → `10.42.0.10`)

Niente Tailscale, niente Zerotier. WireGuard puro + coordinator self-hosted.

---

## Attivazione

In `nixos/configuration.nix`:

```nix
solem.mesh = {
  enable = true;
  role = "coordinator";              # o "peer" su device secondari
  nodeAddress = "10.42.0.1/24";      # IP nella mesh
  listenPort = 51820;
};
```

Rebuild:

```bash
sudo nixos-rebuild switch --flake /etc/nixos/solem#solem-vm
```

Al primo boot, `solem-mesh-keygen.service` genera la chiave WireGuard in
`/var/lib/wireguard/wg-solem.key` (privata) e `.pub` (pubblica).

---

## Pairing nuovo device (PIN BBM-style)

Quando vuoi aggiungere un device (es. un telefono):

### 1. Sul coordinator: richiedi PIN

```bash
curl -X POST http://localhost:8001/solem/pairing/start
```

Risposta:

```json
{
  "pin": "A3F7C912",
  "expires_at": "2026-05-17T19:30:00Z",
  "coordinator_endpoint": "solem.local:51820",
  "instructions": "Sul nuovo device esegui: solem-join --pin A3F7C912 ..."
}
```

### 2. Sul nuovo device: confirm

Il device genera la sua keypair WireGuard, poi:

```bash
curl -X POST http://solem.local:8001/solem/pairing/confirm \
  -H "Content-Type: application/json" \
  -d '{
    "pin": "A3F7C912",
    "device_name": "phone-ruben",
    "device_pubkey_wg": "<DEVICE_PUBKEY>"
  }'
```

Riceve in risposta:

```json
{
  "device_id": "...",
  "assigned_ip": "10.42.0.10/32",
  "coordinator_pubkey_wg": "<COORD_PUBKEY>",
  "mesh_subnet": "10.42.0.0/24",
  "dns_server": "10.42.0.1"
}
```

Configura WireGuard locale con questi dati. Sei nella mesh.

### 3. PIN: regole

- 8 caratteri hex (esadecimali maiuscoli)
- Scade in **10 minuti**
- One-shot (consumato al primo confirm)
- Generato con `secrets.token_hex(4)` (cryptographic random)

---

## Sicurezza

| Threat | Mitigazione |
|--------|-------------|
| Peer compromesso ascolta altri | Subnet routing limitato + zero-trust mTLS sopra |
| PIN intercettato in transito | PIN inviato via canale fidato (occhio-a-occhio o messaging E2E) |
| Coordinator compromesso | Single point of failure — Step 3+ multi-coordinator |
| MITM su pairing | Step 2+ pairing usa challenge firmato da CA SOLEM |

---

## Stato implementazione

| Componente | Step 0 | Step target |
|------------|--------|-------------|
| Modulo NixOS `solem-mesh.nix` | ✅ scaffold | — |
| Keygen automatico | ✅ | — |
| Pairing API `/solem/pairing/*` | ✅ in-memory | Step 2: Supabase |
| Aggiornamento dinamico peers WG | ❌ | Step 1: hot-reload |
| DNS interno `*.solem.mesh` | ❌ stub | Step 1: dnsmasq attivo |
| Client `solem-join` per device | ❌ | Step 2: CLI + mobile app |
| Multi-coordinator HA | ❌ | Step 3+ |
