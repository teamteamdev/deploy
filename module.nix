myPackages:
{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  cfg = config.services.gh-deploy;

  isGitHttp = cfg.http != null;
  isGitSsh = cfg.ssh != null;

  maxTimeout = foldr max 0 (mapAttrsToList (name: proj: proj.timeout) cfg.projects) + 15;

  deployConfig = {
    bind = "unix:/run/gh-deploy/http.sock";
    webhook_secret = "GITHUB_WEBHOOK_SECRET_PLACEHOLDER";
    default_timeout = maxTimeout;

    git =
      {
        type = if isGitHttp then "http" else "ssh";
        use_lfs = cfg.lfs;
      }
      // lib.attrsets.optionalAttrs isGitHttp {
        inherit (cfg.git) username;
        password = "PASSWORD_PLACEHOLDER";
      };

    projects = mapAttrsToList (path: project: {
      inherit (project) repo branch timeout;
      inherit path;
      cmd = pkgs.writeScript "deploy.sh" ''
        #!${pkgs.stdenv.shell} -e
        ${project.script}
      '';
    }) cfg.projects;
  };

  configFile = pkgs.writeText "config.json" (builtins.toJSON deployConfig);

  binPkgs =
    with pkgs;
    [
      git
      bash
    ]
    ++ optional isGitSsh pkgs.openssh
    ++ optional cfg.docker pkgs.docker
    ++ optional cfg.lfs pkgs.git-lfs
    ++ cfg.path;

  package = myPackages.${pkgs.system}.gh-deploy;

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
in
{
  options = {
    services.gh-deploy = {
      enable = mkEnableOption "GitHub Deployment System";

      docker = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Docker support.";
      };

      ssh = mkOption {
        type = types.nullOr (
          types.submodule {
            options = {
              privateKeyFile = mkOption {
                type = types.path;
                description = "Path to private key file.";
              };
            };
          }
        );
        description = "Options for SSH transport.";
        default = null;
      };

      http = mkOption {
        type = types.nullOr (
          types.submodule {
            username = mkOption {
              type = types.str;
              description = "Username for HTTP basic authentication.";
            };
            passwordFile = mkOption {
              type = types.path;
              description = "Path to password for HTTP basic authentication.";
            };
          }
        );
        description = "Options for HTTP transport.";
        default = null;
      };

      lfs = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Git LFS support.";
      };

      webhookSecretFile = mkOption {
        type = types.path;
        description = "Path to Github webhook secret file.";
      };

      domain = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Domain name. Nginx is not used if null (default).";
      };

      projects = mkOption {
        type = types.attrsOf (types.submodule projectOpts);
        default = { };
        description = "Deployed projects configuration.";
      };

      path = mkOption {
        type = types.listOf types.path;
        default = [ ];
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
        locations."/".proxyPass = "http://unix:/run/gh-deploy/http.sock";
      };
    };

    virtualisation.docker.enable = mkIf cfg.docker true;

    systemd.services."gh-deploy" = {
      description = "gh-deploy web service.";
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.coreutils ] ++ binPkgs;
      environment = {
        "NIX_PATH" = concatStringsSep ":" config.nix.nixPath;
      };
      serviceConfig = {
        User = "gh-deploy";
        Group = "gh-deploy";
        RuntimeDirectory = "gh-deploy";
        StateDirectory = "gh-deploy";
        StateDirectoryMode = "0700";
        WorkingDirectory = "/var/lib/gh-deploy";
        LoadCredential =
          [
            "webhook_secret:${cfg.webhookSecretFile}"
          ]
          ++ lib.optional isGitSsh "ssh:${cfg.ssh.privateKeyFile}"
          ++ lib.optional isGitHttp "password:${cfg.http.passwordFile}";
      };
      script = concatStrings (
        [
          ''
            sed \
              "s,GITHUB_WEBHOOK_SECRET_PLACEHOLDER,$(cat "$CREDENTIALS_DIRECTORY/webhook_secret"),g" \
              \${configFile} > config.json
          ''
        ]
        ++ lib.optional isGitSsh ''
          mkdir -p .ssh
          if [ ! -f .ssh/known_hosts ]; then
            ssh-keyscan github.com >.ssh/known_hosts 2>/dev/null
          fi
          cp -f "$CREDENTIALS_DIRECTORY/ssh" .ssh/id_rsa
          chmod 400 .ssh/id_rsa
        ''
        ++ lib.optional isGitHttp ''
          sed \
            "s,PASSWORD_PLACEHOLDER,$(cat "$CREDENTIALS_DIRECTORY/password"),g" \
            \${configFile} > config.json
        ''
        ++ [
          ''
            exec ${package}/bin/gh-deploy run -c /var/lib/gh-deploy/config.json
          ''
        ]
      );
    };

    users.extraUsers.gh-deploy = {
      isSystemUser = true;
      group = "gh-deploy";
      createHome = true;
      home = "/var/lib/gh-deploy";
      extraGroups = optional cfg.docker "docker";
    };

    users.extraGroups.gh-deploy = { };
  };
}
