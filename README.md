# palworld-linux-steamcmd-docker
Simple Dockerfile that installs steamcmd and a palworld server with option of saves

**Installation**
1. download this repo to any directory.
2. Make sure you have docker installed.
3. Enable Ports **8211** and **25575** in your firewall.
   (Docker will change your IP tables, and it may go around your firewall (**ufw**). Do some research if changes need to be made.)
4. Within repo directory, there is a folder **/files/Config/** to place your PalWorldSettings.ini from a previous server.
   There is also a folder **/files/World/0/RecentSave/** which you can optionally place a backup save (server save), ie. "Level.sav LevelMeta.sav Players/*".
   (The RecentSave folder will be copied into the container, but since the hash folder is randomly generated you'll need to manually move the files over).
5. Inside repo dir, run ``Docker build -t palworld_server .`` and wait for completion.
6. Next run, ``./docker-run.sh`` to build the container.
7. Setup your Router to port-forward to your host PC's IP address ``192.168.1.***"`` ports: ``25575:25575 8211:8211``
   To Connect from **WITHIN YOUR LAN**: the IP is your host PC's IP Address.
   To Connect from **OUTSIDE YOUR LAN, AKA WAN**: the IP is your router's IP.
   (If you want to make these the same IP, that's messing with NAT Hair-pinning within your Router settings..if it has it. Mine doesn't.)
8. LOGIN! Make a character and play.
**Modifying the Server**
To access the server within the container, run ``docker exec -it palworld_srvcntr /bin/bash``
If you intend on making modifications to an existing docker server, the services running within will keep the Server up if it crashes or is killed.
To disable this, run ``systemctl stop palworld.service`` . THEN modify your saves or settings:
To enable againg run ``systemctl start palworld.service`` and the server should boot up in a few moments.
 9. To modify your server settings: \
       ``nano /home/steam/serverdata/palworld/Pal/Saved/Config/LinuxServer/PalWorldSetting.ini``
10. To copy savegame files to server save. **MAKE SURE A CHARACTER HAS BEEN CREATED ON THE SERVER FIRST** or the folder won't exist.
       ``cp -rf ~/Saved_Game/World/SaveGames/0/RecentSave/* ~/serverdata/palworld/Pal/Saved/SaveGames/0/*insert known hash*/*``

**Happy Pal--Pallying---Hunting!**
