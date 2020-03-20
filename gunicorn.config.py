import config
import os

try:
    bind = config.Config["bind"]
    workers = 3
    chdir = config.BASE_DIR
except KeyError as e:
    raise KeyError(f"Missing required configuration key: {e}") from e

del config