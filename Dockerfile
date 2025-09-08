# syntax=docker/dockerfile:1.7-labs
FROM ubuntu

LABEL version="1.0"
LABEL description="Docker image for SteamCMD Game Server"
LABEL maintainer = ["Riker Q."]

# Build arguments (override via docker-compose build.args)
ARG APP_USER=steam
ARG BACKUPS_DIR=GenericBackups
ARG DATA_DIR=/home/steam/serverdata
ARG GAME_EXECUTABLE=Executable.sh
ARG GAME_ID=0000000
ARG GAME_NAME=game
ARG GAME_SETTINGS_PATH=GameSettings.ini
ARG RCON_PASSWORD=password
ARG RCON_PORT=25575
ARG REQUIRED_SCRIPT=""
ARG MIGRATION_DATA_DIR=./files
ARG SAVED_GAME_DIR=Saved/SaveGames
ARG SAVED_GAME_HASH_DIR=0
ARG SERVER_SUBDIR=gameserver
ARG STEAMCMD_SUBDIR=steamcmd

# Runtime environment (export build args for container use)
ENV APP_USER=$APP_USER \
    BACKUPS_DIR=$BACKUPS_DIR \
    DATA_DIR=$DATA_DIR \
    GAME_EXECUTABLE_PATH=${DATA_DIR}/${GAME_NAME}/${GAME_EXECUTABLE} \
    GAME_ID=$GAME_ID \
    GAME_NAME=$GAME_NAME \
    GAME_SETTINGS_PATH=$GAME_SETTINGS_PATH \
    HOME=/home/steam \
    RCON_PASSWORD=$RCON_PASSWORD \
    RCON_PORT=$RCON_PORT \
    REQUIRED_SCRIPT=$REQUIRED_SCRIPT \
    MIGRATION_DATA_DIR=$MIGRATION_DATA_DIR \
    SAVED_GAME_DIR=$SAVED_GAME_DIR \
    SAVED_GAME_HASH_DIR=$SAVED_GAME_HASH_DIR \
    SERVER_DIR=$DATA_DIR/$SERVER_SUBDIR \
    STEAMCMD_DIR=$DATA_DIR/$STEAMCMD_SUBDIR \
    STEAM_DIR=/home/steam/steam

# NOTE: APP_NAME intentionally omitted; compute at runtime if needed: APP_NAME="${GAME_NAME}-server"

RUN apt-get update && apt-get -y upgrade \
    && apt-get -y install lib32gcc-s1 libc6-i386 wget apt-utils git systemd curl unzip sudo python3 net-tools nano cron \
    && useradd -ms /bin/bash ${APP_USER} \
    && echo "${APP_USER}:${APP_USER}" | chpasswd

# If REQUIRED_SCRIPT is provided, copy & execute it (e.g., Wine install). Silently skip if empty
COPY ${REQUIRED_SCRIPT} /tmp/
RUN if [ -n "${REQUIRED_SCRIPT}" ] && [ -f "/tmp/${REQUIRED_SCRIPT}" ]; then \
            chmod +x "/tmp/${REQUIRED_SCRIPT}" && /tmp/${REQUIRED_SCRIPT}; \
        else \
            echo "[INFO] No REQUIRED_SCRIPT provided or file missing. Skipping."; \
        fi
# run sudo without password
RUN echo "steam ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers \ 
    && usermod -aG sudo steam
WORKDIR /home/steam

RUN mkdir $DATA_DIR \
    && mkdir $STEAMCMD_DIR \
    && mkdir $SERVER_DIR \
    && mkdir $STEAM_DIR \
    && mkdir $STEAM_DIR/appinfo \
    && mkdir ${DATA_DIR}/repos

#Copy repos
RUN git clone https://github.com/XtraIce/linux-steamcmd.git ${DATA_DIR}/repos/linux-steamcmd \
    && git clone https://github.com/gdraheim/docker-systemctl-replacement.git ${DATA_DIR}/repos/docker-systemctl-replacement\
    && cat ${DATA_DIR}/repos/linux-steamcmd/steamcmd_server.service

#Curl get ARRCON-3.3.7-Linux.zip
RUN curl -L -o ${DATA_DIR}/ARRCON.zip https://github.com/radj307/ARRCON/releases/download/3.3.7/ARRCON-3.3.7-Linux.zip \
    && unzip ${DATA_DIR}/ARRCON.zip -d ${DATA_DIR}/repos/ARRCON \
    && cp ${DATA_DIR}/repos/ARRCON/ARRCON /usr/bin/ARRCON
#Copy scripts
RUN chown -R ${APP_USER} ${DATA_DIR}/repos/ \
    && chmod +x ${DATA_DIR}/repos/linux-steamcmd/QueryUpdateAvailable.sh \
    && chmod +x ${DATA_DIR}/repos/linux-steamcmd/SaveAndUpdate.sh \
    && cp ${DATA_DIR}/repos/linux-steamcmd/steamcmd_server* /etc/systemd/system/ \
    && cp ${DATA_DIR}/repos/linux-steamcmd/etc/cron.d/steamcmd_server_update /etc/cron.d/steamcmd_server_update \
    && chmod 644 /etc/cron.d/steamcmd_server_update \
    && cp ${DATA_DIR}/repos/docker-systemctl-replacement/files/docker/systemctl3.py /usr/bin/systemctl \
    #write sed command to replace "$EXECPATH" variable in steamcmd_server.service file with "${GAME_EXECUTABLE_PATH}"
    && sed -i "s|\$EXECPATH|${GAME_EXECUTABLE_PATH}|g" /etc/systemd/system/steamcmd_server.service \
    #write sed command to replace "$EXECPATH" variable in steamcmd_server_update.service file with "${DATA_DIR}/repos/linux-steamcmd"
    && sed -i "s|\$EXECPATH|${DATA_DIR}/repos/linux-steamcmd|g" /etc/systemd/system/steamcmd_server_update.service \
    #write sed command to replace "game_server" in SaveAndUpdate.sh file with "${GAME_NAME}"
    && sed -i "s|game_server|${GAME_NAME}|g" ${DATA_DIR}/repos/linux-steamcmd/SaveAndUpdate.sh \
    #Append global environment variables to /etc/environment
    && echo "DATA_DIR=${DATA_DIR}" >> /etc/environment
#Install SteamCMD
RUN wget -q -O ${STEAMCMD_DIR}/steamcmd_linux.tar.gz http://media.steampowered.com/client/steamcmd_linux.tar.gz \
    &&  tar --directory ${STEAMCMD_DIR} -xvzf ${STEAMCMD_DIR}/steamcmd_linux.tar.gz \
    &&  rm ${STEAMCMD_DIR}/steamcmd_linux.tar.gz \
    &&  chmod -R 774 $STEAMCMD_DIR  $SERVER_DIR 

RUN --mount=type=cache,target=${STEAMCMD_DIR}/steamapps \
        --mount=type=cache,target=/root/.steam \
        ${STEAMCMD_DIR}/steamcmd.sh \
            +login anonymous \
            +app_update 1007 validate \
            +quit
# make .steam/sdk64 dir and cp steamclient.so from steamcmd dir
RUN ls -la $HOME/steam/steamapps/common
RUN mkdir -p .steam/sdk64 \
    && cp ${STEAM_DIR}/steamapps/common/Steamworks\ SDK\ Redist/linux64/steamclient.so ${HOME}/.steam/sdk64/steamclient.so \
    && ln -s ${STEAMCMD_DIR}/linux32/steamclient.so ${STEAMCMD_DIR}/linux32/steamservice.so

#Install GameServer
# Use BuildKit cache mounts so SteamCMD content persists across rebuilds
RUN --mount=type=cache,target=${STEAMCMD_DIR}/steamapps \
        --mount=type=cache,target=/root/.steam \
        ${STEAMCMD_DIR}/steamcmd.sh \
            +force_install_dir $SERVER_DIR \
            +login anonymous \
            +app_update $GAME_ID \
            +quit
RUN chown -R ${APP_USER} ${HOME} \
    && ls -la ${SERVER_DIR}

COPY ${MIGRATION_DATA_DIR} /home/steam

# Copy entrypoint scripts (game-specific helpers) if present
COPY scripts/palworld-entrypoint.sh /usr/local/bin/palworld-entrypoint
RUN chmod +x /usr/local/bin/palworld-entrypoint && chown ${APP_USER}:${APP_USER} /usr/local/bin/palworld-entrypoint

USER ${APP_USER}
# Game-specific runtime initialization (e.g., Palworld settings copy) moved to docker-compose command.

USER root
#Change values for Server Specs (1Gb = 1024Mb)
RUN ulimit -m 28672 && ulimit -v 28672 && ulimit -n 2048

RUN mkdir -p /var/log/journal \
 && touch /var/log/journal/steamcmd_server.service.log \
 && touch /var/log/journal/steamcmd_server_update.service.log \
 && chown -R ${APP_USER}:${APP_USER} /var/log/journal \
 && chmod 664 /var/log/journal/steamcmd_server.service.log /var/log/journal/steamcmd_server_update.service.log \
 && systemctl enable steamcmd_server.service
CMD ["/usr/bin/systemctl", "init"]

USER steam
