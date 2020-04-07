#!/usr/bin/env python3

from setuptools import setup


setup(
    name="deploy",
    description="[team Team] Deploy System",
    version="1.0",
    package_dir={"": "src"},
    packages=["deploy"],
    install_requires=[
        "flask",
        "pyyaml",
    ],
    entry_points={
        "console_scripts": [
            "deploy=deploy:main"
        ]
    },
)

