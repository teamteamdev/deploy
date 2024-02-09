{
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:abbradar/nixpkgs/ugractf";
    poetry2nix.url = "github:nix-community/poetry2nix";
    poetry2nix.inputs.nixpkgs.follows = "nixpkgs";
    alejandra.url = "github:kamadorueda/alejandra";
    alejandra.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    poetry2nix,
    flake-utils,
    alejandra,
  }:
    {
      overlays.default = final: prev: {
        deploy-bot = final.python3.pkgs.callPackage ./. {};
      };

      nixosModules.default.imports = [
        ({pkgs, ...}: {
          nixpkgs.overlays = [self.overlays.default];
        })
        ./module.nix
      ];
    }
    // flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {
        inherit system;
        overlays = [self.overlays.default alejandra.overlays.default poetry2nix.overlays.default];
      };
    in {
      packages.default = pkgs.deploy-bot;
      formatter = pkgs.alejandra;
    });
}
