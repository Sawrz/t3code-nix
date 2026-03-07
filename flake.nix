{
  description = "Nix flake for the T3 Code CLI";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      overlay = final: prev: {
        t3 = final.callPackage ./package.nix { };
        t3code = final.t3;
      };
      mkT3App = drv: {
        type = "app";
        program = "${drv}/bin/t3";
        meta = drv.meta;
      };
    in
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ overlay ];
        };
      in
      {
        packages = {
          default = pkgs.t3;
          t3 = pkgs.t3;
          t3code = pkgs.t3code;
        };

        apps = {
          default = mkT3App pkgs.t3;
          t3 = mkT3App pkgs.t3;
          t3code = mkT3App pkgs.t3code;
        };

        checks = {
          t3-build = pkgs.t3;
          t3-help = pkgs.runCommand "t3-help" { } ''
            ${pkgs.t3}/bin/t3 --help > "$out"
          '';
        };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            jq
            nodejs_22
            nixpkgs-fmt
          ];
        };
      }
    )
    // {
      overlays.default = overlay;
    };
}
