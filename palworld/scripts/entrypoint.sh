#!/usr/bin/env bash
set -euo pipefail

log(){ echo "[ENTRYPOINT] $*"; }

log '--- DEBUG ENV (container runtime) ---'
log "SERVER_DIR=${SERVER_DIR:-}"
log "GAME_EXECUTABLE=${GAME_EXECUTABLE:-}"
log "GAME_SETTINGS_PATH=${GAME_SETTINGS_PATH:-}"
log "RCON_PORT=${RCON_PORT:-}"
log "RCON_PASSWORD=${RCON_PASSWORD:-}"
log "GAME_NAME=${GAME_NAME:-}"
log '-------------------------------------'

# Ensure required vars
if [[ -z "${SERVER_DIR:-}" || -z "${GAME_EXECUTABLE:-}" ]]; then
  log 'SERVER_DIR or GAME_EXECUTABLE is empty.'
  exit 1
fi

marker="${SERVER_DIR}/.palworld_initialized"
if [[ ! -f "${marker}" ]]; then

    # Register ARRCON host if possible
    if [[ -n "${RCON_PORT:-}" && -n "${RCON_PASSWORD:-}" && -n "${GAME_NAME:-}" ]]; then
    if command -v ARRCON >/dev/null 2>&1; then
        log 'exit' | ARRCON -P "${RCON_PORT}" -p "${RCON_PASSWORD}" --save-host "${GAME_NAME}" || true
    else
        log 'ARRCON binary not found.'
    fi
    else
    log 'ARRCON not run: missing RCON_PORT, RCON_PASSWORD, or GAME_NAME.'
    fi

    full_path="${SERVER_DIR}/${GAME_EXECUTABLE}"
    if [[ ! -f "${full_path}" ]]; then
        log " Configured executable not found: ${full_path}"
        log "Listing server dir for inspection:" >&2
        ls -la "${SERVER_DIR}" >&2 || true
        candidate=$(ls -1 "${SERVER_DIR}" | grep -E '^(PalServer|PalworldServer)\.sh$' || true)
        if [[ -n "${candidate}" ]]; then
            log " Using detected executable: ${candidate}" >&2
            full_path="${SERVER_DIR}/${candidate}"
        fi
    fi

    if [[ ! -x "${full_path}" ]]; then
        log " Executable missing or not executable: ${full_path}" >&2
        exit 127
    fi

    log " First-time initialization: launching for 10 seconds to generate files."
    "${full_path}" &
    pid=$!
    sleep 10
    if kill -0 "${pid}" 2>/dev/null; then
        log " Stopping initialization process (PID ${pid})."
        kill "${pid}" 2>/dev/null || true
        for _ in 1 2 3 4 5; do
            if kill -0 "${pid}" 2>/dev/null; then
                sleep 1
            else
                break
            fi
        done
        if kill -0 "${pid}" 2>/dev/null; then
            log " Force killing process (PID ${pid})."
            kill -9 "${pid}" 2>/dev/null || true
        fi
    else
        log " Process exited before 10s wait."
    fi

    # Load most recent dated backup if available
    backup_dir="${HOME}/${BACKUPS_DIR}"
    if [[ -d "${backup_dir}" ]]; then
        log " Looking for most recent dated backup in: ${backup_dir}"
        latest_backup=$(ls -1 "${backup_dir}" | grep -E '^?[0-9]{2}_[0-9]{2}_[0-9]{4}_[0-9]{2}:[0-9]{2}:[0-9]{2}\.tar\.gz$' | sort -r | head -n1 || true)
        log " Found backup: ${latest_backup:-<none>}"
        if [[ -n "${latest_backup}" ]]; then
            log " Restoring most recent backup: ${latest_backup}"
        log " Extracting backup..."
        tar -xzf "${backup_dir}/${latest_backup}" -C "${SERVER_DIR}" || log " Failed to extract backup."
        log " Moving World files..."
        cp -r "${SERVER_DIR}/$(basename "${latest_backup}" .tar.gz)"/World/. "${SERVER_DIR}/Pal/Saved/" || log " Failed to move World files."
        log " Moving Config files..."
        cp -r "${SERVER_DIR}/$(basename "${latest_backup}" .tar.gz)"/Config/. "${SERVER_DIR}/Pal/Saved/Config/LinuxServer/" || log " Failed to move Config files."
        else
            log " No dated backup found in ${backup_dir}"
        fi
    else
        log " Backup directory not found: ${backup_dir}"
    fi
    touch "${marker}"
    log " Initialization complete."
fi

# Ensure steamcmd related services are enabled and running
if command -v systemctl >/dev/null 2>&1; then
    PRSV_BROADCAST_OPTION=${BROADCAST_MAINTENANCE:-true}
    export BROADCAST_MAINTENANCE=false
    for svc in steamcmd_server steamcmd_server_update; do
        if ! systemctl is-enabled --quiet "${svc}"; then
            log " Enabling service: ${svc}"
            systemctl enable "${svc}" >/dev/null 2>&1 || log " Failed to enable ${svc}"
        fi
        if ! systemctl is-active --quiet "${svc}"; then
            log " Starting service: ${svc}"
            systemctl start "${svc}" >/dev/null 2>&1 || log " Failed to start ${svc}"
        else
            log " Service already active: ${svc}"
        fi
    done
    # Start cron if available (for scheduled updates)
    if command -v cron >/dev/null 2>&1; then
      log "Enabling and starting cron service"
      sudo sh -c '/usr/sbin/cron -f >> /var/log/cron.log 2>&1 &'
    else
      log "cron not available; skipping cron service."
    fi
    systemctl daemon-reload || true
    export BROADCAST_MAINTENANCE=${PRSV_BROADCAST_OPTION}
else
    log " systemd not available; skipping steamcmd services."
fi

# Start an interactive login shell so env/profile scripts run.
exec /bin/bash -l
