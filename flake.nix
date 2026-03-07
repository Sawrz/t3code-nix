{
  description = "Nix flake for the T3 Code desktop app and CLI";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      overlay = final: prev: {
        t3code = final.callPackage ./package.nix { };
        t3code-desktop = final.t3code;
        t3code-cli = final.callPackage ./package-cli.nix { };
        t3 = final.t3code-cli;
      };
      mkApp = drv: binary: {
        type = "app";
        program = "${drv}/bin/${binary}";
        meta = drv.meta;
      };
    in
    flake-utils.lib.eachDefaultSystem
      (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ overlay ];
          };
        in
        {
          packages = {
            default = pkgs.t3code;
            t3code = pkgs.t3code;
            t3code-desktop = pkgs.t3code-desktop;
            t3code-cli = pkgs.t3code-cli;
            t3 = pkgs.t3;
          };

          apps = {
            default = mkApp pkgs.t3code "t3code";
            t3code = mkApp pkgs.t3code "t3code";
            t3code-desktop = mkApp pkgs.t3code-desktop "t3code";
            t3code-cli = mkApp pkgs.t3code-cli "t3";
            t3 = mkApp pkgs.t3 "t3";
          };

          checks = {
            t3code-build = pkgs.t3code;
            t3-cli-build = pkgs.t3code-cli;
            t3-cli-help = pkgs.runCommand "t3-cli-help" { } ''
              ${pkgs.t3code-cli}/bin/t3 --help > "$out"
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
