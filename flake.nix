{
  inputs = {
    nixpkgs.url = "github:abbradar/nixpkgs/ugractf";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }: {
    overlays.default = final: prev: {
      deploy-bot = final.python3.pkgs.callPackage ./. { };
    };

    nixosModules.default.imports = [
      ({ pkgs, ... }: {
        nixpkgs.overlays = [ self.overlays.default ];
      })
      ./module.nix
    ];
  } // flake-utils.lib.eachDefaultSystem (system:
    let
       pkgs = import nixpkgs {
         inherit system;
         overlays = [ self.overlays.default ];
        };
    in {
      packages.default = pkgs.deploy-bot;
    });
}
