#!/bin/bash

docker run -d --name palworld_srvcntr -p 8211:8211/udp -p 25575:25575/tcp palworld-server
