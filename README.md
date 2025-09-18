## SteamCMD Game Servers (Palworld + V Rising)

Dockerized servers with SteamCMD, per-game docker-compose, backups, and RCON helpers.

This repo contains two ready-to-run setups:
- Palworld: `palworld/`
- V Rising (Wine): `vrising/`

Both share the same Dockerfile base and store data under `/home/steam/serverdata` inside the container.

# Paired Repo
Utilizes service files and scripts defined in this repo: https://github.com/XtraIce/linux-steamcmd
I seperated them for if someone just wants to use those files without a container.

## Admin cheat sheet

Build + up

```bash
cd palworld && docker compose up -d --build
cd vrising && docker compose up -d --build
```

Logs and shell

```bash
docker logs -f palworld-server
docker logs -f vrising-server
docker exec -it palworld-server /bin/bash
docker exec -it vrising-server /bin/bash
```

Systemctl inside container

```bash
systemctl status steamcmd_server
systemctl restart steamcmd_server
systemctl start steamcmd_server_update
```

ARRCON (RCON)

```bash
docker exec -it palworld-server ARRCON -P 25575 -p <pass> broadcast "Restart in 5m"
docker exec -it vrising-server  ARRCON -P 25576 -p <pass> announce  "Restart in 5m"
```

Tar with colons in names

```bash
tar czf "09_18_2025_20:36:58.tar.gz" --force-local "09_18_2025_20:36:58"
```

## Requirements

- Linux host with Docker and Docker Compose plugin
- Open/forward the necessary ports on your firewall/router
  - Palworld: UDP 8211-8212, RCON TCP 25575
  - V Rising: UDP 9876-9877, RCON TCP 25576

## Repository layout

- `Dockerfile` – Generic SteamCMD + utilities image
- `palworld/` – Compose, scripts, files, backups for Palworld
- `vrising/` – Compose, scripts, files, backups for V Rising

## Quick start

### Palworld

1) Build and start

```bash
cd palworld
docker compose up -d --build
```

2) Default ports exposed

- UDP 8211-8212 (game)
- TCP 25575 (RCON)

3) Config and saves on the host

- Config: `palworld/files/Saved_Game/Config` -> container `/home/steam/serverdata/palworld/Pal/Saved/Config/LinuxServer`
- Saves: `palworld/files/Saved_Game/World/SaveGames` -> container `/home/steam/serverdata/palworld/Pal/Saved/SaveGames`
- Backups: `palworld/backups` (mounted as `/home/steam/PalWorldBackups`)

### V Rising

1) Build and start

```bash
cd vrising
docker compose up -d --build
```

2) Default ports exposed

- UDP 9876-9877 (game + query)
- TCP 25576 (RCON)

3) Saves/Config/Backups

- Container data root: `/home/steam/serverdata/vrising`
- Backups: `vrising/backups` (mounted as `/home/steam/VrisingBackups`)

```yaml
    command: /usr/local/src/vrising-scripts/run_server.sh
```

See `vrising/scripts/run_server.sh` for the exact behavior and environment it uses.

## Environment variables

Set in each `docker-compose.yml` and can be overridden via your shell or a `.env` file.

Common
- `DATA_DIR` – Base data directory (default `/home/steam/serverdata`)
- `STEAMCMD_DIR` – SteamCMD install dir
- `SERVER_DIR` – Game server directory under data dir
- `BACKUPS_DIR` – Where backups live inside the container
- `BACKUP_CRON_X` – Cron schedule for update/backup jobs (when enabled)
- `RCON_PASSWORD`, `RCON_PORT` – RCON auth and port

Palworld-specific (see `palworld/docker-compose.yml`)
- `GAME_ID=2394010`
- `GAME_EXECUTABLE=PalServer.sh`
- `GAME_SETTINGS_PATH=Pal/Saved/Config/LinuxServer/PalWorldSettings.ini`

V Rising–specific (see `vrising/docker-compose.yml`)
- `GAME_ID=1829350`
- `GAME_EXECUTABLE=VRisingServer.exe`
- `VR_GAME_PORT`, `VR_QUERY_PORT`
- `VR_RCON_ENABLED`, `VR_RCON_PORT`, `VR_RCON_PASSWORD`

Use shell exports to run one-off overrides:

```bash
export RCON_PASSWORD=changeme
export RCON_PORT=25575
docker compose up -d
```

## RCON testing (ARRCON)

The image includes ARRCON. Test from the host or inside the container.

Palworld examples

```bash
# save host (optional)
docker exec -it palworld-server ARRCON -P 25575 -p yourpass --save-host palworld

# broadcast a message
docker exec -it palworld-server ARRCON -P 25575 -p yourpass broadcast "Server restarting in 5 minutes"
```

V Rising examples

```bash
# save host (optional)
docker exec -it vrising-server ARRCON -P 25576 -p yourpass --save-host vrising

# announce to players
docker exec -it vrising-server ARRCON -P 25576 -p yourpass announce "Server restarting in 5 minutes"
```

## Backups and restore

Palworld
- Backups are placed under `palworld/backups` on the host and `/home/steam/PalWorldBackups` in the container.
- The Palworld entrypoint attempts to auto-restore the most recent dated archive named like `MM_DD_YYYY_HH:MM:SS.tar.gz`.

Manual restore snippet

```bash
# extract into server dir (inside container)
tar -xzf "/home/steam/PalWorldBackups/09_18_2025_20:36:58.tar.gz" --force-local -C "/home/steam/serverdata/palworld"

# move World and Config into place
cp -r "/home/steam/serverdata/palworld/09_18_2025_20:36:58/World/." \
   "/home/steam/serverdata/palworld/Pal/Saved/"
cp -r "/home/steam/serverdata/palworld/09_18_2025_20:36:58/Config/." \
   "/home/steam/serverdata/palworld/Pal/Saved/Config/LinuxServer/"
```

V Rising
- Backups live under `vrising/backups` on the host and `/home/steam/VrisingBackups` in the container.
- World saves and settings are under `/home/steam/serverdata/vrising/save-data`.

## Logs and admin

Follow logs

```bash
docker logs -f palworld-server
docker logs -f vrising-server
```

Enter a shell inside the container

```bash
docker exec -it palworld-server /bin/bash
docker exec -it vrising-server /bin/bash
```

## Service management inside the container (systemd)

Both stacks run under systemd-style services inside the container using a lightweight systemctl replacement. Key units and scripts are installed from `linux-steamcmd`:

- Services
   - `steamcmd_server.service` – launches the game via `START_CMD` (your `START_SCRIPT` or the computed executable command).
   - `steamcmd_server_update.service` – helper for save-and-update tasks.
- Cron
   - `/etc/cron.d/steamcmd_server_update` runs on the schedule in `BACKUP_CRON_X` and triggers update/backup routines.

Common control commands (run inside the container):

```bash
# status
systemctl status steamcmd_server
systemctl status steamcmd_server_update

# start/stop/restart game service
systemctl stop steamcmd_server
systemctl start steamcmd_server
systemctl restart steamcmd_server

# run the update job on-demand
systemctl start steamcmd_server_update

# view service logs (also see docker logs)
tail -f /var/log/journal/steamcmd_server.service.log
tail -f /var/log/journal/steamcmd_server_update.service.log
```

Tip: Stop `steamcmd_server` before manually editing saves/config, then start it again when done.

## Troubleshooting

- RCON won’t connect: confirm the container port mapping, firewall rules, and correct `-P` and `-p` for ARRCON. Prefer `localhost` from the host or run inside the container.
- Filenames with colons: use `--force-local` with `tar`, or avoid colons in names.
- Permission denied or operation not permitted on copy: stop the container if paths are in-use, use `cp -r` (not `-a`), and/or `chown` the destination.

## Notes

Other images exist; this setup is tailored to the author’s workflow and shared as-is.

## Contributing other games

Contributions to support more SteamCMD games are welcome. Keep it simple and consistent with the existing stacks.

Checklist for a new game stack
- Create a new folder at repo root (e.g., `mygame/`) with:
   - `docker-compose.yml` wiring build args and env vars
   - `scripts/` with an `entrypoint.sh` and/or `run_server.sh`
   - `files/` (optional host-mounted config/saves) and `backups/`
- Set compose build args: `GAME_NAME`, `GAME_ID`, `SERVER_SUBDIR`, `STEAMCMD_SUBDIR`, `GAME_EXECUTABLE`, and any `GAME_EXECUTABLE_PREFIX/POSTFIX` if needed (e.g., `xvfb`+`wine64`).
- Make sure `START_SCRIPT` is set if you want the systemd service to run your script; otherwise the computed executable command is used.
- Map volumes under `/home/steam/serverdata/<game>` for saves/config; keep paths consistent with `DATA_DIR`.
- Expose the correct ports (game/query), and add RCON env and examples if the game supports it (ARRCON works for many titles).
- Integrate backups/update scheduling via `BACKUP_CRON_X` if applicable (cron job is already present in the image); document any custom scripts.
- Test locally: `docker compose up -d --build`, verify logs, connectivity, saves, and RCON.

PR guidelines
- Keep dependencies minimal; prefer using the shared Dockerfile knobs (build args/env) over adding new packages.
- Include brief notes in the README sections (Quick start, Ports, Volumes, RCON, Backups) for the new game.
