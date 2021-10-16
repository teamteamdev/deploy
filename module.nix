{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.teamteam.deploy-bot;
  uwsgiSock = "/run/uwsgi/deploy.sock";
  user = "deploy";

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
    teamteam.deploy-bot = {
      enable = mkEnableOption "deploy bot";

      podman = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Podman support.";
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
    };
  };

  config = mkIf cfg.enable {
    services.nginx = mkIf (cfg.domain != null) {
      enable = true;
      virtualHosts."${cfg.domain}" = {
        forceSSL = true;
        enableACME = true;
        locations = {
          "/".extraConfig = ''
            uwsgi_pass unix:${uwsgiSock};
            include ${pkgs.nginx}/conf/uwsgi_params;
          '';
        };
      };
    };
  
    services.uwsgi = {
      enable = true;
      plugins = [ "python3" ];
      instance = {
        type = "emperor";
        vassals = {
          deploy = config.teamteam.commonUwsgiConfig // {
            plugins = [ "python3" ];
            pythonPackages = _: [ pkgs.deploy-bot ];
            env = [ "CONFIG=/var/lib/${user}/config.json" "PATH=${makeBinPath (with pkgs; [ git git-lfs openssh bash ])}" "HOME=/var/lib/${user}" ];
            socket = uwsgiSock;
            chdir = "/var/lib/${user}";
            uid = user;
            gid = "uwsgi";
            logger = "syslog:deploy";
            module = "deploy.wsgi";
            callable = "app";
          };
        };
      };
    };

    virtualisation.podman.enable = mkIf cfg.podman true;

    systemd.services.uwsgi.restartTriggers = [ configFile ];

    systemd.services."prepare-${user}" = {
      wantedBy = [ "multi-user.target" ];
      before = [ "uwsgi.service" ];
      serviceConfig.Type = "oneshot";
      path = [ pkgs.openssh ];
      script = ''
        secret="$(cat ${cfg.gitHubSecretFile})"
        sed "s,REPLACE_BY_GITHUB_SECRET,$secret," ${configFile} > /var/lib/${user}/config.json
        mkdir -p /var/lib/${user}/.ssh
        if [ ! -f /var/lib/${user}/.ssh/known_hosts ]; then
          ssh-keyscan github.com >/var/lib/${user}/.ssh/known_hosts 2>/dev/null
        fi
        cp ${cfg.privateKeyFile} /var/lib/${user}/.ssh/id_rsa
        chown -R ${user}:uwsgi /var/lib/${user}/.ssh
        chmod 600 /var/lib/${user}/.ssh/id_rsa
        ${optionalString cfg.podman "${config.systemd.package}/bin/loginctl enable-linger ${user}"}
      '';
    };

    users.extraUsers.${user} = {
      isSystemUser = true;
      group = "uwsgi";
      createHome = true;
      home = "/var/lib/${user}";
    } // optionalAttrs cfg.podman {
      subUidRanges = [{ startUid = 100000; count = 65536; }];
      subGidRanges = [{ startGid = 100000; count = 65536; }];
    };
  };
}
