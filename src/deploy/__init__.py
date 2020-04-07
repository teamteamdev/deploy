#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import hmac
import flask
import os
import sys
import subprocess
import logging
import yaml


logger = logging.getLogger(__name__)


def remove_prefix(prefix, str):
    if str.startswith(prefix):
        return str[len(prefix):]
    else:
        return None


def run_command(command, folder):
    return subprocess.run(
        command,
        check=True, cwd=folder, 
        timeout=60
    )


def deploy(folder, cmd):
    try:
        run_command(["git", "fetch"], folder)
        run_command(["git", "checkout", "-B", "master", "origin/master"], folder)

        if cmd is not None:
            run_command(["bash", "-c", cmd], folder)
        elif os.path.exists(os.path.join(folder, "deploy.sh")):
            run_command(["bash", "deploy.sh"], folder)
        elif os.path.exists(os.path.join(folder, "docker-compose.yml")):
            run_command(["docker-compose", "restart"], folder)
        else:
            logger.error(f"No idea how to deploy project in folder {folder}")
    except subprocess.CalledProcessError as e:
        raise
        # TODO: notify
    except subprocess.TimeoutExpired as e:
        raise
        # TODO: notify


def make_app(config_path):
    app = flask.Flask(__name__)
    with open(config_path) as f:
        app.config.from_mapping(**yaml.load(f, Loader=yaml.FullLoader))

    secret = app.config["GITHUB_SECRET"]
    projects = {}
    for raw_project in app.config["PROJECTS"]:
        branches = projects.setdefault(raw_project["repo"].lower(), {})
        project = branches.setdefault(raw_project["branch"].lower(), {})
        project["path"] = raw_project["path"]
        project["cmd"] = raw_project.get("cmd")

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
                config.Config["secret"].encode(),
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

        deploy(project["path"], project.get("cmd"))
        # TODO: notify about successful deployment
        return "OK"

    return app


def main():
    app = make_app(sys.argv[1])
    app.run()


if __name__ == "__main__":
    main()
