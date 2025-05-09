import argparse
import sys
from pathlib import Path
from typing import NoReturn

from .config import get_config, set_config_path
from .util import remove_prefix


def main() -> NoReturn:
    parser = argparse.ArgumentParser(
        prog="gh-deploy", description="GitHub webhook-based deployment system"
    )
    commands = parser.add_subparsers(
        title="commands", metavar="command", required=True, dest="command"
    )
    run_command = commands.add_parser("run", help="launch gh-deploy")
    run_command.add_argument(
        "-c",
        "--config",
        type=Path,
        default=Path("/etc/gh-deploy.yaml"),
        help="configuration file",
    )
    commands.add_parser("install", help="install systemd unit")
    commands.add_parser("uninstall", help="uninstall systemd unit")

    args = parser.parse_args()

    match args.command:
        case "run":
            set_config_path(args.config)

            from .gunicorn import run

            run()
        case "install":
            from .systemd import install

            install()
        case "uninstall":
            from .systemd import uninstall

            uninstall()


def debug() -> NoReturn:
    if len(sys.argv) > 1:
        set_config_path(sys.argv[1])
    else:
        print(
            "[!] Config not provided, loading `config.yaml`.",
            "Pass correct location as first argument.",
            file=sys.stderr,
        )
        set_config_path("config.yaml")

    import uvicorn

    bind = get_config().bind
    uv_bind = {}
    if (fd := remove_prefix(bind, "fd://")) is not None:
        uv_bind["fd"] = int(fd)
    elif (uds := remove_prefix(bind, "unix:")) is not None:
        uv_bind["uds"] = uds
    elif ":" in bind:
        host, port = bind.split(":")
        uv_bind["host"], uv_bind["port"] = host, int(port)
    elif bind.isdigit():
        uv_bind["port"] = int(bind)
    else:
        error = f"Unsupported bind target: {bind}"
        raise ValueError(error)

    uvicorn.run("gh_deploy.app:app", **uv_bind, reload=True)
