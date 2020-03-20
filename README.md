# [team Team] Deploy System

## Setup

1. Clone this repository to the target server
2. [Optional] Create virtual environment: `virtualenv venv`
3. [Optional] Activate it: `source venv/bin/activate`
4. Install dependencies: `pip install -r requirements.txt`
5. Edit `example.service` and move it to your systemd folder
   
   For example, the path for Ubuntu 18.04 is `/etc/systemd/system/deploy.service`.

   You should specify path to your folder and user which has both ability to read from remote repositories as well as privileges to write to projects' folders.
6. Reload systemd daemon: `systemctl daemon-reload` (as root)
7. Start service: `service deploy start` (as root)
8. Enable startup on boot: `systemctl enable deploy` (as root)

## Add project

You should put configuration file `deploy.yaml` in project folder to setup deploy configuration. Its root element is a dictionary containing these properties:

* `secret` — required — GitHub webhook secret
* `bind` — required — host and port to listen on

  > **Note**: Deploy System doesn't support HTTPS protocol. Use Nginx for reverse-proxying. Sample config is provided in `example.nginx.conf`.
* `projects` — required — list of `Project` objects

### Project

* `repo` — required — full repository name
* `branch` — optional, defaults to `master` — branch name
* `path` — required — location of the project on your drive
* `script` — optional — bash command to redeploy the project

## GitHub configuration

Open **Webhooks** tab in repository or organization settings, setup new webhook. Send only `push` events. By default, Deploy System listens on `/`.

## Deployment process

* If `script` is provided in configuration file, it will be started to deploy new version
* Otherwise, if `deploy.sh` exists in the project root, it will be started
* Otherwise, Deploy System will execute `docker-compose restart`

## TODOs

1. Implement Telegram notifications on pushes
2. Send HTTP response asynchronously
3. ???
4. PROFIT!!!!