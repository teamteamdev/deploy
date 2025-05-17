import hmac
import json
import logging

from starlette.applications import Starlette
from starlette.background import BackgroundTask
from starlette.requests import Request
from starlette.responses import PlainTextResponse, Response
from starlette.routing import Route

from gh_deploy.config import get_config
from gh_deploy.deploy import deploy
from gh_deploy.util import remove_prefix

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


async def hook(request: Request) -> Response:
    action = request.headers.get("X-GitHub-Event", "")
    if action != "push":
        return PlainTextResponse("OK [skip event]", status_code=200)

    signature = remove_prefix("sha1=", request.headers.get("X-Hub-Signature", ""))
    if signature is None:
        return PlainTextResponse("Bad signature algorithm", status_code=400)

    body = await request.body()

    if not hmac.compare_digest(
        signature,
        hmac.new(get_config().webhook_secret.encode(), body, "sha1").hexdigest(),
    ):
        return PlainTextResponse("Bad security signature", status_code=403)

    data = json.loads(body)

    try:
        repository = data["repository"]["full_name"]
        ref = data["ref"]
    except KeyError:
        return PlainTextResponse("Missing required fields", status_code=400)

    branch = remove_prefix("refs/heads/", ref)
    if branch is None:
        return PlainTextResponse("OK [skip: non-branch push]")

    project = get_config().project(repository, branch)
    if project is None:
        return PlainTextResponse("OK [skip: no deploy action]")

    return PlainTextResponse(
        "OK",
        background=BackgroundTask(
            deploy,
            project,
            use_lfs=get_config().git.use_lfs,
            default_timeout=get_config().default_timeout,
        ),
    )


app = Starlette(routes=[Route("/", hook, methods=["POST"], name="hook")])
