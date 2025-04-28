import subprocess
from pathlib import Path


def run_command(
    command: list[str],
    *,
    cwd: Path | None = None,
    timeout: int = 120,
    capture_output: bool = False,
    shell: bool = False,
) -> bytes | None:
    sp = subprocess.run(
        command,
        check=True,
        shell=shell,
        cwd=cwd,
        timeout=timeout,
        stdout=subprocess.PIPE if capture_output else None,
        stderr=None,
    )

    if capture_output:
        return sp.stdout

    return None


def remove_prefix(prefix: str, source: str) -> str | None:
    if source.startswith(prefix):
        return source[len(prefix) :]

    return None


__all__ = ["remove_prefix", "run_command"]
