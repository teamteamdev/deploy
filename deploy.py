#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import hmac
import flask
import os
import subprocess

import config

app = flask.Flask(__name__)


def run_command(command, folder):
    return subprocess.run(
        command,
        check=True, cwd=folder, 
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=60
    )


def deploy(folder, cmd):
    try:
        run_command(["git", "pull"], folder)

        if cmd is not None:
            run_command(["bash", "-c", cmd], folder)
        elif os.path.exists(os.path.join(folder, "deploy.sh")):
            run_command(["bash", "deploy.sh"], folder)
        else:
            run_command(["docker-compose", "restart"], folder)
    except subprocess.CalledProcessError as e:
        raise
        # TODO: notify
    except subprocess.TimeoutExpired as e:
        raise
        # TODO: notify

@app.route("/", methods=["POST"])
def hook():
    action = flask.request.headers.get("X-GitHub-Event", "")
    if action != "push":
        return "OK [skip event]", 200
    
    signature = flask.request.headers.get("X-Hub-Signature", "")

    if not signature.startswith("sha1="):
        return "Bad signature algorithm", 400
 
    if not hmac.compare_digest(
        signature[5:],
        hmac.new(
            config.Config["secret"].encode(),
            flask.request.get_data(),
            "sha1"
        ).hexdigest()
    ):
        return f"Bad security signature", 403
    
    data = flask.request.json

    try:
        repository = data["repository"]["full_name"]

        ref = data["ref"]
        if not ref.startswith("refs/heads/"):
            return "OK [skip: non-branch push]"
        branch = ref[11:]

        for project in config.Config.get("projects", []):
            if project["repo"].lower() != repository.lower():
                continue
            if project["branch"].lower() != branch.lower():
                continue
            
            deploy(project["path"], project.get("cmd"))

            # TODO: notify about successful deployment
    except KeyError:
        return "Missing required fields", 400

    return "OK"


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=8080)