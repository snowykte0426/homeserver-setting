#!/usr/bin/env bash
# Read Compose's raw env format as data. Never source this file or evaluate a value.
set +x
set +v
set -f
set -o pipefail
export LC_ALL=C

usage() {
    printf '%s\n' \
        'Usage: preflight.sh ENV_FILE' \
        'Validate a private UTF-8 Compose raw env file without executing or printing values.' \
        'Use KEY=raw-value; blank lines and comments are allowed. Quotes stay literal.' \
        'CRLF line endings are accepted; embedded CR, NUL and physical multiline values are not.' \
        'Use literal \n inside an unquoted GitHub RSA PEM value. PEM checks are structural only.' \
        'File permissions must exclude all group/other access (normally 0600 or 0400).' \
        'URL checks are preliminary; the application still validates keys, URLs and connections.'
}

if [[ $# == 1 && $1 == --help ]]; then
    usage
    exit 0
fi
if [[ $# != 1 ]]; then
    usage >&2
    exit 2
fi
for preflight_command in stat iconv tr wc; do
    if ! command -v "$preflight_command" >/dev/null 2>&1; then
        printf 'configuration preflight failed: required command unavailable: %s\n' "$preflight_command" >&2
        exit 1
    fi
done

preflight_path=$1
case $preflight_path in /*) ;; *) preflight_path=./$preflight_path ;; esac
if [[ ! -f $preflight_path || ! -r $preflight_path ]]; then
    printf '%s\n' 'configuration preflight failed: input must be a readable regular file' >&2
    exit 1
fi
preflight_mode=$(stat -Lc '%a' "$preflight_path" 2>/dev/null) ||
    preflight_mode=$(stat -Lf '%Lp' "$preflight_path" 2>/dev/null) || preflight_mode=
if [[ ! $preflight_mode =~ ^[0-7]{3,4}$ ]] || (( (8#$preflight_mode & 077) != 0 )); then
    printf '%s\n' 'configuration preflight failed: file must have no group/other access (use 0600 or 0400)' >&2
    exit 1
fi
if ! iconv -f UTF-8 -t UTF-8 "$preflight_path" >/dev/null 2>&1; then
    printf '%s\n' 'configuration preflight failed: valid UTF-8 input and iconv are required' >&2
    exit 1
fi
# Bash cannot preserve NUL bytes. Reject them before reading any configuration line.
if ! preflight_bytes=$(wc -c < "$preflight_path" 2>/dev/null) ||
    ! preflight_without_nul=$(tr -d '\000' < "$preflight_path" 2>/dev/null | wc -c); then
    printf '%s\n' 'configuration preflight failed: input could not be read' >&2
    exit 1
fi
if [[ $preflight_bytes != "$preflight_without_nul" ]]; then
    printf '%s\n' 'configuration preflight failed: NUL bytes are not allowed' >&2
    exit 1
fi

preflight_errors=0
preflight_keys=()
preflight_values=()
# Kotlin trim() recognizes both Unicode whitespace and space separators. In the C
# locale these UTF-8 sequences can be matched without miscounting secret byte lengths.
preflight_whitespace=$'[ \t\r\n\v\f\034-\037]|\xc2\xa0|\xe1\x9a\x80|\xe2\x80[\x80-\x8a\xa8\xa9\xaf]|\xe2\x81\x9f|\xe3\x80\x80'
preflight_trim_start="^($preflight_whitespace)"
preflight_trim_end="($preflight_whitespace)$"
report() {
    printf 'configuration preflight failed: %s\n' "$1" >&2
    preflight_errors=$((preflight_errors + 1))
}

trim_value() {
    preflight_value=$1
    while [[ $preflight_value =~ $preflight_trim_start ]]; do
        preflight_value=${preflight_value#"${BASH_REMATCH[0]}"}
    done
    while [[ $preflight_value =~ $preflight_trim_end ]]; do
        preflight_value=${preflight_value%"${BASH_REMATCH[0]}"}
    done
}

read_value() {
    local index
    preflight_value=
    for ((index = 0; index < ${#preflight_keys[@]}; index++)); do
        if [[ ${preflight_keys[index]} == "$1" ]]; then
            trim_value "${preflight_values[index]}"
            return
        fi
    done
}

preflight_line_number=0
while IFS= read -r preflight_line || [[ -n $preflight_line ]]; do
    preflight_line_number=$((preflight_line_number + 1))
    preflight_line=${preflight_line%$'\r'}
    if [[ $preflight_line == *$'\r'* ]]; then
        report "embedded CR on line $preflight_line_number"
        continue
    fi
    preflight_line=${preflight_line#"${preflight_line%%[!$' \t']*}"}
    [[ -z $preflight_line || $preflight_line == \#* ]] && continue
    preflight_key=${preflight_line%%=*}
    if [[ $preflight_line != *=* || ! $preflight_key =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        report "invalid KEY=raw-value syntax on line $preflight_line_number"
        continue
    fi
    preflight_duplicate=false
    for preflight_existing_key in "${preflight_keys[@]}"; do
        if [[ $preflight_existing_key == "$preflight_key" ]]; then
            report "duplicate key $preflight_key"
            preflight_duplicate=true
            break
        fi
    done
    if [[ $preflight_duplicate == false ]]; then
        preflight_keys[${#preflight_keys[@]}]=$preflight_key
        preflight_values[${#preflight_values[@]}]=${preflight_line#*=}
    fi
done < "$preflight_path"

for preflight_key in \
    AXIA_DATABASE_URL AXIA_DATABASE_USER AXIA_DATABASE_PASSWORD \
    AXIA_DATAGSM_CLIENT_ID AXIA_DATAGSM_THEMOMENT_CLUB_ID AXIA_DATAGSM_EVENT_SECRET \
    AXIA_GITHUB_APP_ID AXIA_GITHUB_INSTALLATION_ID AXIA_GITHUB_PRIVATE_KEY AXIA_GITHUB_WEBHOOK_SECRET \
    AXIA_ACCESS_TOKEN_SECRET AXIA_AUTH_TRANSACTION_SECRET AXIA_REFRESH_CREDENTIAL_SECRET; do
    read_value "$preflight_key"
    [[ -n $preflight_value ]] || report "missing $preflight_key"
done

positive_integer() {
    local number=$1 maximum=$2
    [[ $number =~ ^\+?[0-9]+$ ]] || return 1
    number=${number#+}
    while [[ $number == 0* ]]; do number=${number#0}; done
    [[ -n $number ]] || return 1
    [[ ${#number} -lt ${#maximum} ]] ||
        { [[ ${#number} -eq ${#maximum} ]] && [[ ! $number > $maximum ]]; }
}

for preflight_key in AXIA_DATAGSM_THEMOMENT_CLUB_ID AXIA_GITHUB_APP_ID AXIA_GITHUB_INSTALLATION_ID; do
    read_value "$preflight_key"
    if [[ -n $preflight_value ]] && ! positive_integer "$preflight_value" 9223372036854775807; then
        report "invalid positive Long $preflight_key"
    fi
done
for preflight_key in \
    AXIA_SERVER_PORT AXIA_DATABASE_POOL_SIZE AXIA_GITHUB_INCREMENTAL_SECONDS AXIA_GITHUB_FULL_SECONDS \
    AXIA_GITHUB_REDELIVERY_SECONDS AXIA_REMINDER_SECONDS AXIA_HEALTH_SECONDS; do
    read_value "$preflight_key"
    if [[ -n $preflight_value ]] && ! positive_integer "$preflight_value" 2147483647; then
        report "invalid positive Int $preflight_key"
    fi
done
for preflight_key in \
    AXIA_ACCESS_TOKEN_SECRET AXIA_AUTH_TRANSACTION_SECRET AXIA_REFRESH_CREDENTIAL_SECRET AXIA_GITHUB_WEBHOOK_SECRET; do
    read_value "$preflight_key"
    if [[ -n $preflight_value && ${#preflight_value} -lt 32 ]]; then
        report "must contain at least 32 UTF-8 bytes: $preflight_key"
    fi
done
read_value AXIA_DATAGSM_EVENT_SECRET
if [[ -n $preflight_value && ! $preflight_value =~ ^[0-9a-f]{64}$ ]]; then
    report 'invalid provider-issued lowercase hex64: AXIA_DATAGSM_EVENT_SECRET'
fi

valid_pem_shape() {
    local pem=${1//\\n/$'\n'} label body
    case $pem in
        '-----BEGIN RSA PRIVATE KEY-----'$'\n'*) label='RSA PRIVATE KEY' ;;
        '-----BEGIN PRIVATE KEY-----'$'\n'*) label='PRIVATE KEY' ;;
        *) return 1 ;;
    esac
    # A trailing escaped newline is conventional; no other material may follow the PEM.
    while [[ $pem == *$'\n' ]]; do pem=${pem%$'\n'}; done
    [[ $pem == *$'\n'"-----END $label-----" ]] || return 1
    body=${pem#*$'\n'}
    body=${body%$'\n'"-----END $label-----"}
    body=${body//$'\n'/}
    [[ $body =~ ^[A-Za-z0-9+/]+={0,2}$ ]] && (( ${#body} % 4 == 0 ))
}
read_value AXIA_GITHUB_PRIVATE_KEY
if [[ -n $preflight_value ]] && ! valid_pem_shape "$preflight_value"; then
    report 'invalid RSA PEM envelope/base64: AXIA_GITHUB_PRIVATE_KEY'
fi

# Deliberately only preliminary URL syntax checks; java.net.URI/JDBC remain authoritative.
preflight_https_pattern='^https://([A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?|\[[0-9A-Fa-f:]+\])(:[0-9]+)?([/?#][^[:space:]\\]*)?$'
for preflight_key in \
    AXIA_DATAGSM_AUTHORIZATION_BASE_URL AXIA_DATAGSM_RESOURCE_BASE_URL AXIA_DATAGSM_REDIRECT_URI AXIA_GITHUB_API_BASE_URL; do
    read_value "$preflight_key"
    if [[ -n $preflight_value && ! $preflight_value =~ $preflight_https_pattern ]]; then
        report "invalid HTTPS URL syntax: $preflight_key"
    fi
done
read_value AXIA_DATABASE_URL
if [[ -n $preflight_value && ! $preflight_value =~ ^jdbc:mysql://[^/?#[:space:]]+/[^?#[:space:]]+(\?[^#[:space:]]*)?$ ]]; then
    report 'invalid MySQL JDBC URL syntax: AXIA_DATABASE_URL'
fi

[[ $preflight_errors == 0 ]] || exit 1
printf '%s\n' 'configuration preflight passed (provider availability not verified)'
