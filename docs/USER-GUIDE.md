# SOLEM — Guida utente

Sei al primo giorno con SOLEM. Questa guida ti porta da zero a "uso il PC normalmente" in 15 minuti.

> Non serve sapere niente di Linux/Nix. Tutto è progettato per essere **comandi semplici** in italiano.

---

## 1. Il primo minuto — dimmi cosa vedo

Quando hai SOLEM avviato, vedi 4 cose in alto sullo schermo (waybar):

| Cosa | Significato |
|---|---|
| `I II III IV V` a sinistra | I 5 "spazi di lavoro" (workspace). Cliccaci sopra. |
| Titolo finestra | Cosa stai usando in questo momento |
| Orario centrale | Ora e data |
| `SOLEM` gold a destra | **Badge live**: cambia quando GAVIO/backup/focus è attivo |

In basso, il **dock** con icone cliccabili. La più importante è **G** (GAVIO).

---

## 2. Parlare con GAVIO

GAVIO è la tua AI personale. **L'unica AI** dentro SOLEM.

**3 modi per parlarci:**

### A) Tasto Super (Windows) + Spazio → overlay

Ovunque tu sia, **Super+Space** apre una finestra fluttuante. Scrivi → invio.

### B) Da terminale

```bash
solem ai "scrivimi una mail a Mario per ringraziarlo"
```

### C) Da smartphone / smart glass

Apri sul browser: `http://solem.local:8001/mobile` (o `/glass`).

**Esempi di cosa puoi chiedere:**

- "blocca social per 25 minuti" → focus mode pomodoro
- "fai backup ora" → snapshot encrypted
- "trova le foto del viaggio a Roma" → cerca via vector
- "qual è il device con la GPU libera?" → cluster status
- "spegni tutti i miei device" → coordinated shutdown
- "che ora è in Giappone?" → risposta semplice

---

## 3. Installare un'app

**Non serve aprire terminali strani.** Hai 3 modi:

### A) GUI store (la più semplice)

Clicca su `▦ APPS` nel dock → **GNOME Software** (o KDE Discover).
Cerca → installa → fatto.

### B) Comando rapido

```bash
solem-app browse                              # vedi il catalogo curato (60+ app FOSS)
solem-app search obsidian                     # cerca per nome
solem-app install md.obsidian.Obsidian        # installa
```

### C) Per app Windows (Photoshop, Office vecchio, AutoCAD...)

```bash
solem-wine list                               # 12+ preset Windows pronti
solem-wine apply photoshop-cs6                # prepara il prefix
WINEPREFIX=~/.wine-photoshop-cs6 wine installer.exe
```

---

## 4. I tuoi 5 device sono uno solo

SOLEM ti permette di **paired tutti i tuoi dispositivi** sotto un solo account. Il PC fisso, il laptop, il Raspberry, lo smartphone, gli smart glass: stesso "account SOLEM", stesso GAVIO ovunque.

### Aggiungere un device

Sul PC principale:
```bash
solem pair
```

Ottieni un PIN tipo `A1B2C3D4`. Sull'altro device:

- **Laptop con SOLEM**: `solem-join --pin A1B2C3D4`
- **Smartphone**: apri `http://solem.local:8001/mobile` → Account → inserisci PIN
- **Smart glass**: apri `http://solem.local:8001/glass` → ...

Poi:
```bash
solem cluster                                 # vedi tutti i tuoi device
```

### Cosa succede dopo

GAVIO **smista automaticamente** ogni richiesta al device giusto:
- Chiedi una traduzione veloce → laptop
- Chiedi di analizzare una foto → Jetson (ha la GPU)
- Chiedi di guardare un film → device con video output
- Sei sul glass e chiedi "che ora è" → risposta locale, non passa per il PC

---

## 5. Continuità tra device (handoff)

Stai leggendo un PDF sul PC. Esci di casa. Apri il telefono:

```bash
# Sul PC, manda l'handoff:
solem ai "manda questo PDF al telefono, pagina 17"

# Sul telefono ricevi notifica → 1 tap → si apre dove eri.
```

Niente cloud. Tutto via mesh VPN privata.

---

## 6. Focus + Privacy

### Sessione focus pomodoro

```bash
solem ai "blocca social per 25 minuti"
```

oppure più diretto:
```bash
solemctl focus  # interactive
```

Per 25 min facebook/instagram/twitter/tiktok/reddit sono bloccati a livello DNS. Niente trucchi: il browser non li raggiunge proprio.

### Vedere chi accede al microfono/camera ORA

Dock → `◉ PRIVACY` → vedi processi che usano sensori. Clicca → KILL.

---

## 7. Backup

I backup partono automaticamente ogni notte alle 03:00, encrypted, locali.

```bash
solem backup           # backup adesso (non aspetta la notte)
solem backup history   # quando sono stati fatti
solem backup restore   # ripristina (con conferma)
```

---

## 8. Aggiornamenti

```bash
solem update check     # vedi cosa c'è di nuovo
solem update apply     # applica (richiede riavvio)
solem update rollback  # se qualcosa va storto, torna indietro
```

Il sistema **è atomico**: ogni aggiornamento crea una "generation". Se qualcosa va storto, scegli la precedente dal menu GRUB al boot. **Niente paura di rompere il PC.**

---

## 9. Quando qualcosa non va

### "L'app crasha"
Dock → `S SYSTEM` → vedi servizi attivi. Verde = ok, rosso = problema.

### "GAVIO non risponde"
```bash
solem ai "test"
# Se risponde "GAVIO offline" → fallback locale OK, GAVIO è giù
# Riavvia: sudo systemctl restart gavio
```

### "Non si connette a internet"
Dock → `≋ NETWORK` → vedi DHCP/DNS/devices. Se rosso, prova:
```bash
sudo systemctl restart NetworkManager
```

### "Voglio tornare allo stato di ieri"
Riavvia il PC → al menu GRUB scegli "NixOS - configuration N-1" → enter.

---

## 10. Comandi essenziali (impara solo questi 10)

```bash
solem status        # come stai SOLEM?
solem ai "..."      # parla con GAVIO
solem-app browse    # catalogo app
solem-app install <id>     # installa
solem backup        # backup ora
solem update apply  # aggiorna
solem cluster       # i miei device
solem pair          # aggiungi nuovo device
solem help          # tutti i comandi
solem-doc           # questa guida (offline)
```

---

## 11. Suggerimenti per essere produttivi

- **Cmd+K ovunque sul desktop**: apre una search universale (file, app, comandi, impostazioni)
- **Super+L**: blocca lo schermo subito
- **Super+Spazio**: parla con GAVIO ovunque
- **Stampa**: tasto `PrintScreen` → screenshot automatico in `~/Pictures/solem/`
- **Audio dettatura**: `Super+Ctrl+Spazio` → registra → testo nel campo attivo

---

## 12. Cosa fare DOPO

Quando ti senti a tuo agio:

1. **Aggiungi servizi self-host FOSS** che sostituiscono i SaaS paid: abilita Navidrome (musica, Spotify-alt), Immich (foto, Google Photos-alt), Jellyfin (video, Netflix-alt), Nextcloud (cloud, Drive-alt) dal modulo `solem.selfhost.*` o `solem.photoMusic.*`. **0 €/mese**.
2. **Compra un Raspberry Pi** e usalo come worker AI in casa: `nix build .#raspberry` + flash SD.
3. **Vai sul GitHub** del progetto per partecipare: https://github.com/rguidotti-design/solem

---

## Aiuto

- Lancia `solem help` da terminale per la lista comandi
- Apri questa guida con `solem-doc`
- Sul GitHub apri issue per problemi: https://github.com/rguidotti-design/solem/issues
- L'API di SOLEM è OpenAPI documentata: `http://localhost:8001/docs`

---

**Non hai capito qualcosa?** Chiedi a GAVIO:
```bash
solem ai "come si fa a installare Photoshop?"
```

Lui legge questa guida e te lo spiega meglio di me.
