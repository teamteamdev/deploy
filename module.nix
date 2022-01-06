{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.deploy-bot;

  deployConfig = {
    GITHUB_SECRET = "REPLACE_BY_GITHUB_SECRET";
    PROJECTS = mapAttrsToList (path: project: {
      inherit (project) repo branch timeout;
      inherit path;
      cmd = pkgs.writeScript "deploy.sh" ''
        #!${pkgs.stdenv.shell} -e
        ${project.script}
      '';
    }) cfg.projects;
  };

  configFile = pkgs.writeText "config.json" (builtins.toJSON deployConfig);

  gunicornPkg = pkgs.python3.withPackages (ps: [ pkgs.deploy-bot ps.gunicorn ]);

  binPkgs = with pkgs;
    [ git git-lfs openssh bash ]
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
      wantedBy = [ "multi-user.target" ];
      path = [ gunicornPkg pkgs.coreutils ] ++ binPkgs;
      environment = {
        "CONFIG" = "/var/lib/deploy-bot/config.json";
        "NIX_PATH" = concatStringsSep ":" config.nix.nixPath;
      };
      serviceConfig = {
        User = "deploy-bot";
        Group = "deploy-bot";
        RuntimeDirectory = "deploy-bot";
        StateDirectory = "deploy-bot";
        WorkingDirectory = "/var/lib/deploy-bot";
      };
      script = ''
        exec gunicorn -n deploy-bot -w $(nproc) -b unix:/run/deploy-bot/http.sock deploy_bot.wsgi:app
      '';
    };

    systemd.services."deploy-bot-prepare" = {
      description = "Prepare state directory for deploy-bot.";
      wantedBy = [ "multi-user.target" ];
      serviceConfig.Type = "oneshot";
      path = [ pkgs.openssh ];
      script = ''
        secret="$(cat ${cfg.gitHubSecretFile})"
        sed "s,REPLACE_BY_GITHUB_SECRET,$secret," ${configFile} > /var/lib/deploy-bot/config.json
        mkdir -p /var/lib/deploy-bot/.ssh
        if [ ! -f /var/lib/deploy-bot/.ssh/known_hosts ]; then
          ssh-keyscan github.com >/var/lib/deploy-bot/.ssh/known_hosts 2>/dev/null
        fi
        cp ${cfg.privateKeyFile} /var/lib/deploy-bot/.ssh/id_rsa
        chown -R deploy-bot:deploy-bot /var/lib/deploy-bot/.ssh
        chmod 600 /var/lib/deploy-bot/.ssh/id_rsa
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
