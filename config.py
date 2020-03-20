import os
import yaml

BASE_DIR = os.path.dirname(os.path.realpath(__file__))

with open(os.path.join(BASE_DIR, "deploy.yaml")) as config_file:
    Config = yaml.safe_load(config_file.read())