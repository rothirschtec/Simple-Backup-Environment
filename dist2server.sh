#!/bin/bash

SERV=gmo.bdg.bak
USER=bac
PORT=907

# DIRS
cd $(dirname $0)
rdir="$PWD/"

rsync   -avP -e "ssh -p ${PORT}" \
        ${rdir} ${USER}@${SERV}:/media/4tb2/gmo-micr-srv/ \
        --exclude={"*_bak/*","*.log","mnt/*"}

rsync   -avP -e "ssh -p ${PORT}" \
        ${rdir}.ssh/ ${USER}@${SERV}:/home/SX2/bac/.ssh/ \
        --exclude={"*_bak/*","*.log","mnt/*"}
