import os

from . import make_app

if "CONFIG" in os.environ:
    config = os.environ["CONFIG"]
else:
    config = "config.yaml"

app = make_app(config)
