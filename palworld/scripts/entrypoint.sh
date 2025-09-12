#!/usr/bin/env bash
set -euo pipefail

echo '--- DEBUG ENV (container runtime) ---'
echo "SERVER_DIR=${SERVER_DIR:-}"
echo "GAME_EXECUTABLE=${GAME_EXECUTABLE:-}"
echo "GAME_SETTINGS_PATH=${GAME_SETTINGS_PATH:-}"
echo "RCON_PORT=${RCON_PORT:-}"
echo "RCON_PASSWORD=${RCON_PASSWORD:-}"
echo "GAME_NAME=${GAME_NAME:-}"
echo '-------------------------------------'

# Ensure required vars
if [[ -z "${SERVER_DIR:-}" || -z "${GAME_EXECUTABLE:-}" ]]; then
  echo '[palworld-entrypoint] SERVER_DIR or GAME_EXECUTABLE is empty.'
  exit 1
fi

marker="${SERVER_DIR}/.palworld_initialized"
if [[ ! -f "${marker}" ]]; then
    # Create needed directories
    mkdir -p "${SERVER_DIR}/Pal/Saved/World/SaveGames" \
            "${SERVER_DIR}/Pal/Saved/Config/LinuxServer" || true

    # Copy settings if present
    if [[ -n "${MIGRATION_SETTINGS_PATH:-}" && -f \
        "/home/steam/Saved_Game/${MIGRATION_SETTINGS_PATH}" ]]; then
    target_dir="${SERVER_DIR}/$(dirname "${GAME_SETTINGS_PATH:-}")"
    mkdir -p "${target_dir}" || true
    cp "/home/steam/Saved_Game/${MIGRATION_SETTINGS_PATH}" \
        "${SERVER_DIR}/${GAME_SETTINGS_PATH:-}"
    echo '[palworld-entrypoint] Copied settings file.'
    else
    echo '[palworld-entrypoint] Settings file missing, skipping copy.'
    fi

    # Register ARRCON host if possible
    if [[ -n "${RCON_PORT:-}" && -n "${RCON_PASSWORD:-}" && -n "${GAME_NAME:-}" ]]; then
    if command -v ARRCON >/dev/null 2>&1; then
        echo 'exit' | ARRCON -P "${RCON_PORT}" -p "${RCON_PASSWORD}" --save-host "${GAME_NAME}" || true
    else
        echo '[palworld-entrypoint] ARRCON binary not found.'
    fi
    else
    echo '[palworld-entrypoint] ARRCON not run: missing RCON_PORT, RCON_PASSWORD, or GAME_NAME.'
    fi

    full_path="${SERVER_DIR}/${GAME_EXECUTABLE}"
    if [[ ! -f "${full_path}" ]]; then
        echo "[palworld-entrypoint] Configured executable not found: ${full_path}" >&2
        echo "Listing server dir for inspection:" >&2
        ls -la "${SERVER_DIR}" >&2 || true
        candidate=$(ls -1 "${SERVER_DIR}" | grep -E '^(PalServer|PalworldServer)\.sh$' || true)
        if [[ -n "${candidate}" ]]; then
            echo "[palworld-entrypoint] Using detected executable: ${candidate}" >&2
            full_path="${SERVER_DIR}/${candidate}"
        fi
    fi

    if [[ ! -x "${full_path}" ]]; then
        echo "[palworld-entrypoint] Executable missing or not executable: ${full_path}" >&2
        exit 127
    fi

    echo "[palworld-entrypoint] First-time initialization: launching for 10 seconds to generate files."
    "${full_path}" &
    pid=$!
    sleep 10
    if kill -0 "${pid}" 2>/dev/null; then
        echo "[palworld-entrypoint] Stopping initialization process (PID ${pid})."
        kill "${pid}" 2>/dev/null || true
        for _ in 1 2 3 4 5; do
            if kill -0 "${pid}" 2>/dev/null; then
                sleep 1
            else
                break
            fi
        done
        if kill -0 "${pid}" 2>/dev/null; then
            echo "[palworld-entrypoint] Force killing process (PID ${pid})."
            kill -9 "${pid}" 2>/dev/null || true
        fi
    else
        echo "[palworld-entrypoint] Process exited before 10s wait."
    fi
    touch "${marker}"
    echo "[palworld-entrypoint] Initialization complete."
fi

# Ensure steamcmd related services are enabled and running
if command -v systemctl >/dev/null 2>&1; then
    for svc in steamcmd_server steamcmd_server_update; do
        if ! systemctl is-enabled --quiet "${svc}"; then
            echo "[palworld-entrypoint] Enabling service: ${svc}"
            systemctl enable "${svc}" >/dev/null 2>&1 || echo "[palworld-entrypoint] Failed to enable ${svc}"
        fi
        if ! systemctl is-active --quiet "${svc}"; then
            echo "[palworld-entrypoint] Starting service: ${svc}"
            systemctl start "${svc}" >/dev/null 2>&1 || echo "[palworld-entrypoint] Failed to start ${svc}"
        else
            echo "[palworld-entrypoint] Service already active: ${svc}"
        fi
    done
    systemctl daemon-reload || true
else
    echo "[palworld-entrypoint] systemd not available; skipping steamcmd services."
fi

# Start an interactive login shell so env/profile scripts run.
exec /bin/bash -l
