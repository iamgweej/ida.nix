{
  lib,
  pkgs,
  stdenv,
  writeShellScriptBin,
  symlinkJoin,
  bubblewrap,
  coreutils,
  python314,

  # Interpreter used for IDAPython, idalib and `ida-env python`.
  idaPython ? python314,
  # Extra packages for that interpreter, e.g. `ps: [ ps.capstone ps.pwntools ]`.
  extraPythonPackages ? (ps: [ ]),
  # Fixed IDA install dir. null = discover at runtime (see `findIdaDir` below).
  idaDir ? null,
  # Extra libraries to put on the runtime library path.
  extraLibs ? [ ],
}:

let
  pythonEnv = idaPython.withPackages extraPythonPackages;
  pyVer = idaPython.pythonVersion;

  libs =
    (with pkgs; [
      stdenv.cc.cc.lib
      zlib
      bzip2
      xz
      zstd
      expat
      libffi
      libxcrypt
      openssl
      krb5
      util-linux.lib # libuuid
      glib
      dbus
      fontconfig
      freetype
      libGL
      libglvnd
      libdrm
      libxkbcommon
      wayland
      xcb-util-cursor # required by Qt >= 6.5 xcb plugin
    ])
    ++ (with pkgs; [
      libx11
      libxcb
      libxext
      libxrender
      libxi
      libxcursor
      libxrandr
      libxfixes
      libxau
      libxdmcp
      libsm
      libice
      libxcb-util
      libxcb-wm
      libxcb-image
      libxcb-keysyms
      libxcb-render-util
    ])
    ++ extraLibs;

  libPath = lib.makeLibraryPath libs;

  # Sourced by every wrapper. Sets IDADIR and the nix-ld environment.
  prelude = ''
    set -euo pipefail
    shopt -s nullglob

    findIdaDir() {
      ${lib.optionalString (idaDir != null) ''
        echo ${lib.escapeShellArg idaDir}; return
      ''}
      local candidates=(
        "$HOME"/ida-pro-* "$HOME"/idapro-* "$HOME"/ida-* \
        /opt/ida-pro-* /opt/idapro-* /opt/ida-*
      )
      local best=""
      if (( ''${#candidates[@]} )); then
        best=$(printf '%s\n' "''${candidates[@]}" | ${coreutils}/bin/sort -V | while read -r d; do
          if [ -x "$d/ida" ]; then echo "$d"; fi
        done | ${coreutils}/bin/tail -n1)
      fi
      echo "$best"
    }

    IDADIR="''${IDADIR:-$(findIdaDir)}"
    if [ -z "$IDADIR" ] || [ ! -x "$IDADIR/ida" ]; then
      echo "ida.nix: could not find an IDA installation (set IDADIR=/path/to/ida)" >&2
      exit 1
    fi
    export IDADIR

    # Force our own glibc loader so the libs below always match it,
    # regardless of what the system-wide nix-ld points at.
    export NIX_LD=${stdenv.cc.bintools.dynamicLinker}
    export NIX_LD_LIBRARY_PATH=${libPath}

    # Host Qt settings would make IDA's bundled Qt load incompatible plugins.
    unset QT_PLUGIN_PATH QML2_IMPORT_PATH QML_IMPORT_PATH QT_QPA_PLATFORMTHEME
    export QT_QPA_PLATFORM="''${IDA_QPA_PLATFORM:-xcb}"

    # Stable path for the libpython IDA records in ida.reg, so it survives GC
    # of old store paths. Refreshed on every launch.
    pyLinkDir="''${XDG_STATE_HOME:-$HOME/.local/state}/ida-nix"
    pyLink="$pyLinkDir/libpython${pyVer}.so"
    ${coreutils}/bin/mkdir -p "$pyLinkDir"
    ${coreutils}/bin/ln -sfn ${pythonEnv}/lib/libpython${pyVer}.so "$pyLink"

    # No network: keeps Lumina, update checks and decompiler cloud quiet.
    # IDA_ALLOW_NET=1 opts out (e.g. `IDA_ALLOW_NET=1 ida-env pip install ...`).
    sandbox() {
      if [ "''${IDA_ALLOW_NET:-0}" = 1 ]; then
        exec "$@"
      fi
      exec ${bubblewrap}/bin/bwrap --dev-bind / / --unshare-net --die-with-parent -- "$@"
    }
  '';

  ida = writeShellScriptBin "ida" ''
    ${prelude}
    # IDAPython runs on the flake's interpreter (extraPythonPackages), not on
    # whatever venv/direnv happens to be active in the launching shell.
    export PYTHONHOME=${pythonEnv}
    export PATH=${pythonEnv}/bin:$PATH
    unset PYTHONPATH VIRTUAL_ENV
    sandbox "$IDADIR/ida" "$@"
  '';

  ida-env = writeShellScriptBin "ida-env" ''
    ${prelude}
    if [ $# -eq 0 ]; then
      echo "usage: ida-env <command> [args...]   e.g. ida-env python script.py (uses your own python/venv)" >&2
      exit 1
    fi
    # Non-nix-ld processes (python loading libidalib.so) need the plain var.
    export LD_LIBRARY_PATH="${libPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    sandbox "$@"
  '';

  ida-pyswitch = writeShellScriptBin "ida-pyswitch" ''
    ${prelude}
    # No args: point IDA at this flake's python (via the stable symlink).
    if [ $# -eq 0 ]; then
      set -- --force-path "$pyLink"
    fi
    sandbox "$IDADIR/idapyswitch" "$@"
  '';
in
symlinkJoin {
  name = "ida-wrapped";
  paths = [
    ida
    ida-env
    ida-pyswitch
  ];
  passthru = {
    inherit
      ida
      ida-env
      ida-pyswitch
      pythonEnv
      libPath
      ;
  };
  meta = {
    description = "nix-ld + bwrap wrappers for a manually installed IDA Pro";
    platforms = lib.platforms.linux;
    mainProgram = "ida";
  };
}
