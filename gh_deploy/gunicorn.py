from collections.abc import Callable
from typing import NoReturn

import gunicorn.app.base

from .app import app
from .config import config


class Application(gunicorn.app.base.BaseApplication):
    def __init__(self):
        self.options = {"bind": config.bind, "workers": config.workers}

        if config.tls:
            self.options["keyfile"] = str(config.tls.key)
            self.options["certfile"] = str(config.tls.cert)

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
