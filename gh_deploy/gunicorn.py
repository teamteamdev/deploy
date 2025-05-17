from collections.abc import Callable
from typing import NoReturn

import gunicorn.app.base

from gh_deploy.app import app
from gh_deploy.config import get_config


class Application(gunicorn.app.base.BaseApplication):
    def __init__(self):
        self.options = {
            "bind": get_config().bind,
            "workers": get_config().workers,
            "worker_class": "uvicorn.workers.UvicornWorker",
        }

        if get_config().tls:
            self.options["keyfile"] = str(get_config().tls.key)
            self.options["certfile"] = str(get_config().tls.cert)

        self.application = app
        super().__init__()

    def load_config(self) -> None:
        config = {
            key: value
            for key, value in self.options.items()
            if key in self.cfg.settings and value is not None
        }
        for key, value in config.items():
            self.cfg.set(key.lower(), value)

    def load(self) -> Callable:
        return self.application


def run() -> NoReturn:
    Application().run()
