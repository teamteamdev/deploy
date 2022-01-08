{
  inputs = {
    nixpkgs.url = "github:abbradar/nixpkgs/ugractf";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }: {
    overlay = self: super: {
      deploy-bot = import ./shell.nix { pkgs = self; };
    };

    nixosModules = [
      ({ pkgs, ... }: {
        nixpkgs.overlays = [ self.overlay ];
      })
      ./module.nix
    ];
  } // flake-utils.lib.eachDefaultSystem (system:
    let
       pkgs = import nixpkgs { inherit system; };
       pkg = import ./shell.nix { inherit pkgs; };
    in {
      devShell = nixpkgs.lib.overrideDerivation pkg (drv: {
        NIX_PATH = "nixpkgs=${nixpkgs}";
      });
      defaultPackage = pkg;
    });
}
