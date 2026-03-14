#!/usr/bin/env bash

com=("$@")

if [ "${#com[@]}" -eq 0 ]; then
    echo "(!) No command to execute." >&2
    exit 1
fi

printf "\033[95;1m§ %s\033[0m\n" "${com[*]}" >&2

DEFAULT_TIME_MSG_LABEL="${DEFAULT_TIME_MSG_LABEL-}"
DEFAULT_TIME_MSG_PREFIX="${DEFAULT_TIME_MSG_PREFIX:-Elapsed time}"
TIME_MSG_LABEL="${TIME_MSG_LABEL:-$DEFAULT_TIME_MSG_LABEL}"
TIME_MSG_PREFIX="${TIME_MSG_PREFIX:-$DEFAULT_TIME_MSG_PREFIX}"
if command -v time > /dev/null 2>&1; then
    # TIMEFORMAT="Elapsed time: %lR seconds"
    TIMEFORMAT=$'\n'"${TIME_MSG_LABEL}"$'\033[7m ⏱ '"${TIME_MSG_PREFIX% }"$': %lR seconds \033[0m'
    time (
        set -x
        "${com[@]}"
    )
else
    SECONDS=0
    (
        set -x
        "${com[@]}"
    )
    # Calculate the duration
    duration=$SECONDS
    # Format the duration into hours, minutes, and seconds
    # Hours: (duration / 3600)
    # Minutes: ((duration % 3600) / 60)
    # Seconds: (duration % 60)
    printf "\n%s\033[7m ⏱ %s: %02d hours, %02d minutes, %02d seconds \033[0m\n" "${TIME_MSG_LABEL}" "${TIME_MSG_PREFIX% }" $((duration / 3600)) $((duration % 3600 / 60)) $((duration % 60)) >&2
fi

echo -e "\033[2m~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\033[0m" >&2
