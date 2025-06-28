{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-utils.url = "github:numtide/flake-utils";

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      uv2nix,
      pyproject-nix,
      pyproject-build-systems,
      flake-utils,
      ...
    }:
    let
      pythonPkg = "python313";
    in
    {
      overlays.default = (
        final: prev:
        let
          pkgs = import nixpkgs {
            system = final.system;
          };
          lib = nixpkgs.lib;
          python = pkgs."${pythonPkg}";
        in
        {
          gh-deploy =
            let
              workspace = uv2nix.lib.workspace.loadWorkspace {
                workspaceRoot = ./.;
              };

              overlay = workspace.mkPyprojectOverlay {
                sourcePreference = "wheel";
              };

              pythonSet =
                (pkgs.callPackage pyproject-nix.build.packages {
                  inherit python;
                }).overrideScope
                  (
                    lib.composeManyExtensions [
                      pyproject-build-systems.overlays.default
                      overlay
                    ]
                  );
            in
            pythonSet.mkVirtualEnv "gh-deploy" workspace.deps.default;
        }
      );

      nixosModules.default.imports = [
        (import ./module.nix self.packages)
      ];
    }
    // flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ self.overlays.default ];
        };

        python = pkgs."${pythonPkg}";
      in
      {
        packages = {
          default = pkgs.gh-deploy;
          gh-deploy = pkgs.gh-deploy;
        };
        formatter = pkgs.nixfmt-tree;
        devShells.default = pkgs.mkShell {
          packages = [
            python
            pkgs.uv
            pkgs.nixfmt-rfc-style
            pkgs.ruff
          ];
        };
      }
    );

}
