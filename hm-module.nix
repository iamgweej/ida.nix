{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.ida;
  inherit (lib) mkOption types;

  finalPackage = cfg.package.override {
    inherit (cfg) idaDir extraLibs extraPythonPackages;
    idaPython = cfg.python;
  };
in
{
  options.programs.ida = {
    enable = lib.mkEnableOption "IDA Pro wrappers (requires `programs.nix-ld.enable` on the NixOS side)";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ./package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ./package.nix { }";
      description = "Base wrapper package; the options below are applied via `.override`.";
    };

    finalPackage = mkOption {
      type = types.package;
      readOnly = true;
      default = finalPackage;
      description = "The wrapper package with all options applied.";
    };

    idaDir = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/home/me/ida-pro-9.2";
      description = "IDA install directory. null = auto-detect at runtime (or `$IDADIR`).";
    };

    python = mkOption {
      type = types.package;
      default = pkgs.python314;
      defaultText = lib.literalExpression "pkgs.python314";
      description = "Interpreter used for IDAPython.";
    };

    extraPythonPackages = mkOption {
      type = types.functionTo (types.listOf types.package);
      default = ps: [ ];
      defaultText = lib.literalExpression "ps: [ ]";
      example = lib.literalExpression "ps: [ ps.capstone ps.keystone-engine ]";
      description = "Python packages available to IDAPython plugins.";
    };

    extraLibs = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = "Extra libraries added to IDA's runtime library path.";
    };

    desktopEntry = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to create an IDA Pro desktop entry.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ finalPackage ];

    xdg.desktopEntries.ida = lib.mkIf cfg.desktopEntry (
      {
        name = "IDA Pro";
        genericName = "Disassembler";
        exec = "ida %f";
        terminal = false;
        categories = [ "Development" ];
      }
      # The icon ships with IDA, so it is only known when idaDir is fixed.
      // lib.optionalAttrs (cfg.idaDir != null) { icon = "${cfg.idaDir}/appico.png"; }
    );
  };
}
