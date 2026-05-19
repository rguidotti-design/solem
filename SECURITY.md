# SOLEM — Security policy + threat model

## Reporting vulnerabilities

Trovi un bug di sicurezza? **NON aprirlo come issue pubblica**.

Mandami una mail a: **guidottrbn@gmail.com** (founder Ruben Guidotti).
Subject: `[SECURITY] SOLEM <descrizione breve>`.

Rispondo entro **72 ore**. Fix critico: target **7 giorni**. Disclosure responsabile: **30 giorni** dopo fix rilasciato.

---

## Threat model (Step 0-1)

### Asset protetti
1. **Identità utente** (L1: nome, email, ruoli, valori, obiettivi, persone)
2. **Memoria utente** (L5: solem_memory + universe_memory con privacy `sacred`)
3. **Context snapshot** (L2: posizione, app aperte, ruolo attivo)
4. **Chiavi crittografiche** (CA root, WireGuard private keys, session token)
5. **API keys cloud** (Groq, Anthropic, OpenAI in `/etc/gavio/env`)
6. **Codice modificato dall'utente** (mount 9p `/opt/gavio` + custom Nix modules)

### Avversari considerati
- **Attaccante remoto su LAN** (rete WiFi pubblica/condivisa)
- **Device compromesso paired alla mesh** (es. telefono rubato/perso)
- **AI maliziosa nel marketplace** (Step 4+: extension di terze parti)
- **Insider con accesso fisico** (escluso da Step 0; Step 1+ con LUKS)

### Avversari **fuori scope**
- Stato-nazione con accesso fisico + tempo illimitato
- Attaccante con accesso hypervisor/BMC
- Side-channel hardware (Spectre/Meltdown class) — mitigato da kernel patch

---

## Mitigazioni implementate (Step 0)

| Asset | Mitigazione | Modulo |
|-------|-------------|--------|
| Identità + Memoria | SQLite locale `/var/lib/solem/solem.db`, file mode 0640, owner gavio | `db.py` |
| Context snapshot | Stesso DB, accesso via API auth | `context.py` |
| Chiavi crittografiche | `/var/lib/wireguard/wg-solem.key` chmod 600, owner gavio | `solem-mesh.nix` |
| Chiavi CA root | `/var/lib/solem-ca/ca.key` chmod 600 owner root, MAI esposta | `solem-zero-trust.nix` |
| API keys env | `/etc/gavio/env` chmod 600 owner gavio | `gavio.nix` |
| Sudo NOPASSWD | Solo per utente `gavio` (single-tenant Step 0) | `ai-freedom.nix` |
| Network ingress | Firewall NixOS, porte esplicitamente whitelisted | `networking.nix` |
| Bruteforce SSH | fail2ban max 5 retry, ban 1h | `security.nix` |
| Kernel hardening | sysctl strict (kptr_restrict, dmesg_restrict, ptrace_scope) | `solem-secure.nix` |
| Audit | systemd-auditd attivo, journald persistent | `security.nix` |

## Mitigazioni in arrivo (Step 1+)

- **LUKS2 disk encryption** — protezione data-at-rest (richiede passphrase boot)
- **Secure Boot Lanzaboote** — firma kernel + initrd con chiavi utente
- **sops-nix** — secret cifrati nel repo Git con chiavi age
- **mTLS gateway** — solo client con cert SOLEM-CA accedono via Caddy `:8443`
- **WireGuard mesh** — traffico inter-device cifrato + autenticato
- **AppArmor selettivo** — sandboxing per L7 extensions di terze parti (Core resta libero)
- **Cert revocation list** — revoca cert client paired in caso device perso
- **JWT short-lived** — token sessione TTL 15 min con refresh + revoca lato server
- **Rate limiting** — endpoint pubblici con limiti per-IP

---

## "AI Freedom" e sicurezza — coerenza

L'utente `gavio` ha sudo NOPASSWD + polkit aperto + accesso totale a device hardware (vedi [docs/AI_FREEDOM.md](docs/AI_FREEDOM.md)).

Questo **non è insicuro** perché:
1. **Single-tenant Step 0**: l'utente umano e l'AI condividono lo stesso "ruolo proprietario"
2. **Confini sono di RETE, non kernel-level**: firewall, mesh, mTLS proteggono dall'esterno
3. **Audit log centralizzato**: ogni azione passa per event bus L3 e viene loggata
4. **Atomicità NixOS**: `nixos-rebuild --rollback` reverte qualsiasi disastro in 30 secondi
5. **Backup automatico**: stato persistente snapshottato ogni 24h, retention 14 giorni

**Quando arriverà multi-tenancy (Step 4)**:
- `users.role` controllerà accesso granulare via JWT
- Extensions L7 saranno sandboxate con AppArmor (profili dichiarativi per-permissions)
- Capability manifest `permissions: [...]` enforced via policy engine OPA

---

## Privacy by design

| Dato | Trattamento |
|------|-------------|
| `privacy_level = 'public'` | Condivisibile con AI esterne |
| `privacy_level = 'work'` | Solo durante context.active_role lavorativo |
| `privacy_level = 'personal'` | Default: visibile a GAVIO, mai a terzi |
| `privacy_level = 'sacred'` | **MAI** inviato a LLM esterni cloud. Solo Ollama locale. |

Il flag `sacred` viene enforced lato client AI prima di inviare prompt a cloud LLM.

---

## Conformità

- **GDPR**: utente è "proprietario" dei propri dati, esportabili via `/solem/identity/me` + `/solem/memory/*` (Step 1+ aggiungerà `/solem/system/export-all`)
- **Diritto all'oblio**: `/solem/system/wipe-user/{id}` cancella tutto (Step 2+ multi-tenant)
- **No tracking**: nessuna telemetria silenziosa (vedi [docs/COSTS.md](docs/COSTS.md))
- **Open source**: codice ispezionabile, audit di terzi benvenuto

---

## Disclosure pubblica

Bug risolti in CHANGELOG (sezione "Sicurezza — fix dopo bug noti").

Vulnerabilità storiche (Step 0):
- PAM hijack via `security.pam.services.<n>.text` mkAfter → fix con `programs.bash.interactiveShellInit` (commit pre-release)
- FastAPI status 204 + return body → fix con dict response
- `hashedPassword` con `mutableUsers=true` non applicato → fix con `mutableUsers=false`
