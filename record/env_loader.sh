#!/usr/bin/env bash

trim_env_value() {
    local value="$1"
    value="${value#${value%%[![:space:]]*}}"
    value="${value%${value##*[![:space:]]}}"
    printf '%s' "$value"
}

load_env_file() {
    local env_file="$1"
    local line key value first_char last_char

    [[ -f "$env_file" ]] || return 0

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ -n "${line//[[:space:]]/}" ]] || continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        line="$(trim_env_value "$line")"
        if [[ "$line" =~ ^export[[:space:]]+ ]]; then
            line="${line#export}"
            line="$(trim_env_value "$line")"
        fi

        [[ "$line" == *=* ]] || continue
        key="$(trim_env_value "${line%%=*}")"
        value="$(trim_env_value "${line#*=}")"

        [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue

        if [[ ${#value} -ge 2 ]]; then
            first_char="${value:0:1}"
            last_char="${value: -1}"
            if [[ "$first_char" == "$last_char" && ( "$first_char" == '"' || "$first_char" == "'" ) ]]; then
                value="${value:1:${#value}-2}"
            fi
        fi

        printf -v "$key" '%s' "$value"
        export "$key"
    done < "$env_file"
}
