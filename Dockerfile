FROM ubuntu

LABEL version="1.0"
LABEL description="Docker image for Palworld"
LABEL maintainer = ["Riker"]

ENV APP_USER="steam" 
ENV HOME="/home/steam"
ENV DATA_DIR="$HOME/serverdata"
ENV STEAM_DIR="$HOME/steam"
ENV STEAMCMD_DIR="${DATA_DIR}/steamcmd"
ENV SERVER_DIR="${DATA_DIR}/palworld"
ENV GAME_ID="2394010"
ENV GAME_NAME="palworld"
ENV RCON_PORT="25575"
ENV RCON_PASSWORD="password"
ENV SAVED_GAME_DIR="./files"
ENV SAVED_GAME_HASH_DIR="0"

RUN apt-get update && apt-get -y upgrade \
    && apt-get -y install lib32gcc-s1 libc6-i386 wget apt-utils git systemd curl unzip sudo python3 net-tools nano \
    && useradd -ms /bin/bash ${APP_USER} \
    && echo "${APP_USER}:${APP_USER}" | chpasswd
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
    && cat ${DATA_DIR}/repos/linux-steamcmd/palworld.service

#Curl get ARRCON-3.3.7-Linux.zip
RUN curl -L -o ${DATA_DIR}/ARRCON.zip https://github.com/radj307/ARRCON/releases/download/3.3.7/ARRCON-3.3.7-Linux.zip \
    && unzip ${DATA_DIR}/ARRCON.zip -d ${DATA_DIR}/repos/ARRCON \
    && cp ${DATA_DIR}/repos/ARRCON/ARRCON /usr/bin/ARRCON
#Copy scripts
RUN chown -R ${APP_USER} ${DATA_DIR}/repos/ \
    && chmod +x ${DATA_DIR}/repos/linux-steamcmd/QueryUpdateAvailable.sh \
    && chmod +x ${DATA_DIR}/repos/linux-steamcmd/SaveAndUpdate.sh \
    && cp ${DATA_DIR}/repos/linux-steamcmd/palworld* /etc/systemd/system/ \
    && cp ${DATA_DIR}/repos/docker-systemctl-replacement/files/docker/systemctl3.py /usr/bin/systemctl \
    #write sed command to replace "$EXECPATH" variable in palworld.service file with "${STEAM_DIR}/palworld"
    && sed -i "s|\$EXECPATH|${SERVER_DIR}|g" /etc/systemd/system/palworld.service \
    #write sed command to replace "$EXECPATH" variable in palworld_update.service file with "${DATA_DIR}/repos/linux-steamcmd"
    && sed -i "s|\$EXECPATH|${DATA_DIR}/repos/linux-steamcmd|g" /etc/systemd/system/palworld_update.service \
    #Append global environment variables to /etc/environment
    && echo "DATA_DIR=${DATA_DIR}" >> /etc/environment
#Install SteamCMD
RUN wget -q -O ${STEAMCMD_DIR}/steamcmd_linux.tar.gz http://media.steampowered.com/client/steamcmd_linux.tar.gz \
    &&  tar --directory ${STEAMCMD_DIR} -xvzf ${STEAMCMD_DIR}/steamcmd_linux.tar.gz \
    &&  rm ${STEAMCMD_DIR}/steamcmd_linux.tar.gz \
    &&  chmod -R 774 $STEAMCMD_DIR  $SERVER_DIR 

RUN ${STEAMCMD_DIR}/steamcmd.sh \
    +login anonymous \
    +app_update 1007 validate \
    +quit
# make .steam/sdk64 dir and cp steamclient.so from steamcmd dir
RUN ls -la $HOME/steam/steamapps/common
RUN mkdir -p .steam/sdk64 \
    && cp ${STEAM_DIR}/steamapps/common/Steamworks\ SDK\ Redist/linux64/steamclient.so ${HOME}/.steam/sdk64/steamclient.so \
    && ln -s ${STEAMCMD_DIR}/linux32/steamclient.so ${STEAMCMD_DIR}/linux32/steamservice.so

#Install Palworld
RUN ${STEAMCMD_DIR}/steamcmd.sh \
    +force_install_dir $SERVER_DIR \
    +login anonymous \
    +app_update $GAME_ID \
    +quit
RUN chown -R ${APP_USER} ${HOME} \
    && ls -la ${SERVER_DIR}

COPY ${SAVED_GAME_DIR} /home/steam

USER ${APP_USER}
RUN echo "${SERVER_DIR}/PalServer.sh &" > $HOME/start.sh \
    && chmod +x $HOME/start.sh \
    && ${HOME}/start.sh \
    && sleep 10 \
    && ps -e
RUN mkdir -p ${SERVER_DIR}/Pal/Saved/World/SaveGames \ 
    && cp /home/steam/Saved_Game/Config/PalWorldSettings.ini $SERVER_DIR/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini \
    && echo "exit" | ARRCON -P $RCON_PORT -p $RCON_PASSWORD --save-host palworld

USER root
#Change values for Server Specs (1Gb = 1024Mb)
RUN ulimit -m 28672 && ulimit -v 28672 && ulimit -n 2048

RUN systemctl enable palworld.service \
    && systemctl enable palworld_update.timer \
    && touch /var/log/journal/palworld.service.log \
    && touch /var/log/journal/palworld_update.service.log
CMD ["/usr/bin/systemctl", "init"]
