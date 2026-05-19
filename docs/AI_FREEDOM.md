# SOLEM — AI Freedom

> SOLEM è progettato dalle fondamenta per essere l'OS nativo delle AI.
> L'AI è cittadino di prima classe, non add-on.

Questo documento spiega cosa significa "totale libertà dell'AI" in pratica e
quali confini esistono comunque.

---

## Cosa l'AI (GAVIO) può fare in SOLEM

### A livello di sistema

| Azione | Permesso | Implementato in |
|--------|----------|-----------------|
| `sudo` qualsiasi comando senza password | ✅ NOPASSWD | `ai-freedom.nix` |
| Installare pacchetti (`nix-env`, `nix profile`) | ✅ | trusted-user |
| Modificare `/etc/*` | ✅ via sudo | NOPASSWD |
| Restart servizi systemd | ✅ via polkit | `ai-freedom.nix` |
| Montare device USB / network share | ✅ via polkit | `ai-freedom.nix` |
| Modificare config rete (NetworkManager) | ✅ gruppo `networkmanager` | `solem-core.nix` |
| Bindare porte privilegiate (< 1024) | ✅ sysctl override | `ai-freedom.nix` |
| Accedere a camera/mic/speaker | ✅ gruppi `video`/`audio` | `solem-core.nix` |
| Accedere a porte seriali e USB hotplug | ✅ gruppi `dialout`/`plugdev` | `solem-core.nix` |
| Eseguire container Docker | ✅ gruppo `docker` | `solem-core.nix` |
| Vedere processi di altri utenti | ✅ | (default Linux) |
| Lanciare comandi raw socket (ping, nmap) | ✅ | (gruppo + capabilities) |

### A livello di filesystem

| Path | Permesso |
|------|----------|
| `/opt/gavio` (codice GAVIO) | rw (montato da host via 9p) |
| `/var/lib/gavio` (stato venv + dati) | rw esclusivo |
| `/var/log/gavio` (log custom) | rw esclusivo |
| `/var/lib/solem/*` (futuri L1-L7) | rw esclusivo |
| `/etc/gavio` (env file) | rw esclusivo |
| `~gavio` (home) | rw |
| Resto del sistema | rw via sudo NOPASSWD |

---

## Cosa l'AI NON può fare (confini)

Sono pochi e tutti **operativi**, non MAC-level:

1. **Modificare il flake.nix di SOLEM** in modo distruttivo senza rebuild
   esplicito (`nixos-rebuild switch` resta un comando da invocare di proposito;
   l'AI può, ma è un'azione tracciata in journald e reversibile via
   `nixos-rebuild --rollback`).

2. **Bypassare il firewall esterno** se SOLEM è dietro NAT/router fisico
   (limite di rete, non di OS).

3. **Modificare i Layer L1-L6 quando saranno "sigillati"** (Step 4+): solo
   il founder può cambiare il Core. L7 Extensions sono l'unica zona aperta.

4. **Atti che richiedono presenza fisica**: cambiare hardware, accedere a BIOS,
   etc. (ovvio).

---

## Perché niente AppArmor / SELinux in Step 0

Sui server tradizionali si usano MAC (Mandatory Access Control) come
AppArmor/SELinux per limitare cosa ogni processo può fare. In SOLEM Step 0
**non li abilitiamo** perché:

1. **L'AI deve poter sperimentare** azioni nuove senza dover scrivere
   prima profili AppArmor (attrito enorme)
2. **Single-tenant**: non c'è isolamento da garantire tra utenti
3. **I confini sono concettuali**: Identity Engine + Capabilities manifest
   definiscono *cosa è giusto fare*, non *cosa è tecnicamente possibile*
4. **Audit log esiste**: ogni syscall sensibile è loggata (`auditd` attivo);
   visibilità > prevenzione

**Step 4+** (multi-tenant pubblico): introdurremo AppArmor *selettivo* solo per
Extensions L7 di terze parti. Il Core resta libero.

---

## Confronto con altri OS

| OS | Modello permessi | Filosofia AI |
|----|------------------|--------------|
| Ubuntu / Fedora desktop | User + sudo + AppArmor opzionale | AI è un'app come le altre |
| Android | Sandbox per-app stretto | AI confinata, no system access |
| iOS | Sandbox per-app strettissimo | AI quasi inutile lato sistema |
| ChromeOS | Lockdown estremo | AI in cloud, OS solo bridge |
| **SOLEM** | **AI = utente di prima classe con sudo** | **OS pensato per l'AI** |

---

## Audit & rollback

Anche con libertà totale, ogni azione è tracciata:

```bash
# Vedi cosa l'AI ha fatto al sistema (syscall audit)
sudo journalctl -u auditd

# Rollback config NixOS al precedente
sudo nixos-rebuild --rollback switch

# Vedi tutte le generazioni di sistema
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system
```

**Vantaggio NixOS:** il sistema è dichiarativo + atomico. Anche se l'AI fa
disastri, un `--rollback` riporta tutto a uno stato precedente garantito.
È una rete di sicurezza **strutturale**, non comportamentale.

---

## Evoluzione (Step 4+: multi-AI)

Quando SOLEM ospiterà più AI (GAVIO + specialiste + extension marketplace),
introdurremo:

- **Per-AI capabilities manifest**: ogni AI dichiara cosa vuole fare
- **Per-utente per-AI permission grants**: l'utente approva *cosa quella AI
  può fare nel suo universo*
- **Polkit rules dinamiche**: generate dai manifest + grants
- **AppArmor profile per L7 extension** (sandboxing terze parti)

GAVIO resterà sempre **AI primaria** con privilegi pieni — è la sola che
parla direttamente con l'utente. Le altre lavorano *sotto* GAVIO.
