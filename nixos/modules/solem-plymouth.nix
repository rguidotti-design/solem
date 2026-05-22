{ config, pkgs, lib, ... }:

# SOLEM PLYMOUTH — boot splash branded (navy + Cormorant + animated S).
#
# Single responsibility: SOLO orchestrazione tema Plymouth (script type)
# + override silent boot. Niente logica generic boot (è in NixOS core).
#
# Tema:
#   - background navy gradient (#0a1628 → #050912)
#   - logo "S" Cormorant gold (#c9a961) al centro, fade-in + glow pulse
#   - thin progress bar gold sotto
#   - tagline "AI-NATIVE OS" letter-spacing in basso
#
# 100% FOSS, scriptato in Plymouth Script (sintassi ECMAScript-like).

let
  cfg = config.solem.plymouth;

  solemTheme = pkgs.runCommand "plymouth-theme-solem" {
    nativeBuildInputs = [ pkgs.librsvg pkgs.imagemagick ];
  } ''
    mkdir -p $out/share/plymouth/themes/solem

    # ── Background navy gradient 1920x1080 ──
    magick -size 1920x1080 \
      radial-gradient:'#1a2840'-'#050912' \
      $out/share/plymouth/themes/solem/background.png

    # ── Logo "S" gold via SVG ──
    cat > /tmp/logo.svg <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="400" height="400" viewBox="0 0 400 400">
  <text x="200" y="280" text-anchor="middle"
        font-family="Cormorant Garamond, Georgia, serif"
        font-size="300" font-weight="300"
        fill="#c9a961" letter-spacing="6">S</text>
</svg>
SVG
    rsvg-convert -w 400 -h 400 -o $out/share/plymouth/themes/solem/logo.png /tmp/logo.svg

    # ── Progress box (gold thin rectangle) ──
    magick -size 300x4 xc:'#c9a961' $out/share/plymouth/themes/solem/progress-box.png

    # ── Progress bar fill ──
    magick -size 4x4 xc:'#e0c585' $out/share/plymouth/themes/solem/progress-bar.png

    # ── Tagline ──
    cat > /tmp/tagline.svg <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="500" height="60" viewBox="0 0 500 60">
  <text x="250" y="40" text-anchor="middle"
        font-family="Inter, sans-serif"
        font-size="18" letter-spacing="14"
        fill="#7a8a9a">AI-NATIVE OS</text>
</svg>
SVG
    rsvg-convert -w 500 -h 60 -o $out/share/plymouth/themes/solem/tagline.png /tmp/tagline.svg

    # ── Plymouth script ──
    cat > $out/share/plymouth/themes/solem/solem.script <<'PLY'
# SOLEM Plymouth Script — navy + Cormorant gold

# Background sfumato
Window.SetBackgroundTopColor(0.039, 0.086, 0.157);
Window.SetBackgroundBottomColor(0.020, 0.035, 0.071);

bg = Image("background.png");
bg_sprite = Sprite(bg);
bg_sprite.SetX(Window.GetWidth()  / 2 - bg.GetWidth()  / 2);
bg_sprite.SetY(Window.GetHeight() / 2 - bg.GetHeight() / 2);
bg_sprite.SetZ(-100);

# Logo "S" centrale
logo = Image("logo.png");
logo_sprite = Sprite(logo);
logo_x = Window.GetWidth()  / 2 - logo.GetWidth()  / 2;
logo_y = Window.GetHeight() / 2 - logo.GetHeight() / 2 - 60;
logo_sprite.SetX(logo_x);
logo_sprite.SetY(logo_y);
logo_sprite.SetOpacity(0);

# Tagline
tag = Image("tagline.png");
tag_sprite = Sprite(tag);
tag_sprite.SetX(Window.GetWidth() / 2 - tag.GetWidth() / 2);
tag_sprite.SetY(Window.GetHeight() / 2 + 180);
tag_sprite.SetOpacity(0);

# Progress box (cornice statica)
pbox = Image("progress-box.png");
pbox_sprite = Sprite(pbox);
pbox_x = Window.GetWidth() / 2 - pbox.GetWidth() / 2;
pbox_y = Window.GetHeight() / 2 + 130;
pbox_sprite.SetX(pbox_x);
pbox_sprite.SetY(pbox_y);
pbox_sprite.SetOpacity(0);

# Progress bar (riempimento)
pbar = Image("progress-bar.png");
pbar_sprite = Sprite();
pbar_sprite.SetX(pbox_x);
pbar_sprite.SetY(pbox_y);

# Fade-in iniziale + pulse logo
fun refresh_callback ()
{
    t = Plymouth.GetMicrosecondsSinceBootStart() / 1000000.0;
    # Logo fade-in primi 0.8s
    fade = Math.Min(t / 0.8, 1.0);
    logo_sprite.SetOpacity(fade);
    tag_sprite.SetOpacity(fade);
    pbox_sprite.SetOpacity(fade * 0.7);
    # Pulse glow ogni 2s
    pulse = 0.85 + 0.15 * Math.Cos(t * 3.14);
    logo_sprite.SetOpacity(fade * pulse);
}
Plymouth.SetRefreshFunction(refresh_callback);

# Progress callback
fun progress_callback (duration, progress)
{
    w = pbox.GetWidth() * progress;
    bar = pbar.Scale(w, pbar.GetHeight());
    pbar_sprite.SetImage(bar);
}
Plymouth.SetBootProgressFunction(progress_callback);

# Quit fade-out
fun quit_callback ()
{
    logo_sprite.SetOpacity(0);
    tag_sprite.SetOpacity(0);
    pbox_sprite.SetOpacity(0);
}
Plymouth.SetQuitFunction(quit_callback);
PLY

    # ── Theme manifest ──
    cat > $out/share/plymouth/themes/solem/solem.plymouth <<EOF
[Plymouth Theme]
Name=SOLEM
Description=Navy + Cormorant gold boot splash
ModuleName=script

[script]
ImageDir=$out/share/plymouth/themes/solem
ScriptFile=$out/share/plymouth/themes/solem/solem.script
EOF
  '';
in {
  options.solem.plymouth = {
    enable = lib.mkEnableOption "Plymouth boot splash branded SOLEM";
  };

  config = lib.mkIf cfg.enable {
    boot.plymouth = {
      enable = true;
      theme = "solem";
      themePackages = [ solemTheme ];
    };

    # Silent boot per dare risalto al tema
    boot.kernelParams = [
      "quiet"
      "splash"
      "loglevel=3"
      "rd.systemd.show_status=false"
      "rd.udev.log_level=3"
      "udev.log_priority=3"
      "vt.global_cursor_default=0"
    ];

    boot.consoleLogLevel = lib.mkDefault 0;
    boot.initrd.verbose = false;
  };
}
