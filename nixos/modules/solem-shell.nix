{ config, pkgs, lib, ... }:

let
  cfg = config.solem.shell;

  # TUI scritta in Python (zero deps, solo stdlib curses) — il "SOLEM Shell"
  # che sostituisce bash come prima esperienza utente al login.
  # Filosofia spec: "il vero shell di SOLEM è la conversazione con l'AI".
  solemShellTUI = pkgs.writers.writePython3Bin "solem-shell" {
    flakeIgnore = [
      "E501" "E741" "E226" "E231" "W291" "W293" "E402" "F401"
      "E241" "E272" "E701" "E702" "E211" "E261" "E302" "E305" "E303" "E306"
    ];
  } ''
    """solem-shell — TUI full-screen di SOLEM (palette navy + oro).

    Layout (curses):
      ┌─ SOLEM ──────────────────── status ──┐
      │ [pannello 1: stato sistema]          │
      │ [pannello 2: layer status]           │
      │ [pannello 3: ultimi eventi event-bus]│
      │ [pannello 4: tip comandi]            │
      └──────────────────────────────────────┘
       prompt > _

    Tasti: q = esci a bash · r = refresh · g = chat con GAVIO · h = help
    """
    from __future__ import annotations
    import curses
    import json
    import os
    import sys
    import time
    import urllib.request
    import urllib.error

    API = "http://127.0.0.1:8001"

    # Color pairs (init in main)
    C_TITLE = 1
    C_LABEL = 2
    C_VALUE = 3
    C_OK = 4
    C_DOWN = 5
    C_BORDER = 6
    C_HINT = 7

    def api_get(path, timeout=2.0):
        try:
            with urllib.request.urlopen(API + path, timeout=timeout) as r:
                return json.loads(r.read())
        except Exception:
            return None

    def draw_header(win, manifest):
        h, w = win.getmaxyx()
        win.attron(curses.color_pair(C_TITLE) | curses.A_BOLD)
        title = "  SOLEM  "
        win.addstr(0, 0, title)
        win.attroff(curses.color_pair(C_TITLE) | curses.A_BOLD)

        win.attron(curses.color_pair(C_LABEL))
        if manifest:
            sub = f"v{manifest.get('version','?')}  ·  {manifest.get('profile','minimal')}  ·  {manifest.get('primary_ai','gavio')}"
        else:
            sub = "connecting to solem-api…"
        win.addstr(0, len(title), sub)
        win.attroff(curses.color_pair(C_LABEL))

        # Time on right
        ts = time.strftime("%a %d %b %Y · %H:%M:%S")
        try:
            win.addstr(0, max(0, w - len(ts) - 2), ts)
        except curses.error:
            pass

        # Underline
        win.attron(curses.color_pair(C_BORDER))
        try:
            win.hline(1, 0, curses.ACS_HLINE, w)
        except curses.error:
            pass
        win.attroff(curses.color_pair(C_BORDER))

    def fmt_uptime(s):
        if not s:
            return "—"
        d, s = divmod(s, 86400)
        h, s = divmod(s, 3600)
        m, _ = divmod(s, 60)
        if d:
            return f"{d}d {h}h {m}m"
        if h:
            return f"{h}h {m}m"
        return f"{m}m"

    def draw_panel(win, y, x, h, w, title):
        win.attron(curses.color_pair(C_BORDER))
        try:
            win.addstr(y, x, "┌─ ")
            win.addstr(y, x + 3, title, curses.color_pair(C_TITLE) | curses.A_BOLD)
            rem = w - 4 - len(title)
            if rem > 0:
                win.addstr(y, x + 4 + len(title), " " + "─" * (rem - 1) + "┐")
            for r in range(1, h - 1):
                win.addstr(y + r, x, "│")
                win.addstr(y + r, x + w - 1, "│")
            win.addstr(y + h - 1, x, "└" + "─" * (w - 2) + "┘")
        except curses.error:
            pass
        win.attroff(curses.color_pair(C_BORDER))

    def put(win, y, x, label, value, ok=None):
        try:
            win.attron(curses.color_pair(C_LABEL))
            win.addstr(y, x, f"{label:<16}")
            win.attroff(curses.color_pair(C_LABEL))
            color = C_VALUE
            if ok is True:
                color = C_OK
            elif ok is False:
                color = C_DOWN
            win.attron(curses.color_pair(color))
            win.addstr(y, x + 16, str(value))
            win.attroff(curses.color_pair(color))
        except curses.error:
            pass

    def draw_status_panel(win, manifest, y, x, h, w):
        draw_panel(win, y, x, h, w, "STATO SISTEMA")
        if not manifest:
            try:
                win.addstr(y + 2, x + 2, "solem-api non raggiungibile", curses.color_pair(C_DOWN))
            except curses.error:
                pass
            return
        rt = manifest.get("runtime", {})
        put(win, y + 2, x + 2, "profilo", manifest.get("profile", "?"))
        put(win, y + 3, x + 2, "step",    manifest.get("step", "?"))
        put(win, y + 4, x + 2, "uptime",  fmt_uptime(rt.get("uptime_seconds", 0)))
        put(win, y + 5, x + 2, "memoria", f"{rt.get('memory_mb', 0)} MB")
        put(win, y + 6, x + 2, "disco lib.", f"{rt.get('disk_free_gb', 0)} GB")
        active = rt.get("active_services", [])
        put(win, y + 7, x + 2, "servizi up", f"{len(active)}")

    def draw_layers_panel(win, manifest, y, x, h, w):
        draw_panel(win, y, x, h, w, "LAYER L1-L7")
        if not manifest:
            return
        layers = manifest.get("layers", [])
        for i, layer in enumerate(layers):
            row = y + 2 + i
            if row >= y + h - 1:
                break
            status = layer.get("status", "?")
            ok = (status == "active")
            partial = (status == "partial")
            try:
                win.attron(curses.color_pair(C_LABEL))
                win.addstr(row, x + 2, f"{layer['layer']}  {layer['name']:<22}")
                win.attroff(curses.color_pair(C_LABEL))
                color = C_OK if ok else (C_VALUE if partial else C_DOWN)
                win.attron(curses.color_pair(color))
                win.addstr(row, x + 28, status)
                win.attroff(curses.color_pair(color))
            except curses.error:
                pass

    def draw_modules_panel(win, manifest, y, x, h, w):
        draw_panel(win, y, x, h, w, "MODULI RUNTIME")
        if not manifest:
            return
        modules = manifest.get("modules", {})
        for i, (name, active) in enumerate(modules.items()):
            row = y + 2 + i
            if row >= y + h - 1:
                break
            put(win, row, x + 2, name, "● up" if active else "○ down", ok=active)

    def draw_hints_panel(win, y, x, h, w):
        draw_panel(win, y, x, h, w, "COMANDI")
        hints = [
            "q   esci a bash",
            "r   refresh manuale",
            "g   chat con GAVIO (futuro)",
            "s   dashboard web :8001",
            "h   help completo",
            "i   identity (l1)",
            "p   pair device (mesh)",
        ]
        for i, hint in enumerate(hints):
            row = y + 2 + i
            if row >= y + h - 1:
                break
            try:
                win.attron(curses.color_pair(C_HINT))
                win.addstr(row, x + 2, hint)
                win.attroff(curses.color_pair(C_HINT))
            except curses.error:
                pass

    def draw_footer(win, w):
        try:
            h, _ = win.getmaxyx()
            footer = " SOLEM TUI · q=esci · r=refresh · h=help "
            win.attron(curses.color_pair(C_LABEL))
            win.addstr(h - 1, 0, footer[:w - 1])
            win.attroff(curses.color_pair(C_LABEL))
        except curses.error:
            pass

    def main_loop(stdscr):
        curses.curs_set(0)
        curses.start_color()
        curses.use_default_colors()

        # Palette navy/oro/ghiaccio
        # 4: ghiaccio bianco; 3: oro; 1: navy bg → testo
        curses.init_pair(C_TITLE,  214, -1)  # oro
        curses.init_pair(C_LABEL,  246, -1)  # grigio chiaro
        curses.init_pair(C_VALUE,  255, -1)  # bianco
        curses.init_pair(C_OK,     42,  -1)  # verde
        curses.init_pair(C_DOWN,   167, -1)  # rosso soft
        curses.init_pair(C_BORDER, 67,  -1)  # navy
        curses.init_pair(C_HINT,   180, -1)  # oro chiaro

        stdscr.nodelay(True)
        last_refresh = 0
        manifest = None

        while True:
            now = time.time()
            if now - last_refresh > 5:
                manifest = api_get("/solem/manifest")
                last_refresh = now

            stdscr.erase()
            h, w = stdscr.getmaxyx()
            if h < 24 or w < 80:
                try:
                    stdscr.addstr(0, 0, f"Terminal troppo piccolo ({w}x{h}). Min: 80x24")
                except curses.error:
                    pass
                stdscr.refresh()
                ch = stdscr.getch()
                if ch in (ord("q"), 27):
                    return
                time.sleep(0.2)
                continue

            draw_header(stdscr, manifest)

            # Layout 2x2 grid
            half_h = (h - 3) // 2
            half_w = w // 2

            draw_status_panel(stdscr,  manifest, 2,           0,         half_h,             half_w)
            draw_layers_panel(stdscr,  manifest, 2,           half_w,    half_h,             w - half_w)
            draw_modules_panel(stdscr, manifest, 2 + half_h,  0,         h - 3 - half_h,     half_w)
            draw_hints_panel(stdscr,             2 + half_h,  half_w,    h - 3 - half_h,     w - half_w)

            draw_footer(stdscr, w)
            stdscr.refresh()

            ch = stdscr.getch()
            if ch in (ord("q"), 27):  # q o ESC → esci a bash
                return
            if ch == ord("r"):
                last_refresh = 0  # force refresh
            if ch == ord("s"):
                # apri dashboard in browser locale (se in desktop)
                os.system("xdg-open http://localhost:8001 2>/dev/null &")
            if ch == ord("g"):
                # placeholder: in futuro lancia chat AI
                pass
            if ch == ord("h"):
                stdscr.erase()
                help_text = [
                    "SOLEM Shell — TUI live",
                    "",
                    "Stato e capabilities di SOLEM in tempo reale.",
                    "Polling /solem/manifest ogni 5s.",
                    "",
                    "Tasti:",
                    "  q, ESC    esci a bash",
                    "  r         refresh manuale immediato",
                    "  g         chat GAVIO (Step 2+)",
                    "  s         apri dashboard :8001 nel browser",
                    "  i         identity engine (Step 2+)",
                    "  p         pairing device mesh (Step 2+)",
                    "  h         questa schermata",
                    "",
                    "API: /solem/* (vedi http://localhost:8001/docs per OpenAPI)",
                    "Backend: SQLite /var/lib/solem/solem.db",
                    "",
                    "Premi un tasto per tornare…",
                ]
                for i, line in enumerate(help_text):
                    try:
                        stdscr.addstr(i + 1, 2, line)
                    except curses.error:
                        pass
                stdscr.refresh()
                stdscr.nodelay(False)
                stdscr.getch()
                stdscr.nodelay(True)

            time.sleep(0.1)

    if __name__ == "__main__":
        try:
            curses.wrapper(main_loop)
        except KeyboardInterrupt:
            pass
        print("solem-shell chiuso. shell tradizionale disponibile.")
  '';
in {
  options.solem.shell = {
    enableAsLoginShell = lib.mkEnableOption "Avvia solem-shell TUI automaticamente al login console di gavio";
  };

  config = {
    # Installa il comando `solem-shell` sempre — l'utente lo può lanciare a mano
    environment.systemPackages = [ solemShellTUI ];

    # Auto-launch al login: aggiungi alla fine di .bashrc dell'utente gavio.
    # Usa solo se interactive + login + non già in solem-shell (evita loop).
    programs.bash.interactiveShellInit = lib.mkIf cfg.enableAsLoginShell ''
      # Auto-launch solem-shell come TUI default (paradigma AI-as-shell)
      if [ -z "''${SOLEM_SHELL_LAUNCHED:-}" ] && shopt -q login_shell 2>/dev/null && [ -t 0 ]; then
        export SOLEM_SHELL_LAUNCHED=1
        ${solemShellTUI}/bin/solem-shell || true
        # Dopo l'uscita dalla TUI, l'utente resta in bash normale.
      fi
    '';
  };
}
