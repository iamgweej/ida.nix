{
  description = "Wrappers for a manually installed IDA Pro (nix-ld, no network)";

  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixpkgs-unstable/nixexprs.tar.zst";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      # Override with e.g.
      #   ida.packages.${system}.default.override {
      #     extraPythonPackages = ps: [ ps.capstone ];
      #     idaDir = "/home/me/ida-pro-9.2";
      #   }
      packages = forAllSystems (pkgs: rec {
        ida = pkgs.callPackage ./package.nix { };
        default = ida;
      });

      overlays.default = final: prev: {
        ida-wrapped = final.callPackage ./package.nix { };
      };

      homeModules.default = ./hm-module.nix;

      apps = forAllSystems (
        pkgs:
        let
          p = self.packages.${pkgs.stdenv.hostPlatform.system}.ida;
        in
        {
          default = self.apps.${pkgs.stdenv.hostPlatform.system}.ida;
          ida = {
            type = "app";
            program = "${p}/bin/ida";
            meta.description = "IDA Pro, network-sandboxed";
          };
          ida-env = {
            type = "app";
            program = "${p}/bin/ida-env";
            meta.description = "Run a command in the IDA runtime environment";
          };
          ida-pyswitch = {
            type = "app";
            program = "${p}/bin/ida-pyswitch";
            meta.description = "Point IDAPython at the flake interpreter";
          };
        }
      );
    };
}
