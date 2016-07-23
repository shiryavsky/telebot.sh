#!/bin/bash

function TeleBot_util_df {
    local UNAME=$1
    local CHATID=$2
    local RES=`df -h`
    TeleBot_sendMessage ${CHATID} "<code>${RES}</code>"
}

function TeleBot_util_free {
    local UNAME=$1
    local CHATID=$2
    local RES=`free -h`
    TeleBot_sendMessage ${CHATID} "<code>${RES}</code>"
}

function TeleBot_util_uname {
    local UNAME=$1
    local CHATID=$2
    local RES=`uname -a`
    TeleBot_sendMessage ${CHATID} "<code>${RES}</code>"
}

function TeleBot_util_release {
    local UNAME=$1
    local CHATID=$2
    local RES=`lsb_release -a`
    TeleBot_sendMessage ${CHATID} "<code>${RES}</code>"
}

function TeleBot_util_top {
    local UNAME=$1
    local CHATID=$2
    local NUM=`echo "$3" | awk '{print $2}'`
    if [ -z ${NUM} ]; then
        NUM=10
    fi
    local RES=`ps aux | sort -nrk 3,3 | grep -v " %CPU " | head -n ${NUM} | awk '{print $1"\t"$2"\t"$3" "$4" "$11}'`
    local MSG=`echo -e "USER PID %CPU %MEM COMMAND\n${RES}"`
    TeleBot_sendMessage ${CHATID} "<code>${MSG}</code>"
}


TeleBot_bindCommand TeleBot_util_df "df" 1
TeleBot_bindCommand TeleBot_util_top "top" 1
TeleBot_bindCommand TeleBot_util_free "free" 1
TeleBot_bindCommand TeleBot_util_uname "uname" 1
TeleBot_bindCommand TeleBot_util_release "release" 1
TeleBot_bindCommand TeleBot_util_release "lsb_release" 1
