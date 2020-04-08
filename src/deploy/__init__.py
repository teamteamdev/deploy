#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import hmac
import flask
import os
from multiprocess import Process
import sys
import contextlib
import subprocess
import logging
import yaml
import fcntl
from contextlib import contextmanager


logger = logging.getLogger(__name__)


def remove_prefix(prefix, str):
    if str.startswith(prefix):
        return str[len(prefix):]
    else:
        return None


def run_command(command, dir, timeout=120):
    return subprocess.run(
        command,
        check=True, cwd=dir,
        timeout=timeout,
    )


@contextmanager
def lock_directory(dir):
    # We use lockfile in parent directory, otherwise git refuses to clone in non-empty directory.
    parentdir, dirname = os.path.split(os.path.abspath(dir))
    with open(os.path.join(parentdir, f".{dirname}-lock"), "w") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        yield


def deploy(repository, branch, dir, cmd, timeout):
    os.makedirs(dir, exist_ok=True)
    with lock_directory(dir):
        try:
            if os.path.isdir(os.path.join(dir, ".git")):
                run_command(["git", "fetch", "origin", branch], dir)
                run_command(["git", "checkout", "-B", branch, f"origin/{branch}"], dir)
            else:
                run_command(["git", "clone", f"git@github.com:{repository}", ".", "-b", branch], dir)

            if cmd is not None:
                run_command([cmd], dir, timeout)
            elif os.path.isfile(os.path.join(dir, "deploy.sh", timeout)):
                run_command(["./deploy.sh"], dir)
            elif os.path.isfile(os.path.join(dir, "docker-compose.yml", timeout)):
                run_command(["docker-compose", "restart"], dir, timeout)
            else:
                logger.error(f"No idea how to deploy project in directory {dir}")
        except subprocess.CalledProcessError as e:
            raise
            # TODO: notify
        except subprocess.TimeoutExpired as e:
            raise
            # TODO: notify
    logger.info(f"Successfully deployed {repository}#{branch}")


def make_app(config_path):
    app = flask.Flask(__name__)
    with open(config_path) as f:
        app.config.from_mapping(**yaml.load(f, Loader=yaml.FullLoader))

    secret = app.config["GITHUB_SECRET"].encode()
    default_timeout = app.config.get("DEFAULT_TIMEOUT", 120)
    projects = {}
    for raw_project in app.config["PROJECTS"]:
        branches = projects.setdefault(raw_project["repo"].lower(), {})
        project = branches.setdefault(raw_project["branch"].lower(), {})
        project.update(raw_project)

    @app.route("/", methods=["POST"])
    def hook():
        action = flask.request.headers.get("X-GitHub-Event", "")
        if action != "push":
            return "OK [skip event]", 200

        signature = remove_prefix("sha1=", flask.request.headers.get("X-Hub-Signature", ""))
        if signature is None:
            return "Bad signature algorithm", 400

        if not hmac.compare_digest(
            signature,
            hmac.new(
                secret,
                flask.request.get_data(),
                "sha1"
            ).hexdigest()
        ):
            return "Bad security signature", 403

        data = flask.request.json

        try:
            repository = data["repository"]["full_name"]
            ref = data["ref"]
        except KeyError:
            return "Missing required fields", 400

        branch = remove_prefix("refs/heads/", data["ref"])
        if branch is None:
            return "OK [skip: non-branch push]"
        try:
            project = projects[repository.lower()][branch.lower()]
        except KeyError:
            return "OK [skip: no deploy action]"

        deploy_args = (repository, branch, project["path"], project.get("cmd"), project.get("timeout", default_timeout))
        deploy_process = Process(target=deploy, args=deploy_args)
        deploy_thread.start()

        # TODO: notify about successful deployment
        return "OK"

    return app


def main():
    app = make_app(sys.argv[1])
    app.run()


if __name__ == "__main__":
    main()
