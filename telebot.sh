#!/bin/bash

if [ -z "${TELEBOT_KEY}" ]; then echo "No TELEBOT_KEY set"; exit 1 ; fi

TELEBOT_SECRETWORD="${TELEBOT_SECRETWORD:-12345}"
TELEBOT_TIMEOUT="${TELEBOT_TIMEOUT:-10}"
TELEBOT_APIURL="${TELEBOT_APIURL:-https://api.telegram.org/bot${TELEBOT_KEY}/}"
TELEBOT_CURLS="${TELEBOT_CURLS:-curl -s --max-time ${TELEBOT_TIMEOUT}}"
TELEBOT_PASSWD="${TELEBOT_PASSWD:-${TELEBOT_WDIR}.passwd}"
TELEBOT_DOIT="${TELEBOT_DOIT:-${TELEBOT_WDIR}.do_it}"
TELEBOT_OFFF="${TELEBOT_OFFF:-${TELEBOT_WDIR}.offset}"
TELEBOT_SKIP="${TELEBOT_SKIP_OFFLINE}"

trap "rm -f ${TELEBOT_DOIT}" SIGHUP SIGINT SIGTERM

# Requirements
if ! hash curl 2>/dev/null; then apt-get -qq install curl || echo "Please, do sudo apt-get install curl" && exit 1; fi
if ! hash jq 2>/dev/null; then apt-get -qq install jq || echo "Please, do sudo apt-get install jq" && exit 1; fi

TELEBOT_COMMANDS=()
TELEBOT_DEFAULT=""

if [ ! -f ${TELEBOT_PASSWD} ]; then touch ${TELEBOT_PASSWD}; fi
if [ ! -f ${TELEBOT_OFFF} ]; then echo "0" > ${TELEBOT_OFFF} ; fi
chmod 600 ${TELEBOT_PASSWD} ${TELEBOT_OFFF}

function TeleBot__isResult {
   echo $1 | jq -r '.ok' | grep -q -v "true"
}

function TeleBot_sendMessage {
    local CHATID=$1
    local MSG=$(echo "$2" | sed 's:%:%25:g; s: :%20:g; s:<:%3C:g; s:>:%3E:g; s:#:%23:g; s:{:%7B:g; s:}:%7D:g; s:|:%7C:g; s:\\:%5C:g; s:\^:%5E:g; s:~:%7E:g; s:\[:%5B:g; s:\]:%5D:g; s:`:%60:g; s:;:%3B:g; s:/:%2F:g; s:?:%3F:g; s^:^%3A^g; s:@:%40:g; s:=:%3D:g; s:&:%26:g; s:\$:%24:g; s:\!:%21:g; s:\*:%2A:g;' )
	local JSON=`${TELEBOT_CURLS} -d "chat_id=${CHATID}&text=${MSG}&disable_web_page_preview=1&parse_mode=HTML" "${TELEBOT_APIURL}sendMessage" | tr '\n' ' '`
    TeleBot__isResult "${JSON}"
    if [ $? -eq 0 ]; then
        echo "["`date`"] Failed Send message to ${CHATID}:"
        echo "${JSON}" | jq -r '.description'
    fi
}

function TeleBot_sendBroadCast {
    local EXCLUDE=$1
    local MSG=$2
    local CHATID=""
    while read LINE; do
        CHATID=`echo ${LINE} | awk -F: '{print $2}'`
        if [ ${CHATID} -ne ${EXCLUDE} ]; then
            TeleBot_sendMessage ${CHATID} "${MSG}"
        fi
    done < ${TELEBOT_PASSWD}
}

function TeleBot_ensureUser {
    local UNAME=$1
    local CHATID=$2
    local OPTIONS=$3
    local USERSTRING=`cat ${TELEBOT_PASSWD} | grep -E ^${UNAME}:`
    if [ -z "${OPTIONS}" ]; then
        OPTIONS=`echo ${USERSTRING} | awk -F: '{print $3}'`
    fi
    local NEWUSERSTRING="${UNAME}:${CHATID}:${OPTIONS}"
    if [ -z "${USERSTRING}" ]; then
        echo ${NEWUSERSTRING} >> ${TELEBOT_PASSWD}
    else
       sed -i "s/^${USERSTRING}$/${NEWUSERSTRING}/" ${TELEBOT_PASSWD}
    fi
}

function TeleBot_authorizedChat {
    local CHATID=$1
    cat ${TELEBOT_PASSWD} | grep -Eq ^[^:]+:${CHATID}:
}

function TeleBot_deleteUser {
    local UNAME=$1
    sed -i "/^${UNAME}:.*$/d" ${TELEBOT_PASSWD}
}

function TeleBot_parseCommands {
    TELEBOT_LAST_OFFSET=`cat ${TELEBOT_OFFF} || echo "${TELEBOT_LAST_OFFSET}"`
    local MSG=""; local CMD=""; local FUNC=""; local CHATID=""; local UNAME="";
    local MSGS=""; local AUTH=""; local HANDLERF=""; local UPDATEID="0";
    local JSON=`${TELEBOT_CURLS} "${TELEBOT_APIURL}getUpdates?offset=${TELEBOT_LAST_OFFSET}" | tr '\n' ' '`;
    TeleBot__isResult "${JSON}"
    if [ $? -eq 1 ]; then
        MSGS=`echo "${JSON}" | jq -r -c '.result[]'`
        printf '%s\n' "${MSGS}" | while IFS= read -r ONE; do
            if [ ! -z "${ONE}" ]; then
                HANDLERF=""
                UPDATEID=`echo ${ONE} | jq -r '.update_id'`
                # Increment update id (offset)
                if [ "${UPDATEID}" -ge "${TELEBOT_LAST_OFFSET}" ]; then
                    TELEBOT_LAST_OFFSET=${UPDATEID}
                    TELEBOT_LAST_OFFSET=$((${TELEBOT_LAST_OFFSET} + 1))
                    echo ${TELEBOT_LAST_OFFSET} > ${TELEBOT_OFFF}
                fi
                MSG=`echo ${ONE} | jq -r '.message.text'`
                CHATID=`echo ${ONE} | jq -r '.message.from.id'`
                UNAME=`echo ${ONE} | jq -r '.message.from.username'`
                if [ -z "${UNAME}" ]; then
                    UNAME="noname_${CHATID}"
                fi
                if [ -z "${TELEBOT_SKIP}" ]; then
                    for FULLCMD in "${TELEBOT_COMMANDS[@]}"; do
                        FUNC=`echo ${FULLCMD} | awk -F: '{print $1}'`
                        CMD=`echo ${FULLCMD} | awk -F: '{print $2}'`
                        AUTH=`echo ${FULLCMD} | awk -F: '{print $3}'`
                        echo ${MSG} | grep -Eqi ^\/?${CMD}
                        #Ok this handler to tall
                        if [ $? -eq 0 ]; then
                            HANDLERF="1"
                            if [ ! -z "${AUTH}" ]; then
                                TeleBot_authorizedChat ${CHATID}
                                if [ $? -eq 0 ]; then
                                    echo "["`date`"] Executed private ${FUNC} by @${UNAME}"
                                    "${FUNC}" ${UNAME} ${CHATID} "${MSG}"
                                else
                                    echo "["`date`"] Trying to execute ${FUNC} by @${UNAME}"
                                    TeleBot_sendMessage ${CHATID} "Tell me any secret..."
                                fi
                            else
                                echo "["`date`"] Executed ${FUNC} by @${UNAME}"
                                "${FUNC}" ${UNAME} ${CHATID} "${MSG}"
                            fi
                        fi
                    done
                    #No one command handlers found
                    if [ -z "${HANDLERF}" ]; then
                        if [ -z "${TELEBOT_DEFAULT}" ]; then
                            TeleBot_sendMessage ${CHATID} "Wut?"
                        else
                            "${TELEBOT_DEFAULT}" ${UNAME} ${CHATID} "${MSG}"
                        fi
                    fi
                else
                    echo "["`date`"] Skipped offline message from @${UNAME}: ${MSG}"
                fi
            fi
        done
        if [ -z "${MSGS}" ]; then
            TELEBOT_SKIP=""
        fi
    fi
}

function TeleBot_bindCommand {
    local FUNC=$1
    local CMD=$2
    local AUTH=$3
    TELEBOT_COMMANDS+=("${FUNC}:${CMD}:${AUTH}")
}

function TeleBot_bindDefault {
    TELEBOT_DEFAULT="$1"
}

function TeleBot_log {
    local UNAME=$1
    local CHATID=$2
    local MSG=$3
    echo "["`date`"] ${UNAME}:${CHATID} says: ${MSG}"
}

function TeleBot_secret {
    local UNAME=$1
    local CHATID=$2
    local MSG=$3
    echo ${MSG} | grep -q "secret ${TELEBOT_SECRETWORD}"
    if [ $? -eq 0 ]; then
        TeleBot_ensureUser ${UNAME} ${CHATID}
        TeleBot_sendMessage ${CHATID} "OK, Accepted. If you want to disconnect from me try /stop."
        TeleBot_sendBroadCast ${CHATID} "User joined and authorized: @${UNAME}"
    else
        TeleBot_sendMessage ${CHATID} "Not read LOL -_-"
    fi
}

function TeleBot_stop {
    local UNAME=$1
    local CHATID=$2
    TeleBot_deleteUser ${UNAME}
    TeleBot_sendBroadCast ${CHATID} "User leaved: @${UNAME}"
}

function TeleBot_start {
    local UNAME=$1
    local CHATID=$2
    TeleBot_sendMessage ${CHATID} "Hi! I am unremarkable boat. You're need to know a secret!"
}

function TeleBot_goLoop {
    if [ ! -z ${TELEBOT_TELL_ALIVE} ]; then
        TeleBot_sendBroadCast 0 "I'm alive, again!"
    fi
    while [ -f "${TELEBOT_DOIT}" ]; do
        TeleBot_parseCommands
        sleep 1
    done
    if [ ! -z ${TELEBOT_TELL_ALIVE} ]; then
        TeleBot_sendBroadCast 0 "Someone stopped me! Goodbye!"
    fi
}

function TeleBot_enable {
    echo "1" >> ${TELEBOT_DOIT}
}

function TeleBot_disable {
    rf -f ${TELEBOT_DOIT}
}


# Bind some utils
TeleBot_bindCommand TeleBot_stop "stop"
TeleBot_bindCommand TeleBot_start "start"
TeleBot_bindCommand TeleBot_log "log"
TeleBot_bindCommand TeleBot_secret "secret"

