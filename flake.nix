{
  inputs = {
    nixpkgs.url = "github:abbradar/nixpkgs/ugractf";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }: {
    overlays.default = final: prev: {
      deploy-bot = import ./shell.nix { pkgs = self; };
    };

    nixosModules.default.imports = [
      ({ pkgs, ... }: {
        nixpkgs.overlays = [ self.overlays.default ];
      })
      ./module.nix
    ];
  } // flake-utils.lib.eachDefaultSystem (system:
    let
       pkgs = import nixpkgs { inherit system; };
       pkg = import ./shell.nix { inherit pkgs; };
    in {
      devShells.default = nixpkgs.lib.overrideDerivation pkg (drv: {
        NIX_PATH = "nixpkgs=${nixpkgs}";
      });
      packages.default = pkg;
    });
}
