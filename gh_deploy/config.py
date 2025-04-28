from functools import cached_property
from pathlib import Path

import yaml
from pydantic import BaseModel, FilePath


class Project(BaseModel):
    repo: str
    branch: str
    path: Path
    cmd: str | None = None
    timeout: int | None = None


class TLS(BaseModel):
    key: FilePath
    cert: FilePath


class Config(BaseModel):
    bind: str = "0.0.0.0:8000"
    workers: int = 3
    tls: TLS | None = None

    github_secret: str
    default_timeout: int = 120

    use_lfs: bool = False

    projects: list[Project] = []

    @cached_property
    def project_map(self) -> dict[tuple[str, str], Project]:
        return {
            (project.repo.lower(), project.branch.lower()): project
            for project in self.projects
        }

    def project(self, repo: str, branch: str) -> Project | None:
        return self.project_map.get((repo.lower(), branch.lower()))


config: Config


# TODO: Refactor this to avoid dirty tricks with config import orders. How?
def load_config(config_path: Path) -> None:
    with config_path.open() as config_file:
        raw_config = yaml.load(config_file, Loader=yaml.SafeLoader)

    global config
    config = Config(**raw_config)
