# [team Team] Deploy System

## Setup

### Systems with systemd

You need:

1. Git
2. Git LFS if you want to use it
3. Your current user should be able to fetch all repositories you need via SSH
4. Execute `ssh-keyscan github.com > ~/.ssh/known_hosts`

We recommend to use [uv](https://docs.astral.sh/uv/), but you can use whatever you want.

1. Fetch the package: `uv tool install git+https://github.com/teamteamdev/deploy.git`.

2. Install systemd unit: `gh-deploy install` (**do not** run it as `sudo`, it will elevate itself).

3. Put the configuration to `/etc/gh-deploy.yaml`.

### NixOS

Use `flake.nix`. It exports NixOS module you need. Probably it will not work.

### Something else

`uv` should also fetch `gh-deploy` for you. Start app via `gh-deploy run /path/to/config.yaml`

## Configuration

Sample `config.yaml`:

```yaml
bind: "0.0.0.0:8000"  # (default) or unix:///var/run/gh-deploy.sock
workers: 3            # (default)
tls:                  # (default is HTTP, see below)
  key: /path/to/domain.key
  cert: /path/to/domain.crt

webhook_secret: "same-thing-as-in-github-webhook-settings"
default_timeout: 120  # (default) in seconds

git:
  method: ssh         # (default, also http is supported)
  # username: ...     # (required for "http" method)
  # password: ...
  use_lfs: false      # (default)

projects:
  # All (repo, branch) pairs should be unique
  - repo: teamteamdev/kyzylborda
    branch: production
    path: /opt/kyzylborda
    cmd: systemctl reload kyzylborda

    timeout: 240      # (optional, default is `default_timeout`)
```

> [!NOTE]
> Though Deploy supports HTTPS out of the box, we recommend to use
> some reverse proxy (Nginx, HAProxy, …).

## GitHub configuration

Open **Webhooks** tab in repository or organization settings, setup new webhook. Send only `push` events.

URL should be `https://your-host:your-port/`. Secret should be same as `github_secret` in config.

## Deployment process

* If `cmd` is provided in configuration file, it will be started to deploy new version
* Otherwise, if `deploy.sh` exists in the project root, it will be started
* Otherwise, Deploy System will execute `docker-compose restart`

## TODOs

- [ ] Implement Telegram notifications on pushes
