import grp
import os
import pwd
import subprocess
import sys
import tempfile
from pathlib import Path

from .util import run_command


def sudo(*args: str, capture_output: bool = False) -> bytes | None:
    print("+ sudo", *args, file=sys.stderr)
    return run_command(["sudo", *args], capture_output=capture_output)


def install() -> None:
    systemd_unit = f"""[Unit]
Description=GitHub webhook-based deployment system
After=network.target

[Service]
User={pwd.getpwuid(os.geteuid()).pw_name}
Group={grp.getgrgid(os.getgid()).gr_name}
WorkingDirectory=/
ExecStart={sys.executable} -m gh_deploy run
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
"""

    if (
        b"systemd" not in sudo("realpath", "/proc/1/exe", capture_output=True)
        and os.environ.get("FORCE_INSTALL") is None
    ):
        print(
            "This system probably not using systemd, so auto-installer won't work.",
            "If you're sure, run with FORCE_INSTALL=1.",
            file=sys.stderr,
        )
        os.exit(1)

    try:
        with tempfile.NamedTemporaryFile("w", delete=False) as conf:
            conf.write(systemd_unit)
        sudo("mv", conf.name, "/lib/systemd/system/gh-deploy.service")
    finally:
        Path(conf.name).unlink(missing_ok=True)

    try:
        sudo("systemctl", "daemon-reload")
        sudo("systemctl", "enable", "gh-deploy.service")
        sudo("systemctl", "start", "gh-deploy.service")
    except subprocess.CalledProcessError:
        print("[-] Some commands failed. Check logs above.", file=sys.stderr)
        sys.exit(1)

    print(
        "Installation is done! Check it out: `systemctl status gh-deploy`",
        file=sys.stderr,
    )


def uninstall() -> None:
    try:
        sudo("systemctl", "disable", "gh-deploy.service")
        sudo("systemctl", "stop", "gh-deploy.service")
        sudo("rm", "/lib/systemd/system/gh-deploy.service")
        sudo("systemctl", "daemon-reload")
    except subprocess.CalledProcessError:
        print("[-] Some commands failed. Check logs above.", file=sys.stderr)
        sys.exit(1)
