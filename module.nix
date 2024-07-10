{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.services.deploy-bot;

  deployConfig = {
    GITHUB_SECRET = "REPLACE_BY_GITHUB_SECRET";
    PROJECTS =
      mapAttrsToList (path: project: {
        inherit (project) repo branch timeout;
        inherit path;
        cmd = pkgs.writeScript "deploy.sh" ''
          #!${pkgs.stdenv.shell} -e
          ${project.script}
        '';
      })
      cfg.projects;
  };

  configFile = pkgs.writeText "config.json" (builtins.toJSON deployConfig);

  gunicornPkg = pkgs.deploy-bot.dependencyEnv.override {
    app = pkgs.deploy-bot.overridePythonAttrs (self: {
      propagatedBuildInputs = self.propagatedBuildInputs or [] ++ [pkgs.deploy-bot.python.pkgs.gunicorn];
    });
  };

  binPkgs = with pkgs;
    [git git-lfs openssh bash]
    ++ optional cfg.docker pkgs.docker
    ++ cfg.path;

  projectOpts = {
    options = {
      repo = mkOption {
        type = types.str;
        description = "Repository owner and name.";
        example = "teamteamdev/kyzylborda";
      };

      branch = mkOption {
        type = types.str;
        description = "Branch name.";
        default = "master";
      };

      timeout = mkOption {
        type = types.int;
        description = "Build timeout.";
        default = 120;
      };

      script = mkOption {
        type = types.lines;
        description = "Script to execute.";
        default = "";
      };
    };
  };

  maxTimeout = max (mapAttrsToList (name: proj: proj.timeout) cfg.projects) + 15;
in {
  options = {
    services.deploy-bot = {
      enable = mkEnableOption "deploy bot";

      docker = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Docker support.";
      };

      privateKeyFile = mkOption {
        type = types.path;
        description = "Path to private key file.";
      };

      gitHubSecretFile = mkOption {
        type = types.path;
        description = "Path to Github secret file.";
      };

      domain = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Domain name. Nginx is not used if null.";
      };

      projects = mkOption {
        type = types.attrsOf (types.submodule projectOpts);
        default = {};
        description = "Deployed projects configuration.";
      };

      path = mkOption {
        type = types.listOf types.path;
        default = [];
        description = "Binary dependencies.";
      };
    };
  };

  config = mkIf cfg.enable {
    services.nginx = mkIf (cfg.domain != null) {
      enable = true;
      virtualHosts."${cfg.domain}" = {
        forceSSL = true;
        enableACME = true;
        locations."/".proxyPass = "http://unix:/run/deploy-bot/http.sock";
      };
    };

    virtualisation.docker.enable = mkIf cfg.docker true;

    systemd.services."deploy-bot" = {
      description = "deploy-bot web service.";
      wantedBy = ["multi-user.target"];
      path = [gunicornPkg pkgs.coreutils pkgs.openssh] ++ binPkgs;
      environment = {
        "CONFIG" = "/var/lib/deploy-bot/config.json";
        "NIX_PATH" = concatStringsSep ":" config.nix.nixPath;
      };
      serviceConfig = {
        User = "deploy-bot";
        Group = "deploy-bot";
        RuntimeDirectory = "deploy-bot";
        StateDirectory = "deploy-bot";
        StateDirectoryMode = "0700";
        WorkingDirectory = "/var/lib/deploy-bot";
        LoadCredential = [
          "secret:${cfg.gitHubSecretFile}"
          "ssh:${cfg.privateKeyFile}"
        ];
      };
      script = ''
        sed \
          "s,REPLACE_BY_GITHUB_SECRET,$(cat "$CREDENTIALS_DIRECTORY/secret"),g" \
          \${configFile} > config.json
        mkdir -p .ssh
        if [ ! -f .ssh/known_hosts ]; then
          ssh-keyscan github.com >.ssh/known_hosts 2>/dev/null
        fi
        cp -f "$CREDENTIALS_DIRECTORY/ssh" .ssh/id_rsa
        chmod 400 .ssh/id_rsa

        exec gunicorn -n deploy-bot -w "$(nproc)" -t ${toString maxTimeout} -b unix:/run/deploy-bot/http.sock deploy_bot.wsgi:app
      '';
    };

    users.extraUsers.deploy-bot = {
      isSystemUser = true;
      group = "deploy-bot";
      createHome = true;
      home = "/var/lib/deploy-bot";
      extraGroups = optional cfg.docker "docker";
    };

    users.extraGroups.deploy-bot = {};
  };
}
