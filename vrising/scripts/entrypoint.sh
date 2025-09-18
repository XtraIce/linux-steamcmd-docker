#!/usr/bin/env bash
# V Rising entrypoint (init-only mode)
# Performs an optional short initialization run of the server to generate
# data, then keeps the container alive WITHOUT running the server again.
#
# Behavior controls:
#   INIT_RUN_SECONDS (int, default 30)  Duration of initial run; 0 = skip running server.
#   USE_BATCH=1                        Use start_server.bat instead of direct exe.
#   POST_INIT_MODE=idle|exit|shell     Action after init (default: idle)
#       idle  => sleep forever (container stays healthy)
#       exit  => container exits 0 after init
#       shell => interactive shell

if [ -n "${BASH_VERSION:-}" ]; then
  set -o pipefail
fi

MARKER_FILE="${SERVER_DIR}/.vrising_initialized"
INIT_RUN_SECONDS="${INIT_RUN_SECONDS:-0}"
POST_INIT_MODE="${POST_INIT_MODE:-idle}"

mkdir -p "${SERVER_DIR}" "${SERVER_DIR}/save-data" "${SERVER_DIR}/logs"
cd "${SERVER_DIR}"

if [ ! -f "start_server.bat" ] && [ -f "start_server_example.bat" ]; then
  cp start_server_example.bat start_server.bat
fi

SERVER_NAME=${SERVER_NAME:-${VR_SERVER_NAME:-"My V Rising Server"}}
SAVE_NAME=${SAVE_NAME:-${VR_SAVE_NAME:-"world1"}}
DESCRIPTION=${VR_DESCRIPTION:-""}
EXECUTABLE="${GAME_EXECUTABLE_PATH}"
LOG_FILE="${SERVER_DIR}/logs/VRisingServer.log"
PERSISTENT_PATH="${SERVER_DIR}/save-data"

log(){ echo "[ENTRYPOINT] $*"; }

export WINEARCH=win64
export WINEPREFIX="${SERVER_DIR}/WINE64"
echo "---Ensuring WINE workdirectory is present and owned by current user---"
mkdir -p "${WINEPREFIX}"
chown -R "$(id -u)":"$(id -g)" "${WINEPREFIX}" 2>/dev/null || true
echo "---Checking if WINE is properly installed---"
if [ ! -d ${WINEPREFIX}/drive_c/windows ]; then
	echo "---Setting up WINE---"
    cd ${SERVER_DIR}
    wineboot -u > /dev/null 2>&1
    sleep 15
else
	echo "---WINE properly set up---"
fi
echo "---Checking for old display lock files---"
find /tmp -name ".X99*" -exec rm -f {} \; > /dev/null 2>&1
# Ensure X11 socket dir exists with proper perms for Xvfb
mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix || true
# Normalize permissions on data dir (best-effort)
if [ -n "${DATA_DIR:-}" ]; then
  mkdir -p "${DATA_DIR}"
  chown -R "$(id -u)":"$(id -g)" "${DATA_DIR}" 2>/dev/null || true
  chmod -R 770 "${DATA_DIR}" 2>/dev/null || true
fi
echo "---Server ready---"

run_init_server(){
  log "Init run starting (duration=${INIT_RUN_SECONDS}s, mode=${USE_BATCH:-exe})"
  # Pick display (default :99) unless already set; if in use, bump.
  BASE_DISPLAY_NUM=${INIT_DISPLAY_BASE:-99}
  if [ -n "${DISPLAY:-}" ]; then
    DISP_NUM="${DISPLAY#:}"
  else
    for try in $(seq 0 10); do
      test ! -e "/tmp/.X$((BASE_DISPLAY_NUM+try))-lock" && { DISP_NUM=$((BASE_DISPLAY_NUM+try)); break; }
    done
    DISPLAY=":${DISP_NUM}"; export DISPLAY
  fi
  log "Using DISPLAY=${DISPLAY}"

  # Start Xvfb manually for full control (avoid xvfb-run zombies)
  Xvfb "${DISPLAY}" -screen 0 1640x480x24:32 -nolisten tcp &
  XVFB_PID=$!
  sleep 1
  if ! kill -0 ${XVFB_PID} 2>/dev/null; then
    log "Failed to start Xvfb (pid ${XVFB_PID}). Skipping init run but keeping container alive."
    return 0
  fi

  # Start server
  if [ "${USE_BATCH:-0}" = "1" ]; then
    wine cmd /c start_server.bat &
  else
    wine64 "${EXECUTABLE}" \
      -persistentDataPath "${PERSISTENT_PATH}" \
      -serverName "${SERVER_NAME}" \
      -saveName "${SAVE_NAME}" \
      -logFile "${LOG_FILE}" \
      ${DESCRIPTION:+-description "${DESCRIPTION}"} &
  fi
  SRV_PID=$!

  # Trap to ensure cleanup even if script interrupted
  cleanup_init(){
    log "Cleanup: stopping server PID ${SRV_PID} and Xvfb PID ${XVFB_PID}"
    kill ${SRV_PID} 2>/dev/null || true
    wait ${SRV_PID} 2>/dev/null || true
    if command -v wineserver >/dev/null 2>&1; then wineserver -k || true; wineserver -w || true; fi
    kill ${XVFB_PID} 2>/dev/null || true
    wait ${XVFB_PID} 2>/dev/null || true
  }
  trap cleanup_init INT TERM EXIT

  sleep "${INIT_RUN_SECONDS}" || true
  log "Stopping init server (PID ${SRV_PID})"
  kill ${SRV_PID} 2>/dev/null || true
  for i in 1 2 3; do kill -0 ${SRV_PID} 2>/dev/null || break; sleep 1; done
  kill -0 ${SRV_PID} 2>/dev/null && kill -9 ${SRV_PID} 2>/dev/null || true
  if command -v wineserver >/dev/null 2>&1; then wineserver -k || true; wineserver -w || true; fi
  kill ${XVFB_PID} 2>/dev/null || true
  for i in 1 2 3; do kill -0 ${XVFB_PID} 2>/dev/null || break; sleep 1; done
  kill -0 ${XVFB_PID} 2>/dev/null && kill -9 ${XVFB_PID} 2>/dev/null || true
  wait ${SRV_PID} 2>/dev/null || true
  wait ${XVFB_PID} 2>/dev/null || true
  trap - INT TERM EXIT
  log "Init run complete and processes reaped."
}

# Ensure no orphan Xvfb instances remain (common when aborting xvfb-run early)
cleanup_xvfb(){
  [ "${NO_XVFB_CLEANUP:-0}" = "1" ] && return 0
  pkill -f '^Xvfb :' 2>/dev/null || true
  # Remove leftover lock sockets from manual Xvfb starts
  rm -rf /tmp/.X*-lock /tmp/.X11-unix/* /tmp/xvfb-run.* 2>/dev/null || true
  log "Xvfb cleanup done."
}

init_migrate_world_save(){
  if [ -d "${MIGRATION_DATA_CNTR_DIR}" ] && [ "$(ls -A ${MIGRATION_DATA_CNTR_DIR} 2>/dev/null | wc -l)" -gt 0 ]; then
    log "Migration data directory found and not empty: ${MIGRATION_DATA_CNTR_DIR}"
    log "Copying migration data to save-data directory: ${PERSISTENT_PATH}"
    mkdir -p "${PERSISTENT_PATH}/Saves/v4/${SAVE_NAME}" "${PERSISTENT_PATH}/Settings"
    # Find the AutoSave_ file with the highest number and copy it
    latest_autosave=$(ls -1 ${MIGRATION_DATA_CNTR_DIR}/${SAVE_NAME}/AutoSave_* 2>/dev/null | sort -V | tail -n 1)
    if [ -n "${latest_autosave}" ] && [ -f "${latest_autosave}" ]; then
      cp "${latest_autosave}" \
         "${MIGRATION_DATA_CNTR_DIR}/${SAVE_NAME}/SessionId.json" \
         "${MIGRATION_DATA_CNTR_DIR}/${SAVE_NAME}/StartDate.json" \
         "${PERSISTENT_PATH}/Saves/v4/${SAVE_NAME}/" #2>/dev/null || log "Failed to migrate world save!"
      echo "Migrated world save files: ${MIGRATION_DATA_CNTR_DIR}/${SAVE_NAME}/"
      ls "${MIGRATION_DATA_CNTR_DIR}/${SAVE_NAME}/" || true
      cp ${MIGRATION_DATA_CNTR_DIR}/${SAVE_NAME}/Server* "${PERSISTENT_PATH}/Settings/" 2>/dev/null || log "No Server settings files found to migrate."
      
    else
      log "No World save found to migrate."
    fi
    log "Migration data copy complete."
  else
    log "No migration data directory found or it is empty: ${MIGRATION_DATA_CNTR_DIR}"
  fi
}

enable_services() {
      
  # Ensure steamcmd related services are enabled and running
if command -v systemctl >/dev/null 2>&1; then
  for svc in steamcmd_server steamcmd_server_update; do
    if ! systemctl is-enabled --quiet "${svc}"; then
        log "Enabling service: ${svc}"
        systemctl enable "${svc}" >/dev/null 2>&1 || log "Failed to enable ${svc}"
    fi
    if ! systemctl is-active --quiet "${svc}"; then
        log "Starting service: ${svc}"
        systemctl start "${svc}" >/dev/null 2>&1 || log "Failed to start ${svc}"
    else
        log "Service already active: ${svc}"
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
else
    log "systemd not available; skipping steamcmd services."
fi
}

if [ ! -f "${MARKER_FILE}" ]; then
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

  init_migrate_world_save || true
  if [ "${INIT_RUN_SECONDS}" -gt 0 ]; then
  run_init_server || true
  else
    log "INIT_RUN_SECONDS=0 -> skipping init run"
    enable_services
    log "Enabled steamcmd services."
  fi
  touch "${MARKER_FILE}" || true
  log "Initialization complete. Marker created."
  cleanup_xvfb
else
  log "Initialization already done (marker present). Skipping init run."
  cleanup_xvfb
fi

case "${POST_INIT_MODE}" in
  exit)
    log "POST_INIT_MODE=exit requested; overriding to idle to prevent container restart."
    ;&
  shell)
    log "POST_INIT_MODE=shell -> starting interactive shell"
    exec /bin/sh -i
    ;;
  idle|*)
    log "POST_INIT_MODE=idle -> entering reaper idle loop (prevents zombies)."
    # Reap any future stray children (Wine helper processes finishing late)
    while true; do
      # wait -n reaps one exited child; if none, sleep
      if ! wait -n 2>/dev/null; then
        sleep 30
      fi
    done
    ;;
esac