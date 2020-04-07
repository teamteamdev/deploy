{ domain, projects ? {}, ... }:

{ config, pkgs, lib, ... }:

with lib;

let
  app = pkgs.python3.pkgs.callPackage ./. { };
  uwsgiSock = "/run/uwsgi/deploy.sock";
  user = "deploy";

  deployConfig = {
    GITHUB_SECRET = "REPLACE_BY_GITHUB_SECRET";
    PROJECTS = projects;
  };

in {
  imports = [ ../config-common.nix ];

  services.nginx = {
    enable = true;
    virtualHosts."${domain}" = {
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
        deploy = {
          type = "normal";
          pythonPackages = pkgs: [ app ];
          env = [ "CONFIG=/var/lib/${user}/config.json" "PATH=${makeBinPath (with pkgs; [ git openssh bash ])}" "HOME=/var/lib/${user}" ];
          socket = uwsgiSock;
          chmod-socket = 664;
          chdir = "/var/lib/${user}";
          uid = user;
          gid = "uwsgi";
          enable-threads = true;
          manage-script-name = true;
          mount = "/=deploy.wsgi:app";
        };
      };
    };
  };

  systemd.services."prepare-${user}" = {
    wantedBy = [ "multi-user.target" ];
    before = [ "uwsgi.service" ];
    serviceConfig.Type = "oneshot";
    path = [ pkgs.openssh ];
    script = ''
      secret="$(cat ${toString ../deploy-secrets/secret.txt})"
      sed "s,REPLACE_BY_GITHUB_SECRET,$secret," ${pkgs.writeText "config.json" (builtins.toJSON deployConfig)} > /var/lib/${user}/config.json
      mkdir -p /var/lib/${user}/.ssh
      if [ ! -f /var/lib/${user}/.ssh/known_hosts ]; then
        ssh-keyscan github.com >/var/lib/${user}/.ssh/known_hosts 2>/dev/null
      fi
      cp ${toString ../deploy-secrets/id_ed25519} /var/lib/${user}/.ssh/id_ed25519
      chown -R ${user}:uwsgi /var/lib/${user}/.ssh
      chmod 600 /var/lib/${user}/.ssh/id_ed25519
    '';
  };

  users.extraUsers.${user} = {
    group = "uwsgi";
    createHome = true;
    home = "/var/lib/${user}";
  };
}
