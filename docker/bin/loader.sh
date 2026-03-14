#!/usr/bin/env bash
# shellcheck disable=SC1091

# Helper function to load environment variables from a specified .env file
# Usage: __load_env env_file
# Args:
#   env_file: Path to the .env file to load
# Example:
#   __load_env /path/to/.env
__load_env() {
    local env_file="${1}"

    if [ -f "${env_file}" ] && [ -r "${env_file}" ]; then
        set -a
        # shellcheck disable=SC1090
        . "${env_file}"
        set +a
        echo "(*) Loaded environment variables from '${env_file}'" >&2
    else
        echo "(!) Warning: Environment file '${env_file}' not found or not readable." >&2
    fi
}

# * Helper function to deduplicate comma-separated strings and sort results
# Behavior:
# - If arr_name is provided, sets the variable with that name to the deduplicated array
# - If arr_name is not provided, echoes the deduplicated comma-separated string
# Usage: dedupe [sort] str [arr_name]
# Args:
#   str: Comma-separated string to deduplicate
#   arr_name: (Optional) Name of the variable to set with the deduplicated array
# Example:
#   result_str=$(dedupe false "c,a,b,a,b")
#   dedupe "c,a,b,a,b" my_array
# ! Caution: Uses eval to set variable by name for bash 3 compatibility
dedupe() {
    local str arr_name sort=false
    if [ "$1" = "true" ] || [ "$1" = "false" ]; then
        sort="$1"
        shift
    fi
    str="${1}"
    arr_name="${2-}"
    local -a temp_arr
    [ -n "$str" ] || return $?
    # Parse str into an array
    IFS="," read -r -a temp_arr <<< "$str"
    # Remove duplicate entries from the array
    if [ "$sort" != "true" ]; then
        # Use `awk '!seen[$0]++'` to filter for unique entries while preserving the original order
        read -r -a temp_arr <<< "$(printf '%s\n' "${temp_arr[@]}" | awk '!seen[$0]++' | xargs echo)"
    else
        # Sort and deduplicate
        read -r -a temp_arr <<< "$(printf '%s\n' "${temp_arr[@]}" | sort -u | xargs echo)"
    fi
    if [ -n "$arr_name" ]; then
        eval "$arr_name"="($(printf '%q ' "${temp_arr[@]}"))"
    else
        # Return comma-separated string
        local IFS=","
        echo "${temp_arr[*]}"
    fi
}

# Helper function to show a wait progress bar with optional manual override
# Usage: waitprogress [waitfor] [progress_char] [background_char]
# Args:
#   waitfor: Number of seconds to wait (default: 5)
#   progress_char: Character to use for progress bar (default: '█')
#   background_char: Character to use for background bar (default: '░')
# Example:
#   waitprogress
#   waitprogress 10 '#' '-'
waitprogress() {
    local _waitfor="${1:-5}"
    local progress_char="${2:-█}"
    local background_char="${3:-░}"
    local count=0
    local progress=""
    local background=""
    local auto=true
    local i blocks percent time_remaining

    # Scale down for large wait times
    local charcap=60
    local multiplier=1
    local waitfor="$_waitfor"
    if [ "$_waitfor" -ge "$charcap" ]; then
        multiplier=$((_waitfor / charcap))
        _waitfor=$((_waitfor / multiplier))
    fi

    # Calculate characters per block
    local numchars=$((charcap / _waitfor))
    [ "$numchars" -ge 1 ] || numchars=1

    # Initial prompt message
    echo "(⏎) Press Enter to continue (proceeds automatically in ${waitfor} seconds)..." >&2
    # Build full progress bar once
    i=0
    while [ "$i" -lt "$_waitfor" ]; do
        j=0
        while [ "$j" -lt "$numchars" ]; do
            background="${background}${background_char}"
            j=$((j + 1))
        done
        i=$((i + 1))
    done

    # Initial progress display
    printf "\r  0%% \033[2m%s\033[0m" "$background" >&2
    # Calculate width of background for later use
    local bglength=${#background}
    # Calculate width needed for time_remaining display
    local time_width=${#waitfor}
    # Show progress...
    while [ "$count" -lt "$_waitfor" ]; do
        if read -r -t "$multiplier" -n 1; then
            auto=false
            break
        fi
        count=$((count + 1))
        j=0
        while [ "$j" -lt "$numchars" ]; do
            progress="${progress}${progress_char}"
            j=$((j + 1))
        done
        percent=$((count * 100 / _waitfor))
        # Calculate how many blocks to show in background
        blocks=$((count * bglength / _waitfor))
        remaining="${background:blocks}"
        time_remaining=$((waitfor - (count * multiplier)))
        # Update progress display
        printf "\r%3d%% %s\033[2m%s\033[0m %${time_width}d" "$percent" "$progress" "$remaining" "$time_remaining" >&2
    done

    # Calculate the space needed to overwrite the progress bar line
    local progress_space=$((bglength + count + time_width))
    if $auto; then
        # Additional wait to show completed progress bar
        sleep 1
        # Overwrite progress bar
        printf "\r(…) %-${progress_space}s\n" "No input detected. Proceeding automatically..." >&2
    else
        # User pressed Enter...
        # Move cursor up and overwrite progress bar
        printf "\033[A\r(…) %-${progress_space}s\n" "Manual input detected. Proceeding..." >&2
    fi
    echo >&2
}

zoneinfo() {
    echo "(+) Determining timezone..." >&2
    local default_tz="${DEFAULT_TIMEZONE:-UTC}"
    [ -n "${TIMEZONE-}" ] \
        || default_tz=$(
            set -eox pipefail
            readlink /etc/localtime 2> /dev/null | grep zoneinfo | sed 's|.*/zoneinfo/||' \
                || echo UTC
        )
    tz="${TIMEZONE:-$default_tz}"
    echo "$tz"
    echo "(∞) Timezone determined: ${tz}" >&2
    echo -e "\033[2m~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\033[0m" >&2
}

# Main function to load environment variables from a .env file
# Usage: load_env [env_dir]
# Args:
#   env_dir: Directory containing the .env file (default: script's parent directory)
# Example:
#   load_env
#   load_env /path/to/dir
load_env() {
    # Declare script path variables in local scope since this is called from other scripts
    # ---------------------------------------
    if [ -z "$0" ]; then
        echo "(!) Cannot determine script path" >&2
        exit 1
    fi

    local script_name="$0"
    local script_dir
    script_dir="$(cd "$(dirname "$script_name")" && pwd)"
    # ---------------------------------------

    local default_env_file="${script_dir}/../.env"
    local from_script="${1:-false}"

    if [ -d "${1-}" ]; then
        echo "(+) Found .env file in directory '${1}'" >&2
        env_file="${1}/.env"
    else
        echo "(+) Using default .env file path '${default_env_file}'" >&2
        if [ "$from_script" = "true" ]; then
            env_file="$default_env_file"
        fi
    fi

    __load_env "$env_file"
}

load_env "$@"
