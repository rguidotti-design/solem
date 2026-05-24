{ config, pkgs, lib, ... }:

# SOLEM MAKERS — 3D printing + CAD + GIS + Education + Electronics.
#
# Single responsibility: SOLO toolkit "maker/scientist" FOSS:
# - 3D printing slicer (PrusaSlicer, OrcaSlicer, Cura)
# - CAD parametrico (FreeCAD, OpenSCAD, Build123d) e mesh (Blender)
# - GIS (QGIS, GRASS, JOSM per OpenStreetMap)
# - Scienza/Math (Octave, Maxima, Wxmaxima, R, Sage)
# - Education (GCompris, Stellarium, Celestia, Kalzium, Scratch)
# - Electronics (KiCad, ngspice, Wireshark, Sigrok PulseView)
#
# Tutto FOSS, 0 €.

let
  cfg = config.solem.makers;
in {
  options.solem.makers = {
    printing3d = lib.mkEnableOption "3D printing slicer FOSS (PrusaSlicer + OrcaSlicer + Cura)";
    cad        = lib.mkEnableOption "CAD parametrico FOSS (FreeCAD + OpenSCAD + LibreCAD)";
    gis        = lib.mkEnableOption "GIS FOSS (QGIS + GRASS + JOSM + Marble)";
    science    = lib.mkEnableOption "Math/Scienza FOSS (Octave + Maxima + R + Sage)";
    education  = lib.mkEnableOption "Education FOSS (GCompris + Stellarium + Kalzium + Scratch)";
    electronics = lib.mkEnableOption "Electronics FOSS (KiCad + ngspice + Wireshark + PulseView)";
  };

  config = lib.mkIf (cfg.printing3d || cfg.cad || cfg.gis || cfg.science || cfg.education || cfg.electronics) {
    environment.systemPackages = with pkgs; lib.flatten [

      (lib.optionals cfg.printing3d [
        prusa-slicer
        orca-slicer
        # cura-appimage: pacchetto rimosso in 24.11 (usa flatpak install com.ultimaker.cura)
        # super-slicer: pacchetto rimosso in 24.11 (usa AppImage o Flatpak)
        openscad          # CAD parametrico script
        slic3r            # original slicer FOSS
      ])

      (lib.optionals cfg.cad [
        freecad           # CAD parametrico full-stack
        librecad          # 2D CAD
        openscad
        kicad             # PCB layout (sotto electronics ma utile qui)
        solvespace        # CAD parametrico 3D leggero
      ])

      (lib.optionals cfg.gis [
        qgis              # GIS desktop completo
        grass             # GIS analytics + raster/vector
        josm              # OpenStreetMap editor (Java, GPL)
        marble            # globe + atlas KDE
        gpsbabel          # convertitore traccia GPS
        gdal              # geo CLI library
      ])

      (lib.optionals cfg.science [
        octaveFull        # Matlab-alt
        maxima            # algebra simbolica
        wxmaxima
        gnuplot
        R                 # statistica
        sage              # math system (Python-based)
        scilab-bin        # Matlab-alt alternativo
        geogebra          # math GUI (educational)
      ])

      (lib.optionals cfg.education [
        gcompris          # 100+ giochi educativi
        stellarium        # planetario
        celestia          # simulatore spaziale
        kalzium           # tavola periodica KDE
        kalgebra
        marble
        # tuxmath           # math arcade (può non essere in 24.11)
        ktouch            # tocca-dattilo
        klavaro
        anki              # SRS (anche in solem-readers)
      ])

      (lib.optionals cfg.electronics [
        kicad
        ngspice
        gnuradio
        wireshark
        sigrok-cli
        pulseview
        gerbv             # gerber viewer
        fritzing          # circuit prototyping
        gtkwave           # waveform viewer
      ])
    ];

    # Permessi seriale per chi usa 3D printer / Arduino
    users.groups.dialout = lib.mkIf (cfg.printing3d || cfg.electronics) {};
  };
}
