import hmac
import logging

import flask

from .after_response import AfterResponse
from .config import config
from .deploy import deploy
from .util import remove_prefix

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = flask.Flask(__name__)
after_response = AfterResponse(app)


@app.route("/", methods=["POST"])
def hook() -> str:
    action = flask.request.headers.get("X-GitHub-Event", "")
    if action != "push":
        return "OK [skip event]", 200

    signature = remove_prefix("sha1=", flask.request.headers.get("X-Hub-Signature", ""))
    if signature is None:
        return "Bad signature algorithm", 400

    if not hmac.compare_digest(
        signature,
        hmac.new(
            config.github_secret.encode(), flask.request.get_data(), "sha1"
        ).hexdigest(),
    ):
        return "Bad security signature", 403

    data = flask.request.json

    try:
        repository = data["repository"]["full_name"]
        ref = data["ref"]
    except KeyError:
        return "Missing required fields", 400

    branch = remove_prefix("refs/heads/", ref)
    if branch is None:
        return "OK [skip: non-branch push]"

    project = config.project(repository, branch)
    if project is None:
        return "OK [skip: no deploy action]"

    @after_response.once
    def run_deploy() -> None:
        deploy(project, use_lfs=config.use_lfs, default_timeout=config.default_timeout)

    return "OK"
