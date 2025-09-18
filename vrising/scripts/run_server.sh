#!/usr/bin/env bash
set -euo pipefail

# Simple V Rising server runner (foreground)

# Basic config (override via environment)
SERVER_DIR=${SERVER_DIR:-/home/steam/serverdata/vrising}
EXECUTABLE=${GAME_EXECUTABLE_PATH:-${SERVER_DIR}/VRisingServer.exe}
SERVER_NAME=${VR_SERVER_NAME:-"My V Rising Server"}
SERVER_DESC=${VR_DESCRIPTION:-""}
SAVE_NAME=${VR_SAVE_NAME:-world1}
PERSISTENT_PATH="${SERVER_DIR}/save-data"
LOG_DIR="${SERVER_DIR}/logs"
LOG_FILE="${LOG_DIR}/VRisingServer.log"
USERNAME=${USERNAME:-""}
VALIDATE=${VALIDATE:-true}
# Ports and RCON from environment (defaults follow V Rising conventions)
GAME_PORT=${VR_GAME_PORT:-9876}
QUERY_PORT=${VR_QUERY_PORT:-9877}
LIST_ON_STEAM=${VR_LIST_ON_STEAM:-true}
MAX_USERS=${VR_MAX_USERS:-10}
MAX_ADMINS=${VR_MAX_ADMINS:-4}
RCON_ENABLED=${VR_RCON_ENABLED:-false}
RCON_PORT=${VR_RCON_PORT:-25575}
RCON_PASS=${VR_RCON_PASSWORD:-${RCON_PASSWORD:-}}
# Wine config
export WINEARCH=win64
export WINEPREFIX="${WINEPREFIX:-${SERVER_DIR}/WINE64}"
export WINEDEBUG=-all
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-mscoree,mshtml=}"

mkdir -p "${LOG_DIR}" "${PERSISTENT_PATH}" "${WINEPREFIX}"

# # Steamworks AppID and steamclient (best-effort)
# APPID=${GAME_ID:-1829350}
# echo "${APPID}" > "${SERVER_DIR}/steam_appid.txt"
# export SteamAppId="${APPID}"
# export SteamAppID="${APPID}"

echo "---Update Server---"
if [ "${USERNAME}" == "" ]; then
    if [ "${VALIDATE}" == "true" ]; then
    	echo "---Validating installation---"
        ${STEAMCMD_DIR}/steamcmd.sh \
        +@sSteamCmdForcePlatformType windows \
        +force_install_dir ${SERVER_DIR} \
        +login anonymous \
        +app_update ${GAME_ID} validate \
        +quit
    else
        ${STEAMCMD_DIR}/steamcmd.sh \
        +@sSteamCmdForcePlatformType windows \
        +force_install_dir ${SERVER_DIR} \
        +login anonymous \
        +app_update ${GAME_ID} \
        +quit
    fi
else
    if [ "${VALIDATE}" == "true" ]; then
    	echo "---Validating installation---"
        ${STEAMCMD_DIR}/steamcmd.sh \
        +@sSteamCmdForcePlatformType windows \
        +force_install_dir ${SERVER_DIR} \
        +login ${USERNAME} ${PASSWRD} \
        +app_update ${GAME_ID} validate \
        +quit
    else
        ${STEAMCMD_DIR}/steamcmd.sh \
        +@sSteamCmdForcePlatformType windows \
        +force_install_dir ${SERVER_DIR} \
        +login ${USERNAME} ${PASSWRD} \
        +app_update ${GAME_ID} \
        +quit
    fi
fi

# Initialize Wine prefix (best effort, non-fatal)
wineboot -u >/dev/null 2>&1 || true
wineserver -w 2>/dev/null || true

# Ensure default Settings exist under persistent data path
SETTINGS_DIR="${PERSISTENT_PATH}/Settings"
if [ ! -d "${SETTINGS_DIR}" ]; then
    mkdir -p "${PERSISTENT_PATH}"
    if [ -d "${SERVER_DIR}/VRisingServer_Data/StreamingAssets/Settings" ]; then
        cp -a "${SERVER_DIR}/VRisingServer_Data/StreamingAssets/Settings" "${PERSISTENT_PATH}/"
    else
        mkdir -p "${SETTINGS_DIR}"
    fi
fi

# Write ServerHostSettings.json with compose-provided ports and options
HOST_CFG="${SETTINGS_DIR}/ServerHostSettings.json"
cat >"${HOST_CFG}" <<EOF
{
    "Name": ${SERVER_NAME@Q},
    "Description": ${SERVER_DESC@Q},
    "Port": ${GAME_PORT},
    "QueryPort": ${QUERY_PORT},
    "MaxConnectedUsers": ${MAX_USERS},
    "MaxConnectedAdmins": ${MAX_ADMINS},
    "SaveName": ${SAVE_NAME@Q},
    "ListOnSteam": ${LIST_ON_STEAM},
    "Password": ${VR_PASSWORD+${VR_PASSWORD@Q}},
    "Rcon": {
        "Enabled": ${RCON_ENABLED},
        "Port": ${RCON_PORT},
        "Password": ${RCON_PASS+${RCON_PASS@Q}}
    },
    "API": {}
}
EOF

# Run server (background), then stream the log to foreground
echo "---Launching VRisingServer (ports: ${GAME_PORT}/${QUERY_PORT} UDP, RCON: ${RCON_PORT})---"
xvfb-run wine64 "${EXECUTABLE}" \
    -persistentDataPath "${PERSISTENT_PATH}" \
    -serverName "${SERVER_NAME}" \
    -saveName "${SAVE_NAME}" \
    -logFile "${LOG_FILE}" \
    ${SERVER_DESC:+-description "${SERVER_DESC}"} &
SRV_PID=$!
sleep 2

trap 'kill ${SRV_PID} 2>/dev/null || true; wait ${SRV_PID} 2>/dev/null || true; kill ${TAIL_PID} 2>/dev/null || true' INT TERM
wait ${SRV_PID}
