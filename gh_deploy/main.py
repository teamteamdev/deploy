import argparse
import sys
from typing import NoReturn

from .app import app
from .config import load_config
from .gunicorn import run
from .systemd import install, uninstall


def main() -> NoReturn:
    parser = argparse.ArgumentParser(
        prog="gh-deploy", description="GitHub webhook-based deployment system"
    )
    commands = parser.add_subparsers(
        title="commands", metavar="command", required=True, dest="command"
    )
    run_command = commands.add_parser("run", help="launch gh-deploy")
    run_command.add_argument(
        "-c", "--config", default="/etc/gh-deploy.yaml", help="configuration file"
    )
    commands.add_parser("install", help="install systemd unit")
    commands.add_parser("uninstall", help="uninstall systemd unit")

    args = parser.parse_args()

    match args.command:
        case "run":
            load_config(args.config)
            run()
        case "install":
            install()
        case "uninstall":
            uninstall()


def debug() -> NoReturn:
    if len(sys.argv) > 1:
        load_config(sys.argv[1])
    else:
        print(
            "[!] Config not provided, loading `config.yaml`.",
            "Pass correct location as first argument.",
            file=sys.stderr,
        )
        load_config("config.yaml")

    app.run(debug=True)
