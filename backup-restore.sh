#!/bin/bash

set -e

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin:$PATH"
export REQUESTS_CA_BUNDLE="/etc/ssl/certs/ca-certificates.crt"

VERSION="4.2.11"
DONATE_URL="https://t.me/tribute/app?startapp=dRNM"
INSTALL_DIR="/opt/rw-backup-restore"
BACKUP_DIR="$INSTALL_DIR/backup"
LOG_DIR="$INSTALL_DIR/logs"
LOG_CATEGORY="system"
LOG_MAX_BYTES=5242880
CONFIG_FILE="$INSTALL_DIR/config.env"
SCRIPT_NAME="backup-restore.sh"
SCRIPT_PATH="$INSTALL_DIR/$SCRIPT_NAME"
RETAIN_BACKUPS_DAYS=7
RETAIN_BACKUPS_VALUE=7
RETAIN_BACKUPS_UNIT="days"
S3_RETAIN_DAYS=30
S3_COUNT=1
SYMLINK_PATH="/usr/local/bin/rw-backup"
REMNALABS_ROOT_DIR=""
SCRIPT_REPO_URL="https://raw.githubusercontent.com/distillium/remnawave-backup-restore/dev/backup-restore.sh"
SCRIPT_RUN_PATH="$(realpath "$0")"

S3_ENDPOINT=""
S3_ACCESS_KEY=""
S3_SECRET_KEY=""
S3_BUCKET=""
S3_REGION=""
S3_PREFIX=""
UPLOAD_METHOD="telegram"
DB_CONNECTION_TYPE="docker"
DB_HOST=""
DB_PORT="5432"
DB_NAME="postgres"
DB_PASSWORD=""
DB_SSL_MODE="prefer"
DB_POSTGRES_VERSION="17"
CRON_TIMES=""
TG_MESSAGE_THREAD_ID=""
TG_PROXY=""
UPDATE_AVAILABLE=false
AUTO_UPDATE="false"
ENCRYPT_ENABLED="false"
ENCRYPT_PUBLIC_KEY=""
BACKUP_EXCLUDE_PATTERNS="*.log *.tmp .git"
LANG_CODE=""
TRANSLATIONS_DIR="$INSTALL_DIR/translations"

BOT_BACKUP_ENABLED="false"
BOT_BACKUP_PATH=""
BOT_BACKUP_SELECTED=""
BOT_BACKUP_DB_USER="postgres"

if [[ -t 0 ]]; then
    RED=$'\e[31m'
    GREEN=$'\e[32m'
    YELLOW=$'\e[33m'
    GRAY=$'\e[37m'
    LIGHT_GRAY=$'\e[90m'
    CYAN=$'\e[36m'
    RESET=$'\e[0m'
    BOLD=$'\e[1m'
    MUTED_GREEN=$'\e[38;5;71m'
    UI_SEL_BG=$'\e[48;5;22m\e[97m'
else
    RED=""
    GREEN=""
    YELLOW=""
    GRAY=""
    LIGHT_GRAY=""
    CYAN=""
    RESET=""
    BOLD=""
    MUTED_GREEN=""
    UI_SEL_BG=""
fi

declare -A L

t() {
    local key="$1"
    if [[ -n "${L[$key]+x}" ]]; then
        echo "${L[$key]}"
    else
        echo "$key"
    fi
}

download_translations() {
    local base_url="${SCRIPT_REPO_URL%/*}"
    mkdir -p "$TRANSLATIONS_DIR"
    for lang_file in ru.sh en.sh; do
        if ! curl -fsSL "$base_url/translations/$lang_file" -o "$TRANSLATIONS_DIR/$lang_file" 2>/dev/null; then
            echo -e "${RED}[ERROR]${RESET} Failed to download $lang_file"
        fi
    done
}

load_language() {
    local lang="${1:-ru}"
    local lang_file="$TRANSLATIONS_DIR/${lang}.sh"
    if [[ -f "$lang_file" ]]; then
        source "$lang_file"
    elif [[ -f "$TRANSLATIONS_DIR/ru.sh" ]]; then
        source "$TRANSLATIONS_DIR/ru.sh"
    fi
}

select_language_interactive() {
    echo ""
    echo "Select language / Выберите язык:"
    echo ""
    ui_menu_reset
    ui_menu_add 1 "Русский"
    ui_menu_add 2 "English"
    local lang_choice
    ui_menu_choose lang_choice
    case "$lang_choice" in
        2) LANG_CODE="en" ;;
        *) LANG_CODE="ru" ;;
    esac
    load_language "$LANG_CODE"
}

print_message() {
    local type="$1"
    local message="$2"
    local color_code="$RESET"

    case "$type" in
        "INFO") color_code="$GRAY" ;;
        "SUCCESS") color_code="$GREEN" ;;
        "WARN") color_code="$YELLOW" ;;
        "ERROR") color_code="$RED" ;;
        "ACTION") color_code="$CYAN" ;;
        "LINK") color_code="$CYAN" ;;
        *) type="INFO" ;;
    esac

    [[ "$_UI_SPIN_ON" == "1" ]] && ui_spin_stop
    if [[ -n "$UI_LAST_ELAPSED" ]]; then
        if [[ "$type" == "SUCCESS" && "$UI_LAST_ELAPSED" -ge 2 ]]; then
            message="${message} ${LIGHT_GRAY}· $(printf "$(t ui_elapsed)" "$UI_LAST_ELAPSED")${RESET}"
        fi
        UI_LAST_ELAPSED=""
    fi
    echo -e "${color_code}[$type]${RESET} $message"
    log_write "$type" "$message"
}

_ui_interactive() {
    [[ -t 0 && -t 1 && "${TERM:-dumb}" != "dumb" && "${RW_PLAIN_UI:-0}" != "1" ]]
}

_UI_MENU_KEYS=()
_UI_MENU_LABELS=()
_UI_MENU_STYLES=()
_UI_MENU_WINDOWED=0
_UI_MENU_FOOTER=()
_UI_MENU_TYPED=""
_UI_MENU_WARN=""
_UI_MENU_KW=1

ui_menu_reset() {
    _UI_MENU_KEYS=()
    _UI_MENU_LABELS=()
    _UI_MENU_STYLES=()
    _UI_MENU_FOOTER=()
}

ui_menu_footer() {
    _UI_MENU_FOOTER+=("$1")
}

ui_menu_add() {
    _UI_MENU_KEYS+=("$1")
    _UI_MENU_LABELS+=("$2")
    _UI_MENU_STYLES+=("${3:-}")
}

ui_menu_gap() {
    _UI_MENU_KEYS+=("")
    _UI_MENU_LABELS+=("")
    _UI_MENU_STYLES+=("gap")
}

_ui_menu_style() {
    case "$1" in
        primary) printf '%s' "${GREEN}${BOLD}" ;;
        warn)    printf '%s' "$YELLOW" ;;
        danger)  printf '%s' "$RED" ;;
        *)       printf '' ;;
    esac
}

_ui_menu_draw() {
    local sel="$1" first="$2" last="$3" final="${4:-0}" total="${#_UI_MENU_KEYS[@]}" i st lines=0 f
    if (( first > 0 )); then
        printf '\r\e[2K   %s↑ %s%s\n' "$LIGHT_GRAY" "$(t ui_more_above)" "$RESET"; lines=$((lines + 1))
    elif (( last < total - 1 || _UI_MENU_WINDOWED )); then
        printf '\r\e[2K\n'; lines=$((lines + 1))
    fi
    for ((i = first; i <= last; i++)); do
        if [[ "${_UI_MENU_STYLES[$i]}" == "gap" ]]; then
            printf '\r\e[2K\n'; lines=$((lines + 1)); continue
        fi
        st=$(_ui_menu_style "${_UI_MENU_STYLES[$i]}")
        local num
        num=$(printf '%*s' "$_UI_MENU_KW" "${_UI_MENU_KEYS[$i]}")
        if (( i == sel )); then
            printf '\r\e[2K %s▸%s %s%s %s. %s %s\n' "${GREEN}${BOLD}" "$RESET" "$UI_SEL_BG" "$BOLD" "$num" "${_UI_MENU_LABELS[$i]}" "$RESET"
        else
            printf '\r\e[2K   %s %s. %s %s\n' "$st" "$num" "${_UI_MENU_LABELS[$i]}" "$RESET"
        fi
        lines=$((lines + 1))
    done
    if (( last < total - 1 )); then
        printf '\r\e[2K   %s↓ %s%s\n' "$LIGHT_GRAY" "$(t ui_more_below)" "$RESET"; lines=$((lines + 1))
    elif (( _UI_MENU_WINDOWED )); then
        printf '\r\e[2K\n'; lines=$((lines + 1))
    fi
    if (( ! final )); then
        local hint hint_color="$LIGHT_GRAY"
        if [[ -n "${_UI_MENU_WARN:-}" ]]; then
            hint=$(printf "$(t ui_invalid_num)" "$_UI_MENU_WARN")
            hint_color="$YELLOW"
        elif [[ -n "${_UI_MENU_TYPED:-}" ]]; then
            hint=$(printf "$(t ui_typed_num)" "$_UI_MENU_TYPED")
            hint_color="$GREEN"
        else
            hint=$(t ui_menu_hint)
        fi
        [[ -z "$hint" || "$hint" == ui_* ]] && hint="↑/↓ · Enter"
        printf '\r\e[2K\n\r\e[2K   %s%s%s\n' "$hint_color" "$hint" "$RESET"
        lines=$((lines + 2))
        for f in "${_UI_MENU_FOOTER[@]}"; do
            printf '\r\e[2K   %s%s%s\n' "$LIGHT_GRAY" "$f" "$RESET"
            lines=$((lines + 1))
        done
    fi
    _UI_MENU_DRAWN=$lines
}

_ui_menu_next() { # index direction -> next selectable index
    local i="$1" dir="$2" n="${#_UI_MENU_KEYS[@]}" step
    for ((step = 0; step < n; step++)); do
        i=$(( (i + dir + n) % n ))
        [[ "${_UI_MENU_STYLES[$i]}" != "gap" ]] && { echo "$i"; return; }
    done
    echo "$1"
}

_ui_menu_index_of() {
    local i
    for ((i = 0; i < ${#_UI_MENU_KEYS[@]}; i++)); do
        [[ "${_UI_MENU_STYLES[$i]}" != "gap" && "${_UI_MENU_KEYS[$i],,}" == "${1,,}" ]] && { echo "$i"; return 0; }
    done
    return 1
}

_ui_menu_has_prefix() { # is there a longer key starting with $1?
    local k
    for k in "${_UI_MENU_KEYS[@]}"; do
        [[ -n "$k" && "${k,,}" != "${1,,}" && "${k,,}" == "${1,,}"* ]] && return 0
    done
    return 1
}

ui_menu_choose() {
    local __var="$1" init="${2:-}" n="${#_UI_MENU_KEYS[@]}" sel=0 i key rest
    _UI_MENU_TYPED=""
    _UI_MENU_WARN=""
    ui_spin_stop
    _UI_MENU_KW=1
    for i in "${_UI_MENU_KEYS[@]}"; do
        (( ${#i} > _UI_MENU_KW )) && _UI_MENU_KW=${#i}
    done

    if ! _ui_interactive; then
        for ((i = 0; i < n; i++)); do
            if [[ "${_UI_MENU_STYLES[$i]}" == "gap" ]]; then echo ""; continue; fi
            echo -e " $(_ui_menu_style "${_UI_MENU_STYLES[$i]}")$(printf '%*s' "$_UI_MENU_KW" "${_UI_MENU_KEYS[$i]}"). ${_UI_MENU_LABELS[$i]}${RESET}"
        done
        for i in "${_UI_MENU_FOOTER[@]}"; do echo -e "   ${LIGHT_GRAY}${i}${RESET}"; done
        echo ""
        local prompt
        prompt=$(t select_option)
        [[ -z "$prompt" || "$prompt" == "select_option" ]] && prompt="> "
        read -rp "${GREEN}[?]${RESET} ${prompt}" key || key=""
        printf -v "$__var" '%s' "$key"
        return 0
    fi

    if [[ -n "$init" ]] && i=$(_ui_menu_index_of "$init"); then
        sel=$i
    elif [[ "${_UI_MENU_STYLES[0]:-}" == "gap" ]]; then
        sel=$(_ui_menu_next 0 1)
    fi

    local rows max first last
    rows=$(tput lines 2>/dev/null || echo 24)
    max=$(( rows - 10 ))
    (( max < 5 )) && max=5
    first=0; last=$(( n - 1 ))
    _UI_MENU_WINDOWED=0
    (( n > max )) && _UI_MENU_WINDOWED=1

    printf '\e[?25l'
    stty -echo 2>/dev/null || true
    local drawn=0
    while true; do
        if (( n > max && sel >= 0 )); then
            (( sel < first )) && first=$sel
            (( sel > first + max - 1 )) && first=$(( sel - max + 1 ))
            last=$(( first + max - 1 ))
            (( last > n - 1 )) && last=$(( n - 1 ))
        fi
        (( drawn > 0 )) && printf '\e[%dA' "$drawn"
        _ui_menu_draw "$sel" "$first" "$last"
        drawn=$_UI_MENU_DRAWN

        IFS= read -rsn1 key || key=""
        case "$key" in
            $'\e')
                rest=""
                IFS= read -rsn2 -t 0.05 rest || true
                case "$rest" in
                    '[A'|'OA') if (( sel < 0 )); then sel=$(_ui_menu_next "$n" -1); else sel=$(_ui_menu_next "$sel" -1); fi ;;
                    '[B'|'OB') if (( sel < 0 )); then sel=$(_ui_menu_next -1 1); else sel=$(_ui_menu_next "$sel" 1); fi ;;
                    '[H'|'OH') sel=$(_ui_menu_next -1 1) ;;
                    '[F'|'OF') sel=$(_ui_menu_next "$n" -1) ;;
                    '')
                        if i=$(_ui_menu_index_of "0"); then sel=$i; break; fi ;;
                    *) IFS= read -rsn5 -t 0.02 rest || true ;;
                esac
                _UI_MENU_TYPED=""; _UI_MENU_WARN="" ;;
            k) if (( sel < 0 )); then sel=$(_ui_menu_next "$n" -1); else sel=$(_ui_menu_next "$sel" -1); fi; _UI_MENU_TYPED=""; _UI_MENU_WARN="" ;;
            j) if (( sel < 0 )); then sel=$(_ui_menu_next -1 1); else sel=$(_ui_menu_next "$sel" 1); fi; _UI_MENU_TYPED=""; _UI_MENU_WARN="" ;;
            '') (( sel >= 0 )) && break ;;
            $'\x7f'|$'\b')
                _UI_MENU_TYPED="${_UI_MENU_TYPED%?}"
                _UI_MENU_WARN=""
                if [[ -n "$_UI_MENU_TYPED" ]] && i=$(_ui_menu_index_of "$_UI_MENU_TYPED"); then
                    sel=$i
                fi ;;
            *)
                _UI_MENU_WARN=""
                local cand="${_UI_MENU_TYPED}${key}"
                if i=$(_ui_menu_index_of "$cand"); then
                    _UI_MENU_TYPED="$cand"
                    sel=$i
                elif _ui_menu_has_prefix "$cand"; then
                    _UI_MENU_TYPED="$cand"
                else
                    _UI_MENU_WARN="$cand"
                    _UI_MENU_TYPED=""
                    sel=-1
                fi ;;
        esac
    done
    printf '\e[%dA' "$drawn"
    _ui_menu_draw "$sel" "$first" "$last" 1
    printf '\e[J'
    stty echo 2>/dev/null || true
    printf '\e[?25h'
    printf -v "$__var" '%s' "${_UI_MENU_KEYS[$sel]}"
    return 0
}

ui_input() {
    local __var="$1" label="$2" hint="${3:-}" note="${4:-}" first="" value=""
    ui_spin_stop
    label="${label%: }"; label="${label%:}"
    if ! _ui_interactive; then
        read -rp "${label}: " value || value=""
        printf -v "$__var" '%s' "$value"
        return 0
    fi
    echo -e "   ${BOLD}${label}${RESET}"
    [[ -n "$note" ]] && echo -e "   ${LIGHT_GRAY}${note}${RESET}"
    local p=$'\001'"${GREEN}"$'\002''›'$'\001'"${RESET}"$'\002'' '
    printf '   %s›%s %s%s%s\r' "$GREEN" "$RESET" "$LIGHT_GRAY" "$hint" "$RESET"
    printf '   %s›%s ' "$GREEN" "$RESET"
    stty -echo 2>/dev/null || true
    while true; do
        IFS= read -rsn1 first || first=""
        if [[ "$first" == $'\e' ]]; then          # ignore arrows etc. on an empty field
            IFS= read -rsn5 -t 0.02 first || true
            continue
        fi
        break
    done
    if [[ -z "$first" ]]; then
        stty echo 2>/dev/null || true
        printf '\e[K\n'
        printf -v "$__var" '%s' ""
        return 0
    fi
    printf '\r\e[K'
    stty echo 2>/dev/null || true
    IFS= read -re -i "$first" -p "   $p" value || value=""
    printf -v "$__var" '%s' "$value"
    return 0
}

ui_secret() {
    local __var="$1" label="$2" note="${3:-}" value=""
    ui_spin_stop
    label="${label%: }"; label="${label%:}"
    if ! _ui_interactive; then
        read -rsp "${label}: " value || value=""
        echo ""
        printf -v "$__var" '%s' "$value"
        return 0
    fi
    echo -e "   ${BOLD}${label}${RESET}"
    [[ -n "$note" ]] && echo -e "   ${LIGHT_GRAY}${note}${RESET}"
    printf '   %s›%s ' "$GREEN" "$RESET"
    IFS= read -rs value || value=""
    if [[ -n "$value" ]]; then
        printf '%s••••••••%s\n' "$LIGHT_GRAY" "$RESET"
    else
        printf '\n'
    fi
    printf -v "$__var" '%s' "$value"
    return 0
}

ui_confirm() {
    local __var="$1" q="${2:-}" ans
    ui_spin_stop
    while true; do
        if ! read -rp "$(echo -e "${GREEN}[?]${RESET} ${q:+$q }(${GREEN}${BOLD}Y${RESET}/${RED}${BOLD}N${RESET}): ")" ans; then
            echo ""
            printf -v "$__var" '%s' "n"
            return 0
        fi
        case "${ans,,}" in
            y) printf -v "$__var" '%s' "y"; return 0 ;;
            n) printf -v "$__var" '%s' "n"; return 0 ;;
        esac
        if [[ -n "$(LC_ALL=C tr -d '\000-\177' <<< "$ans")" ]]; then
            echo -e "    ${YELLOW}$(t ui_yn_layout)${RESET}"
        else
            echo -e "    ${YELLOW}$(t ui_yn_invalid)${RESET}"
        fi
    done
}

_UI_SPIN_PID=""
_UI_SPIN_T0=0
_UI_SPIN_ON=0
UI_LAST_ELAPSED=""

ui_spin_start() {
    local msg="$1"
    ui_spin_stop
    _UI_SPIN_T0=$SECONDS
    _UI_SPIN_ON=1
    log_write "INFO" "$msg"
    if ! _ui_interactive; then
        echo -e "${GRAY}[INFO]${RESET} $msg"
        return 0
    fi
    (
        local frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏) i=0 t0=$SECONDS fmt
        fmt=$(t ui_elapsed)
        while true; do
            printf "\r\e[2K%s%s%s %s %s${fmt}%s" "$CYAN" "${frames[i]}" "$RESET" "$msg" "$LIGHT_GRAY" $((SECONDS - t0)) "$RESET"
            i=$(( (i + 1) % 10 ))
            sleep 0.1
        done
    ) &
    _UI_SPIN_PID=$!
    printf '\e[?25l'
}

ui_spin_stop() {
    if [[ -n "$_UI_SPIN_PID" ]]; then
        kill "$_UI_SPIN_PID" 2>/dev/null || true
        wait "$_UI_SPIN_PID" 2>/dev/null || true
        _UI_SPIN_PID=""
        printf '\r\e[2K\e[?25h'
    fi
    if [[ "$_UI_SPIN_ON" == "1" ]]; then
        UI_LAST_ELAPSED=$(( SECONDS - _UI_SPIN_T0 ))
        _UI_SPIN_ON=0
    fi
}
trap 'ui_spin_stop; if [[ -t 0 ]]; then stty echo 2>/dev/null; printf "\e[?25h"; fi' EXIT

_LOG_ROTATED=false
_log_rotate() {
    local f
    for f in backup restore system error cron; do
        if [[ -f "$LOG_DIR/$f.log" && $(stat -c %s "$LOG_DIR/$f.log" 2>/dev/null || echo 0) -gt $LOG_MAX_BYTES ]]; then
            mv -f "$LOG_DIR/$f.log" "$LOG_DIR/$f.log.1" 2>/dev/null || true
        fi
    done
}

log_write() {
    local level="$1"
    local message="$2"
    (
        umask 077
        [[ -d "$INSTALL_DIR" ]] || exit 0
        mkdir -p "$LOG_DIR" 2>/dev/null || exit 0
        chmod 700 "$LOG_DIR" 2>/dev/null
        if [[ "$_LOG_ROTATED" != "true" ]]; then _log_rotate; fi
        local clean
        clean=$(printf '%s' "$message" | sed -e $'s/\x1b\\[[0-9;]*m//g' -e 's/bot[0-9]\{6,\}:[A-Za-z0-9_-]\{20,\}/bot***/g' | tr '\n' ' ')
        local line
        line="$(date '+%Y-%m-%d %H:%M:%S') [${level}] ${clean}"
        echo "$line" >> "$LOG_DIR/${LOG_CATEGORY}.log"
        if [[ "$level" == "ERROR" || "$level" == "WARN" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') [${level}] [${LOG_CATEGORY}] ${clean}" >> "$LOG_DIR/error.log"
        fi
    ) 2>/dev/null || true
    _LOG_ROTATED=true
}

setup_symlink() {
    echo ""
    if [[ "$EUID" -ne 0 ]]; then
        print_message "WARN" "$(t symlink_root) ${BOLD}${SYMLINK_PATH}${RESET}. $(t symlink_skip)"
        return 1
    fi

    if [[ -L "$SYMLINK_PATH" && "$(readlink -f "$SYMLINK_PATH")" == "$SCRIPT_PATH" ]]; then
        print_message "SUCCESS" "$(t symlink_ok) ${BOLD}${SCRIPT_PATH}${RESET}."
        return 0
    fi

    print_message "INFO" "$(t symlink_creating) ${BOLD}${SYMLINK_PATH}${RESET}..."
    rm -f "$SYMLINK_PATH"
    if [[ -d "$(dirname "$SYMLINK_PATH")" ]]; then
        if ln -s "$SCRIPT_PATH" "$SYMLINK_PATH"; then
            print_message "SUCCESS" "$(t symlink_created)"
        else
            print_message "ERROR" "$(t symlink_fail) ${BOLD}${SYMLINK_PATH}${RESET}. $(t check_permissions)"
            return 1
        fi
    else
        print_message "ERROR" "$(t symlink_dir_missing)"
        return 1
    fi
    echo ""
    return 0
}

configure_bot_backup() {
    while true; do
        clear
        echo -e "${GREEN}${BOLD}$(t bot_cfg_title)${RESET}"
        echo ""
        
        if [[ "$BOT_BACKUP_ENABLED" == "true" ]]; then
            local bot_mode_disp
            if [[ "$SKIP_PANEL_BACKUP" == "true" ]]; then
                bot_mode_disp="${RED}$(t bot_mode_only)"
            else
                bot_mode_disp="${GREEN}$(t bot_mode_panel_bot)"
            fi
            print_aligned_rows \
                "$(t bot_label)" "${GREEN}${BOT_BACKUP_SELECTED}" \
                "$(t bot_path_label)" "$BOT_BACKUP_PATH" \
                "$(t bot_mode_label)" "$bot_mode_disp"
        else
            print_message "INFO" "$(t bot_backup_status) ${RED}${BOLD}$(t bot_disabled)${RESET}"
            if [[ "$SKIP_PANEL_BACKUP" == "true" ]]; then
                print_message "WARN" "$(t bot_warn_nothing)"
            else
                print_message "INFO" "$(t bot_panel_only_mode)"
            fi
        fi
        echo ""
        
        ui_menu_reset
        ui_menu_add 1 "$(t bot_menu_configure)"
        
        if [[ "$BOT_BACKUP_ENABLED" == "true" ]]; then
            ui_menu_add 2 "$(t bot_menu_disable)"
            
            if [[ "$SKIP_PANEL_BACKUP" == "true" ]]; then
                if [[ "$REMNALABS_ROOT_DIR" != "none" && -n "$REMNALABS_ROOT_DIR" ]]; then
                    ui_menu_add 3 "$(t bot_menu_enable_panel)"
                fi
            else
                ui_menu_add 3 "$(t bot_menu_exclude_panel)"
            fi
        fi

        ui_menu_gap
        ui_menu_add 0 "$(t back_to_menu)"
        
        ui_menu_choose choice
        
        case $choice in
            1)
                clear
                echo -e "${GREEN}${BOLD}$(t bot_select_title)${RESET}"
                echo ""
                ui_menu_reset
                ui_menu_add 1 "$(t bot_jesus)"
                ui_menu_add 2 "$(t bot_jesus_priv)"
                ui_menu_add 3 "$(t bot_machka)"
                ui_menu_add 4 "$(t bot_snoups)"
                ui_menu_add 5 "$(t bot_minishop)"
                ui_menu_add 0 "$(t back)"
                
                local bot_choice
                ui_menu_choose bot_choice
                case "$bot_choice" in
                    1) BOT_BACKUP_SELECTED="Бот от Иисуса"; bot_folder="remnawave-telegram-shop" ;;
                    2) BOT_BACKUP_SELECTED="Приватный бот от Иисуса"; bot_folder="rwp-shop" ;;
                    3) BOT_BACKUP_SELECTED="Бот от Мачки"; bot_folder="remnawave-tg-shop" ;;
                    4) BOT_BACKUP_SELECTED="Бот от Snoups"; bot_folder="remnashop" ;;
                    5) BOT_BACKUP_SELECTED="Бот Minishop"; bot_folder="remnawave-minishop" ;;
                    0) continue ;;
                    *) print_message "ERROR" "$(t invalid_input)"; sleep 1; continue ;;
                esac
                
                echo ""
                print_message "ACTION" "$(t bot_select_path)"
                ui_menu_reset
                ui_menu_add 1 "/opt/$bot_folder"
                ui_menu_add 2 "/root/$bot_folder"
                ui_menu_add 3 "/opt/stacks/$bot_folder"
                ui_menu_add 4 "$(t custom_path)"
                ui_menu_gap
                ui_menu_add 0 "$(t back)"

                local path_choice
                ui_menu_choose path_choice
                case "$path_choice" in
                    0) continue ;;
                    1) BOT_BACKUP_PATH="/opt/$bot_folder" ;;
                    2) BOT_BACKUP_PATH="/root/$bot_folder" ;;
                    3) BOT_BACKUP_PATH="/opt/stacks/$bot_folder" ;;
                    4) 
                        echo ""
                        ui_input custom_bot_path "$(t bot_enter_path)" "/opt/my-bot"
                        if [[ -z "$custom_bot_path" || ! "$custom_bot_path" = /* ]]; then
                            print_message "ERROR" "$(t bot_path_absolute)"
                            sleep 2; continue
                        fi
                        BOT_BACKUP_PATH="${custom_bot_path%/}" 
                        ;;
                    *) print_message "ERROR" "$(t invalid_input)"; sleep 1; continue ;;
                esac

                echo ""
                ui_input bot_db_user "$(t bot_db_user)" "postgres"
                BOT_BACKUP_DB_USER="${bot_db_user:-postgres}"

                if [[ "$SKIP_PANEL_BACKUP" == "false" ]]; then
                    echo ""
                    ui_confirm only_bot_confirm "$(t bot_disable_panel)"
                    if [[ "$only_bot_confirm" =~ ^[yY]$ ]]; then
                        SKIP_PANEL_BACKUP="true"
                    fi
                fi

                BOT_BACKUP_ENABLED="true"
                save_config
                print_message "SUCCESS" "$(t bot_saved)"
                read -rp "$(t press_enter)"
                ;;

            2)
                BOT_BACKUP_ENABLED="false"
                BOT_BACKUP_PATH=""
                BOT_BACKUP_SELECTED=""
                
                echo ""
                print_message "SUCCESS" "$(t bot_turned_off)"

                if [[ "$SKIP_PANEL_BACKUP" == "true" && "$REMNALABS_ROOT_DIR" != "none" && -n "$REMNALABS_ROOT_DIR" ]]; then
                    print_message "WARN" "$(t bot_panel_also_off)"
                    ui_confirm restore_p "$(t bot_enable_panel_back)"
                    if [[ "$restore_p" =~ ^[yY]$ ]]; then
                        SKIP_PANEL_BACKUP="false"
                        print_message "SUCCESS" "$(t bot_panel_restored)"
                    fi
                fi
                
                save_config
                read -rp "$(t press_enter)"
                ;;

            3)
                if [[ "$SKIP_PANEL_BACKUP" == "true" ]]; then
                    SKIP_PANEL_BACKUP="false"
                    print_message "SUCCESS" "$(t bot_mode_to_panel_bot)"
                else
                    SKIP_PANEL_BACKUP="true"
                    print_message "SUCCESS" "$(t bot_mode_to_only_bot)"
                fi
                save_config
                read -rp "$(t press_enter)"
                ;;

            0) break ;;
            *) print_message "ERROR" "$(t invalid_input)" ; sleep 1 ;;
        esac
    done
}

get_bot_params() {
    local bot_name="$1"
    
    case "$bot_name" in
        "Бот от Иисуса")
            echo "remnawave-telegram-shop-db|remnawave-telegram-shop-db-data|remnawave-telegram-shop|db"
            ;;
        "Приватный бот от Иисуса")
            echo "rwp_shop_db|rwp_shop_rwp_shop_db_data|rwp-shop|db"
            ;;
        "Бот от Мачки")
            echo "remnawave-tg-shop-db|remnawave-tg-shop-db-data|remnawave-tg-shop|remnawave-tg-shop-db"
            ;;
        "Бот от Snoups")
            echo "remnashop-db|remnashop-db-data|remnashop|remnashop-db"
            ;;
        "Бот Minishop")
            echo "remnawave-minishop-postgres|remnawave-minishop-db-data|remnawave-minishop|postgres"
            ;;
        *)
            echo "|||"
            ;;
    esac
}

get_bot_assistant_params() {
    case "$1" in
        "Приватный бот от Иисуса")
            echo "kb-db|rwp-shop-kb-db|rwp-shop-kb-db-data"
            ;;
        *)
            echo "||"
            ;;
    esac
}

_find_service_container() {
    local service="$1" workdir fallback="$3" cid name=""
    workdir=$(readlink -f "$2" 2>/dev/null || echo "$2")
    cid=$(docker ps -q \
        --filter "label=com.docker.compose.service=${service}" \
        --filter "label=com.docker.compose.project.working_dir=${workdir}" 2>/dev/null | head -n 1)
    if [[ -n "$cid" ]]; then
        name=$(docker inspect -f '{{.Name}}' "$cid" 2>/dev/null | sed 's#^/##')
    fi
    echo "${name:-$fallback}"
}

_container_env() {
    docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$1" 2>/dev/null | sed -n "s/^$2=//p" | head -n 1
}

_container_pg_identity() {
    local user db
    user=$(_container_env "$1" POSTGRES_USER)
    user="${user:-postgres}"
    db=$(_container_env "$1" POSTGRES_DB)
    db="${db:-$user}"
    echo "$user $db"
}

_compose_pg_volumes() {
    docker compose config --format json 2>/dev/null | jq -r --arg s "$1" '
        . as $c | ($c.services[$s].volumes // [])[]
        | select(.type == "volume" and ((.target // "") | startswith("/var/lib/postgresql")))
        | ($c.volumes[.source].name // .source)' 2>/dev/null
}

_remove_volume_if_exists() {
    local vol="$1"
    docker volume ls -q | grep -Fxq "$vol" || return 1
    local users
    users=$(docker ps -aq --filter volume="$vol")
    if [[ -n "$users" ]]; then
        print_message "INFO" "$(t rbot_vol_used)"
        docker rm -f $users >/dev/null 2>&1 || true
    fi
    if docker volume rm "$vol" >/dev/null 2>&1; then
        print_message "SUCCESS" "$(t rbot_vol_rm) $vol."
    else
        print_message "WARN" "$(t rbot_vol_rm_fail) $vol."
    fi
    return 0
}

_wait_container_healthy() {
    local container="$1" waited=0 st
    while true; do
        st=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$container" 2>/dev/null)
        [[ "$st" == "healthy" ]] && break
        if [[ -z "$st" ]] && docker exec "$container" pg_isready -q >/dev/null 2>&1; then
            break
        fi
        sleep 2
        echo -n "."
        waited=$((waited + 1))
        if [ $waited -gt 60 ]; then
            echo ""
            return 1
        fi
    done
    echo ""
    return 0
}

check_docker_installed() {
    if ! command -v docker &> /dev/null; then
        print_message "ERROR" "$(t docker_missing)"
        ui_confirm install_choice "$(t docker_install_q)"
        
        if [[ "$install_choice" =~ ^[Yy]$ ]]; then
            print_message "INFO" "$(t docker_installing)"
            if curl -fsSL https://get.docker.com | sh > /dev/null 2>&1; then
                print_message "SUCCESS" "$(t docker_installed)"
            else
                print_message "ERROR" "$(t docker_install_fail)"
                return 1
            fi
        else
            print_message "INFO" "$(t docker_cancelled)"
            return 1
        fi
    fi
    return 0
}

create_bot_backup() {
    if [[ "$BOT_BACKUP_ENABLED" != "true" ]]; then
        return 0
    fi
    
    print_message "INFO" "$(t cbot_creating) ${BOLD}${BOT_BACKUP_SELECTED}${RESET}..."
    
    local bot_params=$(get_bot_params "$BOT_BACKUP_SELECTED")
    IFS='|' read -r BOT_CONTAINER_NAME BOT_VOLUME_NAME BOT_DIR_NAME BOT_SERVICE_NAME <<< "$bot_params"
    
    if [[ -z "$BOT_CONTAINER_NAME" ]]; then
        print_message "ERROR" "$(t cbot_unknown) $BOT_BACKUP_SELECTED"
        print_message "INFO" "$(t cbot_skip)"
        return 0
    fi

    local BOT_BACKUP_FILE_DB="bot_dump_${TIMESTAMP}.sql.gz"
    local BOT_DIR_ARCHIVE="bot_dir_${TIMESTAMP}.tar.gz"
    
    if ! docker inspect "$BOT_CONTAINER_NAME" > /dev/null 2>&1 || ! docker container inspect -f '{{.State.Running}}' "$BOT_CONTAINER_NAME" 2>/dev/null | grep -q "true"; then
        print_message "WARN" "$(t cbot_not_running)"
        return 0
    fi
    
    ui_spin_start "$(t cbot_dumping)"
    if ! docker exec "$BOT_CONTAINER_NAME" pg_dumpall -c -U "$BOT_BACKUP_DB_USER" | gzip -9 > "$BACKUP_DIR/$BOT_BACKUP_FILE_DB"; then
        print_message "ERROR" "$(t cbot_dump_err)"
        return 0
    fi
    META_BOT_VERSION=$(get_rwp_shop_version)

    local ai_params
    ai_params=$(get_bot_assistant_params "$BOT_BACKUP_SELECTED")
    local AI_SERVICE AI_FALLBACK_CONTAINER AI_FALLBACK_VOLUME
    IFS='|' read -r AI_SERVICE AI_FALLBACK_CONTAINER AI_FALLBACK_VOLUME <<< "$ai_params"
    if [[ -n "$AI_SERVICE" ]]; then
        local AI_CONTAINER
        AI_CONTAINER=$(_find_service_container "$AI_SERVICE" "$BOT_BACKUP_PATH" "$AI_FALLBACK_CONTAINER")
        if docker container inspect -f '{{.State.Running}}' "$AI_CONTAINER" 2>/dev/null | grep -q "true"; then
            local AI_DB_USER AI_DB_NAME
            read -r AI_DB_USER AI_DB_NAME <<< "$(_container_pg_identity "$AI_CONTAINER")"
            local BOT_AI_DUMP_FILE="bot_assistant_dump_${TIMESTAMP}.sql.gz"
            ui_spin_start "$(t cbot_ai_dumping)"
            if ( set -o pipefail; docker exec "$AI_CONTAINER" pg_dump -c --if-exists -U "$AI_DB_USER" -d "$AI_DB_NAME" | gzip -9 > "$BACKUP_DIR/$BOT_AI_DUMP_FILE" ); then
                BACKUP_ITEMS+=("$BOT_AI_DUMP_FILE")
                print_message "SUCCESS" "$(t cbot_ai_dumped)"
            else
                rm -f "$BACKUP_DIR/$BOT_AI_DUMP_FILE"
                print_message "WARN" "$(t cbot_ai_dump_err)"
            fi
        fi
    fi
    
    if [ -d "$BOT_BACKUP_PATH" ]; then
        ui_spin_start "$(t cbot_archiving) ${BOLD}${BOT_BACKUP_PATH}${RESET}..."
        local exclude_args=""
        for pattern in $BACKUP_EXCLUDE_PATTERNS; do
            exclude_args+="--exclude=$pattern "
        done
        
        eval "tar --warning=no-file-changed -czf '$BACKUP_DIR/$BOT_DIR_ARCHIVE' $exclude_args -C '$(dirname "$BOT_BACKUP_PATH")' '$(basename "$BOT_BACKUP_PATH")'" || true
        local bot_tar_exit=${PIPESTATUS[0]}
        if [[ $bot_tar_exit -lt 2 ]]; then
            print_message "SUCCESS" "$(t cbot_archived)"
        else
            print_message "ERROR" "$(t cbot_arch_err)"
            return 1
        fi
    else
        print_message "WARN" "$(t cbot_dir_missing)"
        return 0
    fi
    
    BACKUP_ITEMS+=("$BOT_BACKUP_FILE_DB" "$BOT_DIR_ARCHIVE")
    
    print_message "SUCCESS" "$(t cbot_done)"
    echo ""
    return 0
}

restore_bot_backup() {
    local temp_restore_dir="$1"
    
    local BOT_DUMP_FILE=$(find "$temp_restore_dir" -name "bot_dump_*.sql.gz" | head -n 1)
    local BOT_DIR_ARCHIVE=$(find "$temp_restore_dir" -name "bot_dir_*.tar.gz" | head -n 1)
    local AI_DUMP_FILE=$(find "$temp_restore_dir" -name "bot_assistant_dump_*.sql.gz" | head -n 1)
    
    if [[ -z "$BOT_DUMP_FILE" && -z "$BOT_DIR_ARCHIVE" && -z "$AI_DUMP_FILE" ]]; then
        return 2
    fi

    check_docker_installed || return 1

    clear
    print_message "INFO" "$(t rbot_found)"
    echo ""
    ui_confirm restore_bot_confirm "$(t rbot_restore_q)"
    
    if [[ ! "$restore_bot_confirm" =~ ^[yY]$ ]]; then
        print_message "INFO" "$(t rbot_cancelled)"
        return 1
    fi

    echo ""
    print_message "ACTION" "$(t rbot_which)"
    ui_menu_reset
    ui_menu_add 1 "$(t bot_jesus)"
    ui_menu_add 2 "$(t bot_jesus_priv)"
    ui_menu_add 3 "$(t bot_machka)"
    ui_menu_add 4 "$(t bot_snoups)"
    ui_menu_add 5 "$(t bot_minishop)"
    ui_menu_gap
    ui_menu_add 0 "$(t back)"

    local bot_choice
    local selected_bot_name
    while true; do
        ui_menu_choose bot_choice
        case "$bot_choice" in
            0) print_message "INFO" "$(t rbot_cancelled)"; return 1 ;;
            1) selected_bot_name="Бот от Иисуса"; break ;;
            2) selected_bot_name="Приватный бот от Иисуса"; break ;;
            3) selected_bot_name="Бот от Мачки"; break ;;
            4) selected_bot_name="Бот от Snoups"; break ;;
            5) selected_bot_name="Бот Minishop"; break ;;
            *) print_message "ERROR" "$(t invalid_input)" ;;
        esac
    done

    if [[ -n "$AI_DUMP_FILE" ]]; then
        local _ai_chk
        _ai_chk=$(get_bot_assistant_params "$selected_bot_name")
        [[ "${_ai_chk%%|*}" == "" ]] && AI_DUMP_FILE=""
    fi
    if [[ -z "$BOT_DUMP_FILE" && -z "$BOT_DIR_ARCHIVE" && -z "$AI_DUMP_FILE" ]]; then
        print_message "ERROR" "$(t rbot_cancelled)"
        return 1
    fi

    local bot_restore_scope="all"
    local -a scope_keys=() scope_labels=()
    local scope_components=0
    [[ -n "$BOT_DUMP_FILE" ]] && scope_components=$((scope_components + 1))
    [[ -n "$AI_DUMP_FILE" ]] && scope_components=$((scope_components + 1))
    [[ -n "$BOT_DIR_ARCHIVE" ]] && scope_components=$((scope_components + 1))

    if (( scope_components >= 2 )); then
        scope_keys+=("all");   scope_labels+=("$(t rs_scope_all)")
        echo ""
        echo "$(t rbot_scope_title)"
        [[ -n "$BOT_DUMP_FILE" ]]   && { scope_keys+=("db");    scope_labels+=("$(t rs_scope_db)"); }
        [[ -n "$AI_DUMP_FILE" ]]    && { scope_keys+=("ai");    scope_labels+=("$(t rs_scope_ai)"); }
        [[ -n "$BOT_DIR_ARCHIVE" ]] && { scope_keys+=("files"); scope_labels+=("$(t rs_scope_files)"); }
        local scope_i
        ui_menu_reset
        for scope_i in "${!scope_keys[@]}"; do
            ui_menu_add "$((scope_i + 1))" "${scope_labels[$scope_i]}"
        done
        ui_menu_add 0 "$(t back)"
        local bot_scope_choice
        ui_menu_choose bot_scope_choice
        echo ""
        if [[ "$bot_scope_choice" == "0" ]]; then
            print_message "INFO" "$(t rbot_cancelled)"; return 1
        elif [[ "$bot_scope_choice" =~ ^[0-9]+$ ]] && (( bot_scope_choice >= 1 && bot_scope_choice <= ${#scope_keys[@]} )); then
            bot_restore_scope="${scope_keys[$((bot_scope_choice - 1))]}"
        else
            print_message "ERROR" "$(t invalid_input_select)"; return 1
        fi
    elif [[ -n "$BOT_DUMP_FILE" ]]; then
        bot_restore_scope="db"
        print_message "WARN" "$(t rs_scope_only_db_found)"
    elif [[ -n "$AI_DUMP_FILE" ]]; then
        bot_restore_scope="ai"
        print_message "WARN" "$(t rs_scope_only_ai_found)"
    else
        bot_restore_scope="files"
        print_message "WARN" "$(t rs_scope_only_files_found)"
    fi
    
    echo ""
    print_message "WARN" "${YELLOW}$(t rbot_warn_stop)${RESET}"
    print_message "WARN" "$(t rbot_warn_conflict)"
    echo ""
    ui_confirm stop_confirm "$(t rbot_continue_q)"
    
    if [[ ! "$stop_confirm" =~ ^[yY]$ ]]; then
        print_message "INFO" "$(t rbot_stop_first)"
        return 1
    fi
    
    echo ""
    print_message "ACTION" "$(t rbot_select_path)"
    local _bot_params_tmp=$(get_bot_params "$selected_bot_name")
    local _bot_dir_name
    IFS='|' read -r _ _ _bot_dir_name _ <<< "$_bot_params_tmp"
    
    ui_menu_reset
    ui_menu_add 1 "/opt/$_bot_dir_name"
    ui_menu_add 2 "/root/$_bot_dir_name"
    ui_menu_add 3 "/opt/stacks/$_bot_dir_name"
    ui_menu_add 4 "$(t custom_path)"
    ui_menu_gap
    ui_menu_add 0 "$(t back)"

    local restore_path
    local path_choice
    while true; do
        ui_menu_choose path_choice
        case "$path_choice" in
        1) restore_path="/opt/$_bot_dir_name"; break ;;
        2) restore_path="/root/$_bot_dir_name"; break ;;
        3) restore_path="/opt/stacks/$_bot_dir_name"; break ;;
        4)
            echo ""
            print_message "INFO" "$(t rbot_enter_path)"
            ui_input custom_restore_path "$(t path_prompt)" "/opt/remnawave"
            if [[ -z "$custom_restore_path" ]]; then
                print_message "ERROR" "$(t rbot_path_empty)"
                echo ""
                read -rp "$(t press_enter)"
                continue
            fi
        
            if [[ ! "$custom_restore_path" = /* ]]; then
                print_message "ERROR" "$(t rbot_path_abs)"
                echo ""
                read -rp "$(t press_enter)"
                continue
            fi
        
            custom_restore_path="${custom_restore_path%/}"
            restore_path="$custom_restore_path"
            print_message "SUCCESS" "$(t rbot_custom_set) ${BOLD}${restore_path}${RESET}"
            break
            ;;
        0)
            print_message "INFO" "$(t rbot_cancelled)"
            return 0
            ;;
        *)
            print_message "ERROR" "$(t invalid_input)"
            ;;
        esac
    done

    local bot_params=$(get_bot_params "$selected_bot_name")
    IFS='|' read -r BOT_CONTAINER_NAME BOT_VOLUME_NAME BOT_DIR_NAME BOT_SERVICE_NAME <<< "$bot_params"

    echo ""
    print_message "INFO" "$(t rbot_starting)"

    if [[ "$bot_restore_scope" == "db" || "$bot_restore_scope" == "ai" ]]; then
        if ! (cd "$restore_path" 2>/dev/null && { [[ -f docker-compose.yml ]] || [[ -f docker-compose.yaml ]] || [[ -f compose.yml ]] || [[ -f compose.yaml ]]; }); then
            print_message "ERROR" "$(t rs_files_required_first)"
            return 1
        fi
    fi

    if [[ -d "$restore_path" ]]; then
        print_message "INFO" "$(t rbot_exists_stop)"

        if cd "$restore_path" 2>/dev/null && ([[ -f "docker-compose.yml" ]] || [[ -f "docker-compose.yaml" ]] || [[ -f "compose.yml" ]] || [[ -f "compose.yaml" ]]); then
            print_message "INFO" "$(t rbot_stopping)"
            docker compose down 2>/dev/null || print_message "WARN" "$(t rbot_stop_fail)"
        else
            print_message "INFO" "$(t rbot_no_compose)"
        fi
    fi

    cd /

    if [[ "$bot_restore_scope" != "db" && "$bot_restore_scope" != "ai" ]]; then
        print_message "INFO" "$(t rbot_rm_old)"
        if [[ -d "$restore_path" ]]; then
            if ! rm -rf "$restore_path"; then
                print_message "ERROR" "$(t rbot_rm_fail) ${BOLD}${restore_path}${RESET}."
                return 1
            fi
            print_message "SUCCESS" "$(t rbot_rm_done)"
        else
            print_message "INFO" "$(t rbot_clean_install)"
        fi

        print_message "INFO" "$(t rbot_mkdir)"
        if ! mkdir -p "$restore_path"; then
            print_message "ERROR" "$(t rbot_mkdir_fail) ${BOLD}${restore_path}${RESET}."
            return 1
        fi
        print_message "SUCCESS" "$(t rbot_mkdir_done)"
        echo ""

        if [[ -n "$BOT_DIR_ARCHIVE" ]]; then
            print_message "INFO" "$(t rbot_unpack_dir)"
            local temp_extract_dir="$BACKUP_DIR/bot_extract_temp_$$"
            mkdir -p "$temp_extract_dir"

            if tar -xzf "$BOT_DIR_ARCHIVE" -C "$temp_extract_dir"; then
                local extracted_dir=$(find "$temp_extract_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1)

                if [[ -n "$extracted_dir" && -d "$extracted_dir" ]]; then
                    if cp -rf "$extracted_dir"/. "$restore_path/" 2>/dev/null; then
                        print_message "SUCCESS" "$(t rbot_files_ok) $(basename "$extracted_dir")"
                    else
                        print_message "ERROR" "$(t rbot_copy_err)"
                        rm -rf "$temp_extract_dir"
                        return 1
                    fi
                else
                    print_message "ERROR" "$(t rbot_extract_err)"
                    rm -rf "$temp_extract_dir"
                    return 1
                fi
            else
                print_message "ERROR" "$(t rbot_unpack_err)"
                rm -rf "$temp_extract_dir"
                return 1
            fi
            rm -rf "$temp_extract_dir"
        fi
    fi

    if [[ "$bot_restore_scope" == "files" ]]; then
        if ! cd "$restore_path"; then
            print_message "ERROR" "$(t rbot_cd_fail) ${BOLD}${restore_path}${RESET}."
            return 1
        fi
        if [[ ! -f "docker-compose.yml" && ! -f "docker-compose.yaml" && ! -f "compose.yml" && ! -f "compose.yaml" ]]; then
            print_message "ERROR" "$(t rbot_no_yml)"
            return 1
        fi
        print_message "INFO" "$(t rbot_start_all)"
        if ! docker compose up -d; then
            print_message "ERROR" "$(t rbot_start_fail)"
            return 1
        fi
        sleep 3
        return 0
    fi

    if [[ "$bot_restore_scope" != "ai" ]]; then
        print_message "INFO" "$(t rbot_check_vol)"
        local -a bot_volumes=("$BOT_VOLUME_NAME")
        local _rv
        if cd "$restore_path" 2>/dev/null; then
            while IFS= read -r _rv; do
                if [[ -n "$_rv" && "$_rv" != "$BOT_VOLUME_NAME" ]]; then bot_volumes+=("$_rv"); fi
            done < <(_compose_pg_volumes "$BOT_SERVICE_NAME")
        fi
        local bot_vol_found=false
        for _rv in "${bot_volumes[@]}"; do
            if _remove_volume_if_exists "$_rv"; then bot_vol_found=true; fi
        done
        if [[ "$bot_vol_found" == "false" ]]; then
            print_message "INFO" "$(t rbot_no_vols)"
        fi
        echo ""
    
        if ! cd "$restore_path"; then
            print_message "ERROR" "$(t rbot_cd_fail) ${BOLD}${restore_path}${RESET}."
            return 1
        fi
    
        if [[ ! -f "docker-compose.yml" && ! -f "docker-compose.yaml" && ! -f "compose.yml" && ! -f "compose.yaml" ]]; then
        print_message "ERROR" "$(t rbot_no_yml)"
        return 1
        fi
    
        print_message "INFO" "$(t rbot_start_db)"
        if ! docker compose up -d "$BOT_SERVICE_NAME"; then
            print_message "ERROR" "$(t rbot_db_fail)"
            return 1
        fi
    
        echo ""
        print_message "INFO" "$(t rbot_wait_db)"
        local wait_count=0
        local max_wait=60
    
        until [ "$(docker inspect --format='{{.State.Health.Status}}' "$BOT_CONTAINER_NAME" 2>/dev/null)" == "healthy" ]; do
            sleep 2
            echo -n "."
            wait_count=$((wait_count + 1))
            if [ $wait_count -gt $max_wait ]; then
                echo ""
                print_message "ERROR" "$(t rbot_db_timeout)"
                return 1
            fi
        done
        echo ""
        print_message "SUCCESS" "$(t rbot_db_ready)"
    
        if [[ -n "$BOT_DUMP_FILE" ]]; then
            ui_spin_start "$(t rbot_restore_db)"
            local BOT_DUMP_UNCOMPRESSED="${BOT_DUMP_FILE%.gz}"
        
            if ! gunzip "$BOT_DUMP_FILE"; then
                print_message "ERROR" "$(t rbot_gunzip_fail)"
                return 1
            fi
        
            mkdir -p "$temp_restore_dir"

            local restore_bot_db_user restore_bot_db_name="postgres"
            read -r restore_bot_db_user _ <<< "$(_container_pg_identity "$BOT_CONTAINER_NAME")"

            if ! docker exec -i "$BOT_CONTAINER_NAME" psql -q -U "$restore_bot_db_user" -d "$restore_bot_db_name" > /dev/null 2> "$temp_restore_dir/restore_errors.log" < "$BOT_DUMP_UNCOMPRESSED"; then
                print_message "ERROR" "$(t rbot_db_err)"
                echo ""
                if [[ -f "$temp_restore_dir/restore_errors.log" ]]; then
                    print_message "WARN" "${YELLOW}$(t rbot_err_log)${RESET}"
                    cat "$temp_restore_dir/restore_errors.log"
                fi
                [[ -d "$temp_restore_dir" ]] && rm -rf "$temp_restore_dir"
                echo ""
                read -rp "$(t press_enter_back)"
                return 1
            fi

            print_message "SUCCESS" "$(t rbot_db_ok)"
        else
            print_message "WARN" "$(t rbot_no_dump)"
        fi
    
    fi

    if [[ "$bot_restore_scope" == "all" || "$bot_restore_scope" == "ai" ]] && [[ -n "$AI_DUMP_FILE" ]]; then
        local ai_params
        ai_params=$(get_bot_assistant_params "$selected_bot_name")
        local AI_SERVICE AI_FALLBACK_CONTAINER AI_FALLBACK_VOLUME
        IFS='|' read -r AI_SERVICE AI_FALLBACK_CONTAINER AI_FALLBACK_VOLUME <<< "$ai_params"

        if [[ -z "$AI_SERVICE" ]]; then
            print_message "WARN" "$(t rbot_ai_unsupported)"
        elif ! cd "$restore_path" 2>/dev/null \
             || ! { [[ -f docker-compose.yml || -f docker-compose.yaml || -f compose.yml || -f compose.yaml ]]; }; then
            print_message "ERROR" "$(t rbot_no_yml)"
            return 1
        elif ! docker compose config --services 2>/dev/null | grep -Fxq "$AI_SERVICE"; then
            print_message "WARN" "$(t rbot_ai_no_service)"
        else
            echo ""
            print_message "INFO" "$(t rbot_ai_restoring)"

            local -a ai_volumes=("$AI_FALLBACK_VOLUME")
            local _av
            while IFS= read -r _av; do
                if [[ -n "$_av" && "$_av" != "$AI_FALLBACK_VOLUME" ]]; then ai_volumes+=("$_av"); fi
            done < <(_compose_pg_volumes "$AI_SERVICE")
            for _av in "${ai_volumes[@]}"; do
                _remove_volume_if_exists "$_av" || true
            done

            if ! docker compose up -d "$AI_SERVICE"; then
                print_message "ERROR" "$(t rbot_ai_db_fail)"
                return 1
            fi

            local AI_CONTAINER AI_DB_USER AI_DB_NAME
            AI_CONTAINER=$(_find_service_container "$AI_SERVICE" "$restore_path" "$AI_FALLBACK_CONTAINER")
            print_message "INFO" "$(t rbot_ai_wait)"
            if ! _wait_container_healthy "$AI_CONTAINER"; then
                print_message "ERROR" "$(t rbot_ai_timeout)"
                return 1
            fi
            read -r AI_DB_USER AI_DB_NAME <<< "$(_container_pg_identity "$AI_CONTAINER")"

            mkdir -p "$temp_restore_dir"
            if ! gunzip -c "$AI_DUMP_FILE" | docker exec -i "$AI_CONTAINER" psql -q -U "$AI_DB_USER" -d "$AI_DB_NAME" > /dev/null 2> "$temp_restore_dir/restore_ai_errors.log"; then
                print_message "ERROR" "$(t rbot_ai_db_err)"
                if [[ -s "$temp_restore_dir/restore_ai_errors.log" ]]; then
                    print_message "WARN" "${YELLOW}$(t rbot_err_log)${RESET}"
                    cat "$temp_restore_dir/restore_ai_errors.log"
                fi
                echo ""
                read -rp "$(t press_enter_back)"
                return 1
            fi
            print_message "SUCCESS" "$(t rbot_ai_db_ok)"
        fi
    fi

    echo ""
    print_message "INFO" "$(t rbot_start_all)"
    if ! docker compose up -d; then
        print_message "ERROR" "$(t rbot_start_fail)"
        return 1
    fi
    
    sleep 3
    return 0
}

save_config() {
    print_message "INFO" "$(t saving_config) ${BOLD}${CONFIG_FILE}${RESET}..."
    cat > "$CONFIG_FILE" <<EOF
BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
DB_USER="$DB_USER"
UPLOAD_METHOD="$UPLOAD_METHOD"

S3_ENDPOINT="$S3_ENDPOINT"
S3_ACCESS_KEY="$S3_ACCESS_KEY"
S3_SECRET_KEY="$S3_SECRET_KEY"
S3_BUCKET="$S3_BUCKET"
S3_REGION="$S3_REGION"
S3_PREFIX="$S3_PREFIX"
S3_RETAIN_DAYS="$S3_RETAIN_DAYS"
S3_LIMIT_GB="$S3_LIMIT_GB"
S3_NAME="$S3_NAME"
S3_COUNT="${S3_COUNT:-1}"
S3_2_NAME="$S3_2_NAME"
S3_2_ENDPOINT="$S3_2_ENDPOINT"
S3_2_ACCESS_KEY="$S3_2_ACCESS_KEY"
S3_2_SECRET_KEY="$S3_2_SECRET_KEY"
S3_2_BUCKET="$S3_2_BUCKET"
S3_2_REGION="$S3_2_REGION"
S3_2_PREFIX="$S3_2_PREFIX"
S3_2_RETAIN_DAYS="$S3_2_RETAIN_DAYS"
S3_2_LIMIT_GB="$S3_2_LIMIT_GB"
S3_3_NAME="$S3_3_NAME"
S3_3_ENDPOINT="$S3_3_ENDPOINT"
S3_3_ACCESS_KEY="$S3_3_ACCESS_KEY"
S3_3_SECRET_KEY="$S3_3_SECRET_KEY"
S3_3_BUCKET="$S3_3_BUCKET"
S3_3_REGION="$S3_3_REGION"
S3_3_PREFIX="$S3_3_PREFIX"
S3_3_RETAIN_DAYS="$S3_3_RETAIN_DAYS"
S3_3_LIMIT_GB="$S3_3_LIMIT_GB"
S3_4_NAME="$S3_4_NAME"
S3_4_ENDPOINT="$S3_4_ENDPOINT"
S3_4_ACCESS_KEY="$S3_4_ACCESS_KEY"
S3_4_SECRET_KEY="$S3_4_SECRET_KEY"
S3_4_BUCKET="$S3_4_BUCKET"
S3_4_REGION="$S3_4_REGION"
S3_4_PREFIX="$S3_4_PREFIX"
S3_4_RETAIN_DAYS="$S3_4_RETAIN_DAYS"
S3_4_LIMIT_GB="$S3_4_LIMIT_GB"
S3_5_NAME="$S3_5_NAME"
S3_5_ENDPOINT="$S3_5_ENDPOINT"
S3_5_ACCESS_KEY="$S3_5_ACCESS_KEY"
S3_5_SECRET_KEY="$S3_5_SECRET_KEY"
S3_5_BUCKET="$S3_5_BUCKET"
S3_5_REGION="$S3_5_REGION"
S3_5_PREFIX="$S3_5_PREFIX"
S3_5_RETAIN_DAYS="$S3_5_RETAIN_DAYS"
S3_5_LIMIT_GB="$S3_5_LIMIT_GB"
RETAIN_BACKUPS_DAYS="$RETAIN_BACKUPS_DAYS"
RETAIN_BACKUPS_VALUE="${RETAIN_BACKUPS_VALUE:-$RETAIN_BACKUPS_DAYS}"
RETAIN_BACKUPS_UNIT="${RETAIN_BACKUPS_UNIT:-days}"
CRON_TIMES="$CRON_TIMES"
REMNALABS_ROOT_DIR="$REMNALABS_ROOT_DIR"
TG_MESSAGE_THREAD_ID="$TG_MESSAGE_THREAD_ID"
TG_PROXY="$TG_PROXY"
BOT_BACKUP_ENABLED="$BOT_BACKUP_ENABLED"
BOT_BACKUP_PATH="$BOT_BACKUP_PATH"
BOT_BACKUP_SELECTED="$BOT_BACKUP_SELECTED"
BOT_BACKUP_DB_USER="$BOT_BACKUP_DB_USER"
SKIP_PANEL_BACKUP="$SKIP_PANEL_BACKUP"
DB_CONNECTION_TYPE="$DB_CONNECTION_TYPE"
DB_HOST="$DB_HOST"
DB_PORT="$DB_PORT"
DB_NAME="$DB_NAME"
DB_PASSWORD="$DB_PASSWORD"
DB_SSL_MODE="$DB_SSL_MODE"
DB_POSTGRES_VERSION="$DB_POSTGRES_VERSION"
LANG_CODE="$LANG_CODE"
AUTO_UPDATE="$AUTO_UPDATE"
ENCRYPT_ENABLED="$ENCRYPT_ENABLED"
ENCRYPT_PUBLIC_KEY="$ENCRYPT_PUBLIC_KEY"
EOF
    chmod 600 "$CONFIG_FILE" || { print_message "ERROR" "$(t chmod_error) ${BOLD}${CONFIG_FILE}${RESET}. $(t check_permissions)"; exit 1; }
    print_message "SUCCESS" "$(t config_saved)"
}

load_or_create_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        print_message "INFO" "$(t cfg_loading)"
        source "$CONFIG_FILE"
        echo ""

        UPLOAD_METHOD=${UPLOAD_METHOD:-telegram}
        DB_USER=${DB_USER:-postgres}
        CRON_TIMES=${CRON_TIMES:-}
        REMNALABS_ROOT_DIR=${REMNALABS_ROOT_DIR:-}
        TG_MESSAGE_THREAD_ID=${TG_MESSAGE_THREAD_ID:-}
        TG_PROXY=${TG_PROXY:-}
        SKIP_PANEL_BACKUP=${SKIP_PANEL_BACKUP:-false}
        DB_CONNECTION_TYPE=${DB_CONNECTION_TYPE:-docker}
        DB_HOST=${DB_HOST:-}
        DB_PORT=${DB_PORT:-5432}
        DB_NAME=${DB_NAME:-postgres}
        DB_PASSWORD=${DB_PASSWORD:-}
        DB_SSL_MODE=${DB_SSL_MODE:-prefer}
        DB_POSTGRES_VERSION=${DB_POSTGRES_VERSION:-17}
        S3_ENDPOINT=${S3_ENDPOINT:-}
        S3_ACCESS_KEY=${S3_ACCESS_KEY:-}
        S3_SECRET_KEY=${S3_SECRET_KEY:-}
        S3_BUCKET=${S3_BUCKET:-}
        S3_REGION=${S3_REGION:-}
        S3_PREFIX=${S3_PREFIX:-}
        S3_RETAIN_DAYS=${S3_RETAIN_DAYS:-30}
        S3_LIMIT_GB=${S3_LIMIT_GB:-}
        S3_NAME=${S3_NAME:-}
        S3_COUNT=${S3_COUNT:-1}
        [[ "$S3_COUNT" -lt 1 ]] && S3_COUNT=1
        [[ "$S3_COUNT" -gt 5 ]] && S3_COUNT=5
        S3_2_NAME=${S3_2_NAME:-}
        S3_2_ENDPOINT=${S3_2_ENDPOINT:-}
        S3_2_ACCESS_KEY=${S3_2_ACCESS_KEY:-}
        S3_2_SECRET_KEY=${S3_2_SECRET_KEY:-}
        S3_2_BUCKET=${S3_2_BUCKET:-}
        S3_2_REGION=${S3_2_REGION:-}
        S3_2_PREFIX=${S3_2_PREFIX:-}
        S3_2_RETAIN_DAYS=${S3_2_RETAIN_DAYS:-30}
        S3_2_LIMIT_GB=${S3_2_LIMIT_GB:-}
        S3_3_NAME=${S3_3_NAME:-}
        S3_3_ENDPOINT=${S3_3_ENDPOINT:-}
        S3_3_ACCESS_KEY=${S3_3_ACCESS_KEY:-}
        S3_3_SECRET_KEY=${S3_3_SECRET_KEY:-}
        S3_3_BUCKET=${S3_3_BUCKET:-}
        S3_3_REGION=${S3_3_REGION:-}
        S3_3_PREFIX=${S3_3_PREFIX:-}
        S3_3_RETAIN_DAYS=${S3_3_RETAIN_DAYS:-30}
        S3_3_LIMIT_GB=${S3_3_LIMIT_GB:-}
        S3_4_NAME=${S3_4_NAME:-}
        S3_4_ENDPOINT=${S3_4_ENDPOINT:-}
        S3_4_ACCESS_KEY=${S3_4_ACCESS_KEY:-}
        S3_4_SECRET_KEY=${S3_4_SECRET_KEY:-}
        S3_4_BUCKET=${S3_4_BUCKET:-}
        S3_4_REGION=${S3_4_REGION:-}
        S3_4_PREFIX=${S3_4_PREFIX:-}
        S3_4_RETAIN_DAYS=${S3_4_RETAIN_DAYS:-30}
        S3_4_LIMIT_GB=${S3_4_LIMIT_GB:-}
        S3_5_NAME=${S3_5_NAME:-}
        S3_5_ENDPOINT=${S3_5_ENDPOINT:-}
        S3_5_ACCESS_KEY=${S3_5_ACCESS_KEY:-}
        S3_5_SECRET_KEY=${S3_5_SECRET_KEY:-}
        S3_5_BUCKET=${S3_5_BUCKET:-}
        S3_5_REGION=${S3_5_REGION:-}
        S3_5_PREFIX=${S3_5_PREFIX:-}
        S3_5_RETAIN_DAYS=${S3_5_RETAIN_DAYS:-30}
        S3_5_LIMIT_GB=${S3_5_LIMIT_GB:-}
        RETAIN_BACKUPS_DAYS=${RETAIN_BACKUPS_DAYS:-7}
        RETAIN_BACKUPS_VALUE=${RETAIN_BACKUPS_VALUE:-$RETAIN_BACKUPS_DAYS}
        RETAIN_BACKUPS_UNIT=${RETAIN_BACKUPS_UNIT:-days}
        LANG_CODE=${LANG_CODE:-}
        AUTO_UPDATE=${AUTO_UPDATE:-false}
        ENCRYPT_ENABLED=${ENCRYPT_ENABLED:-false}
        ENCRYPT_PUBLIC_KEY=${ENCRYPT_PUBLIC_KEY:-}
        
        if [[ -z "$LANG_CODE" || ! -f "$TRANSLATIONS_DIR/$LANG_CODE.sh" ]]; then
            download_translations
            select_language_interactive
            save_config
        else
            load_language "$LANG_CODE"
        fi
        
        local config_updated=false

        if [[ -z "$BOT_TOKEN" || -z "$CHAT_ID" ]]; then
            print_message "WARN" "$(t cfg_tg_not_configured)"
        fi

        if [[ "$SKIP_PANEL_BACKUP" != "true" && -z "$DB_USER" ]]; then
            print_message "INFO" "$(t cfg_enter_db_user)"
            ui_input input_db_user "$(t input_prompt)"
            DB_USER=${input_db_user:-postgres}
            config_updated=true
            echo ""
        fi
        
        if [[ "$SKIP_PANEL_BACKUP" != "true" && -z "$REMNALABS_ROOT_DIR" ]]; then
            print_message "ACTION" "$(t cfg_where_panel)"
            ui_menu_reset
            ui_menu_add 1 "/opt/remnawave"
            ui_menu_add 2 "/root/remnawave"
            ui_menu_add 3 "/opt/stacks/remnawave"
            ui_menu_add 4 "$(t custom_path)"

            local remnawave_path_choice
            while true; do
                ui_menu_choose remnawave_path_choice
                case "$remnawave_path_choice" in
                1) REMNALABS_ROOT_DIR="/opt/remnawave"; break ;;
                2) REMNALABS_ROOT_DIR="/root/remnawave"; break ;;
                3) REMNALABS_ROOT_DIR="/opt/stacks/remnawave"; break ;;
                4) 
                    echo ""
                    print_message "INFO" "$(t cfg_enter_panel_path)"
                    ui_input custom_remnawave_path "$(t path_prompt)" "/opt/remnawave"
                    if [[ -z "$custom_remnawave_path" ]]; then
                        print_message "ERROR" "$(t cfg_path_empty)"
                        echo ""
                        read -rp "$(t press_enter)"
                        continue
                    fi
    
                    if [[ ! "$custom_remnawave_path" = /* ]]; then
                        print_message "ERROR" "$(t cfg_path_abs)"
                        echo ""
                        read -rp "$(t press_enter)"
                        continue
                    fi
    
                    custom_remnawave_path="${custom_remnawave_path%/}"
    
                    if [[ ! -d "$custom_remnawave_path" ]]; then
                        print_message "WARN" "$(t cfg_dir_missing) ${BOLD}${custom_remnawave_path}${RESET}"
                        ui_confirm confirm_custom_path "$(t cfg_continue_path)"
                        if [[ "$confirm_custom_path" != "y" ]]; then
                            echo ""
                            read -rp "$(t press_enter)"
                            continue
                        fi
                    fi
    
                    REMNALABS_ROOT_DIR="$custom_remnawave_path"
                    print_message "SUCCESS" "$(t cfg_custom_set) ${BOLD}${REMNALABS_ROOT_DIR}${RESET}"
                    break 
                    ;;
                *) print_message "ERROR" "$(t invalid_input)" ;;
                esac
            done
            config_updated=true
            echo ""
        fi

        if [[ "$UPLOAD_METHOD" == "google_drive" ]]; then
            print_message "WARN" "$(t cfg_gd_removed)"
            UPLOAD_METHOD="telegram"
            config_updated=true
            ( send_telegram_message "⚠️ $(t cfg_gd_removed_tg)" "None" >/dev/null 2>&1 || true ) &
        fi

        if [[ "$UPLOAD_METHOD" == "s3" ]]; then
            if [[ -z "$S3_BUCKET" || -z "$S3_ACCESS_KEY" || -z "$S3_SECRET_KEY" ]]; then
                print_message "WARN" "$(t cfg_s3_incomplete)"
                print_message "WARN" "$(t cfg_s3_switch_tg)"
                UPLOAD_METHOD="telegram"
                config_updated=true
            fi
        fi

        if $config_updated; then
            save_config
        else
            print_message "SUCCESS" "$(t cfg_loaded) ${BOLD}${CONFIG_FILE}${RESET}."
        fi

    else
        if [[ "$SCRIPT_RUN_PATH" != "$SCRIPT_PATH" ]]; then
            print_message "INFO" "Configuration not found. Script launched from temporary location."
            print_message "INFO" "Moving script to main install directory: ${BOLD}${SCRIPT_PATH}${RESET}..."
            mkdir -p "$INSTALL_DIR" || { print_message "ERROR" "$(t cfg_install_fail) ${BOLD}${INSTALL_DIR}${RESET}."; exit 1; }
            mkdir -p "$BACKUP_DIR" || { print_message "ERROR" "$(t cfg_backup_fail) ${BOLD}${BACKUP_DIR}${RESET}."; exit 1; }

            if mv "$SCRIPT_RUN_PATH" "$SCRIPT_PATH"; then
                chmod +x "$SCRIPT_PATH"
                clear
                print_message "SUCCESS" "Script successfully moved to ${BOLD}${SCRIPT_PATH}${RESET}."
                print_message "ACTION" "Restarting script from new location to complete setup."
                exec "$SCRIPT_PATH" "$@"
                exit 0
            else
                print_message "ERROR" "$(t cfg_move_fail) ${BOLD}${SCRIPT_PATH}${RESET}."
                exit 1
            fi
        else
            print_message "INFO" "Configuration not found, creating new..."
            echo ""

            download_translations
            select_language_interactive
            echo ""

            print_message "ACTION" "$(t cfg_select_mode)"
            ui_menu_reset
            ui_menu_add 1 "$(t cfg_mode_full)"
            ui_menu_add 2 "$(t cfg_mode_bot)"
            ui_menu_choose main_mode_choice
            
            if [[ "$main_mode_choice" == "2" ]]; then
                SKIP_PANEL_BACKUP="true"
                REMNALABS_ROOT_DIR="none"
            else
                SKIP_PANEL_BACKUP="false"
            fi
            echo ""

            print_message "INFO" "$(t cfg_tg_setup)"
            print_message "INFO" "$(t cfg_create_bot)"
            print_message "INFO" "$(t cfg_tg_skip_hint)"
            print_message "WARN" "$(t cfg_tg_skip_warn)"
            ui_input BOT_TOKEN "$(t cfg_enter_token)" "123456789:AAH..."
            echo ""
            print_message "INFO" "$(t cfg_chatid_desc)"
            echo -e "   $(t cfg_chatid_help)"
            ui_input CHAT_ID "$(t cfg_enter_chatid)" "-1001234567890"
            echo ""
            print_message "INFO" "$(t cfg_thread_info)"
            echo -e "   $(t cfg_thread_empty)"
            ui_input TG_MESSAGE_THREAD_ID "$(t cfg_enter_thread)"
            echo ""

            if [[ "$SKIP_PANEL_BACKUP" == "false" ]]; then
                print_message "INFO" "$(t cfg_enter_db_user_default)"
                ui_input input_db_user "$(t input_prompt)"
                DB_USER=${input_db_user:-postgres}
                echo ""

                print_message "ACTION" "$(t cfg_where_panel)"
                ui_menu_reset
                ui_menu_add 1 "/opt/remnawave"
                ui_menu_add 2 "/root/remnawave"
                ui_menu_add 3 "/opt/stacks/remnawave"
                ui_menu_add 4 "$(t custom_path)"

                local remnawave_path_choice
                while true; do
                    ui_menu_choose remnawave_path_choice
                    case "$remnawave_path_choice" in
                    1) REMNALABS_ROOT_DIR="/opt/remnawave"; break ;;
                    2) REMNALABS_ROOT_DIR="/root/remnawave"; break ;;
                    3) REMNALABS_ROOT_DIR="/opt/stacks/remnawave"; break ;;
                    4) 
                        echo ""
                        print_message "INFO" "$(t cfg_enter_panel_path)"
                        ui_input custom_remnawave_path "$(t path_prompt)" "/opt/remnawave"
                        if [[ -n "$custom_remnawave_path" ]]; then
                            REMNALABS_ROOT_DIR="${custom_remnawave_path%/}"
                            break
                        fi
                        ;;
                    *) print_message "ERROR" "$(t invalid_input)" ;;
                    esac
                done
            fi

            mkdir -p "$INSTALL_DIR"
            mkdir -p "$BACKUP_DIR"
            save_config
            print_message "SUCCESS" "$(t cfg_new_saved) ${BOLD}${CONFIG_FILE}${RESET}"
        fi
    fi

    echo ""
}

escape_markdown_v2() {
    local text="$1"
    echo "$text" | sed \
        -e 's/\\/\\\\/g' \
        -e 's/_/\\_/g' \
        -e 's/\[/\\[/g' \
        -e 's/\]/\\]/g' \
        -e 's/(/\\(/g' \
        -e 's/)/\\)/g' \
        -e 's/~/\\~/g' \
        -e 's/`/\\`/g' \
        -e 's/>/\\>/g' \
        -e 's/#/\\#/g' \
        -e 's/+/\\+/g' \
        -e 's/-/\\-/g' \
        -e 's/=/\\=/g' \
        -e 's/|/\\|/g' \
        -e 's/{/\\{/g' \
        -e 's/}/\\}/g' \
        -e 's/\./\\./g' \
        -e 's/!/\\!/g'
}

get_remnawave_version() {
    local version_output
    version_output=$(docker exec remnawave sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' package.json 2>/dev/null)
    if [[ -z "$version_output" ]]; then
        echo "$(t ver_undefined)"
    else
        echo "$version_output"
    fi
}

get_rwp_shop_version() {
    if [[ "$BOT_BACKUP_ENABLED" != "true" || "$BOT_BACKUP_SELECTED" != "Приватный бот от Иисуса" ]]; then
        return 0
    fi
    local ver=""
    ver=$(docker inspect rwp_shop --format '{{index .Config.Labels "org.opencontainers.image.version"}}' 2>/dev/null) || ver=""
    [[ "$ver" == "<no value>" ]] && ver=""
    printf '%s' "$ver"
}

_ver_disp() {
    if [[ -z "$1" ]]; then
        t rs_meta_unknown
    elif [[ "$1" =~ ^[0-9] ]]; then
        echo "v$1"
    else
        echo "$1"
    fi
}

print_aligned_rows() {
    local LC_ALL=C.UTF-8
    local width=0 i j label
    for ((i = 1; i <= $#; i += 2)); do
        label="${!i}"
        (( ${#label} > width )) && width=${#label}
    done
    for ((i = 1; i <= $#; i += 2)); do
        j=$((i + 1))
        label="${!i}"
        echo -e "   ${label}$(printf '%*s' $((width - ${#label})) '') ${BOLD}${!j}${RESET}"
    done
}

get_postgres_image() {
    echo "postgres:${DB_POSTGRES_VERSION}-alpine"
}

LAST_DB_ERROR=""

create_panel_db_dump() {
    local dump_file="$1"
    local pg_image=$(get_postgres_image)
    LAST_DB_ERROR=""
    
    case "$DB_CONNECTION_TYPE" in
        docker)
            if ! docker inspect remnawave-db > /dev/null 2>&1 || ! docker container inspect -f '{{.State.Running}}' remnawave-db 2>/dev/null | grep -q "true"; then
                LAST_DB_ERROR="$(t db_container_missing)"
                print_message "ERROR" "$LAST_DB_ERROR"
                return 1
            fi
            
            local docker_error_log=$(mktemp)
            docker exec "remnawave-db" pg_dumpall -c -U "$DB_USER" 2>"$docker_error_log" | gzip -9 > "$dump_file"
            local dump_exit_code=${PIPESTATUS[0]}
            if [[ $dump_exit_code -ne 0 ]]; then
                LAST_DB_ERROR=$(cat "$docker_error_log" 2>/dev/null | head -5 | tr '\n' ' ')
                rm -f "$docker_error_log"
                return 1
            fi
            rm -f "$docker_error_log"
            ;;
        external)
            if [[ -z "$DB_HOST" ]]; then
                LAST_DB_ERROR="$(t db_host_missing)"
                print_message "ERROR" "$LAST_DB_ERROR"
                return 1
            fi
            
            ui_spin_start "$(t db_connecting) ${BOLD}${DB_HOST}:${DB_PORT}/${DB_NAME}${RESET}"
            
            local pg_dump_error_log=$(mktemp)
            
            docker run --rm --network host \
                -e PGPASSWORD="$DB_PASSWORD" \
                -e PGSSLMODE="$DB_SSL_MODE" \
                "$pg_image" \
                pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
                --clean --if-exists 2>"$pg_dump_error_log" | gzip -9 > "$dump_file"
            
            local pg_dump_exit_code=${PIPESTATUS[0]}
            
            if [[ $pg_dump_exit_code -ne 0 ]]; then
                print_message "ERROR" "$(t db_dump_err)"
                if [[ -s "$pg_dump_error_log" ]]; then
                    LAST_DB_ERROR=$(cat "$pg_dump_error_log" | head -5 | tr '\n' ' ')
                    print_message "ERROR" "$(t db_err_details)"
                    cat "$pg_dump_error_log"
                fi
                rm -f "$pg_dump_error_log"
                return 1
            fi
            rm -f "$pg_dump_error_log"
            
            local dump_size=$(stat -c%s "$dump_file" 2>/dev/null || stat -f%z "$dump_file" 2>/dev/null || echo "0")
            if [[ "$dump_size" -lt 100 ]]; then
                LAST_DB_ERROR="$(printf "$(t db_dump_small)" "$dump_size")"
                print_message "ERROR" "$LAST_DB_ERROR"
                return 1
            fi
            ;;
        *)
            LAST_DB_ERROR="$(t db_unknown_type) ${DB_CONNECTION_TYPE}"
            print_message "ERROR" "$LAST_DB_ERROR"
            return 1
            ;;
    esac
    
    return 0
}

restore_panel_db_dump() {
    local sql_file="$1"
    local restore_db_name="$2"
    local restore_log="$3"
    local pg_image=$(get_postgres_image)
    
    case "$DB_CONNECTION_TYPE" in
        docker)
            local restore_db_user
            restore_db_user=$(_container_pg_identity remnawave-db | awk '{print $1}')
            restore_db_user="${restore_db_user:-$DB_USER}"
            if ! docker exec -i remnawave-db psql -q -U "$restore_db_user" -d "$restore_db_name" > /dev/null 2> "$restore_log" < "$sql_file"; then
                return 1
            fi
            ;;
        external)
            print_message "INFO" "$(t db_restoring_ext) ${BOLD}${DB_HOST}:${DB_PORT}/${DB_NAME}${RESET}"
            
            if ! docker run --rm -i --network host \
                -e PGPASSWORD="$DB_PASSWORD" \
                -e PGSSLMODE="$DB_SSL_MODE" \
                "$pg_image" \
                psql -q -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$restore_db_name" \
                2> "$restore_log" < "$sql_file"; then
                return 1
            fi
            ;;
        *)
            print_message "ERROR" "$(t db_unknown_type) ${BOLD}${DB_CONNECTION_TYPE}${RESET}"
            return 1
            ;;
    esac
    
    return 0
}

donate_keyboard() {
    printf '{"inline_keyboard":[[{"text":"%s","url":"%s"}]]}' "$(t tg_donate_btn)" "$DONATE_URL"
}

send_telegram_message() {
    local message="$1"
    local parse_mode="${2:-MarkdownV2}"
    local reply_markup="$3"

    if [[ -z "$BOT_TOKEN" || -z "$CHAT_ID" ]]; then
        return 1
    fi

    local url="https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
    local send_text="$message"

    if [[ "$parse_mode" == "MarkdownV2" ]]; then
        send_text=$(escape_markdown_v2 "$message")
    fi

    local data_params=(
        -d chat_id="$CHAT_ID"
        --data-urlencode "text=${send_text}"
    )

    if [[ -n "$parse_mode" && "$parse_mode" != "None" ]]; then
        data_params+=(-d parse_mode="$parse_mode")
    fi

    [[ -n "$TG_MESSAGE_THREAD_ID" ]] && data_params+=(-d message_thread_id="$TG_MESSAGE_THREAD_ID")
    [[ -n "$reply_markup" ]] && data_params+=(--data-urlencode "reply_markup=${reply_markup}")

    local response http_code
    local max_attempts=3
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        response=$(curl -s --connect-timeout 10 --max-time 30 -X POST ${TG_PROXY:+--proxy "$TG_PROXY"} "$url" "${data_params[@]}" -w "\n%{http_code}")
        local curl_status=$?
        http_code=$(echo "$response" | tail -n1)

        if [[ $curl_status -eq 0 && "$http_code" -eq 200 ]]; then
            return 0
        fi

        if [[ $attempt -lt $max_attempts ]]; then
            sleep 5
        fi
        ((attempt++)) || true
    done

    local body=$(echo "$response" | head -n -1)
    echo -e "${RED}❌ $(t tg_send_err) ${BOLD}$http_code${RESET}"
    echo -e "$(t tg_response) ${body}"
    return 1
}

send_telegram_document() {
    local file_path="$1"
    local caption="$2"
    local reply_markup="$3"
    local parse_mode="MarkdownV2"
    local escaped_caption
    escaped_caption=$(escape_markdown_v2 "$caption")

    if [[ -z "$BOT_TOKEN" || -z "$CHAT_ID" ]]; then
        return 1
    fi

    local form_params=(
        -F chat_id="$CHAT_ID"
        -F document=@"$file_path"
        -F parse_mode="$parse_mode"
        -F caption="$escaped_caption"
    )

    if [[ -n "$TG_MESSAGE_THREAD_ID" ]]; then
        form_params+=(-F message_thread_id="$TG_MESSAGE_THREAD_ID")
    fi
    [[ -n "$reply_markup" ]] && form_params+=(-F reply_markup="$reply_markup")

    local api_response curl_status http_code
    local max_attempts=3
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        api_response=$(curl -s --connect-timeout 10 --max-time 120 -X POST ${TG_PROXY:+--proxy "$TG_PROXY"} "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" \
            "${form_params[@]}" \
            -w "%{http_code}" -o /dev/null 2>&1)
        curl_status=$?
        http_code="${api_response: -3}"

        if [[ $curl_status -eq 0 && "$http_code" == "200" ]]; then
            return 0
        fi

        if [[ $attempt -lt $max_attempts ]]; then
            sleep 5
        fi
        ((attempt++)) || true
    done

    echo -e "${RED}❌ $(t tg_curl_err) ${BOLD}$curl_status${RESET}. $(t tg_check_net)${RESET}"
    return 1
}

install_aws_cli() {
    if command -v aws &> /dev/null; then
        return 0
    fi
    print_message "INFO" "$(t s3_installing_cli)"
    if [[ $EUID -ne 0 ]]; then
        print_message "ERROR" "$(t s3_cli_root)"
        return 1
    fi

    local installed=false

    if command -v apt-get &> /dev/null; then
        apt-get update -qq > /dev/null 2>&1
        if apt-get install -y awscli > /dev/null 2>&1; then
            installed=true
        fi
    elif command -v yum &> /dev/null; then
        if yum install -y awscli > /dev/null 2>&1; then
            installed=true
        fi
    elif command -v dnf &> /dev/null; then
        if dnf install -y awscli > /dev/null 2>&1; then
            installed=true
        fi
    fi

    if ! $installed && ! command -v aws &> /dev/null; then
        print_message "INFO" "$(t s3_cli_fallback)"
        local tmp_dir=$(mktemp -d)
        if curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o "$tmp_dir/awscliv2.zip" 2>/dev/null; then
            if command -v unzip &> /dev/null || apt-get install -y unzip > /dev/null 2>&1 || yum install -y unzip > /dev/null 2>&1; then
                unzip -q "$tmp_dir/awscliv2.zip" -d "$tmp_dir" > /dev/null 2>&1
                if "$tmp_dir/aws/install" > /dev/null 2>&1; then
                    installed=true
                fi
            fi
        fi
        rm -rf "$tmp_dir"
    fi

    if command -v aws &> /dev/null; then
        print_message "SUCCESS" "$(t s3_cli_installed)"
        return 0
    else
        print_message "ERROR" "$(t s3_cli_fail)"
        return 1
    fi
}

_s3_var() {
    local field="$1"
    local num="$2"
    local varname
    if [[ -z "$num" || "$num" == "1" ]]; then
        varname="S3_${field}"
    else
        varname="S3_${num}_${field}"
    fi
    printf '%s' "${!varname}"
}

_s3_set() {
    local field="$1"
    local num="$2"
    local value="$3"
    local varname
    if [[ -z "$num" || "$num" == "1" ]]; then
        varname="S3_${field}"
    else
        varname="S3_${num}_${field}"
    fi
    printf -v "$varname" '%s' "$value"
}

_s3_label() {
    local num="$1"
    local name
    name=$(_s3_var NAME "$num")
    if [[ -n "$name" ]]; then
        printf '%s' "$name"
    else
        printf 'S3 #%s' "${num:-1}"
    fi
}

_retention_display() {
    local value="$1"
    local unit="$2"
    case "$unit" in
        days) unit="$(t st_retention_days)" ;;
        hours) unit="$(t st_retention_hours)" ;;
    esac
    if [[ "${value:-0}" -le 0 ]]; then
        printf '%s' "$(t st_retention_value_disabled)"
    else
        printf '%s %s' "$value" "$unit"
    fi
}

_s3_configured_nums() {
    local count="${S3_COUNT:-1}"
    local i
    for ((i=1; i<=count; i++)); do
        if [[ $i -eq 1 ]]; then
            echo ""
        else
            echo "$i"
        fi
    done
}

STORAGE_CACHE="$INSTALL_DIR/.storage_usage"

_disk_usage() {
    local dir="$BACKUP_DIR"
    [[ -d "$dir" ]] || dir="/"
    df -B1 --output=used,size "$dir" 2>/dev/null | awk 'NR==2 {print $1, $2}'
}

_usage_text() {
    local used="$1" total="${2:-}"
    if [[ -n "$total" && "$total" -gt 0 ]]; then
        printf "$(t usage_of)" "$(_ui_human_size "$used")" "$(_ui_human_size "$total")" "$(( used * 100 / total ))"
    else
        _ui_human_size "$used"
    fi
}

_usage_color() {
    local used="$1" total="${2:-}" pct
    if [[ -z "$total" || "$total" -le 0 ]]; then
        printf '%s' "$BOLD"
        return 0
    fi
    pct=$(( used * 100 / total ))
    if (( pct >= 90 )); then
        printf '%s' "${RED}${BOLD}"
    elif (( pct >= 80 )); then
        printf '%s' "${YELLOW}${BOLD}"
    else
        printf '%s' "$BOLD"
    fi
}

_s3_usage_id() {
    printf '%s|%s|%s' "$(_s3_var ENDPOINT "$1")" "$(_s3_var BUCKET "$1")" "$(_s3_var PREFIX "$1")"
}

_s3_limit_bytes() {
    local gb
    gb=$(_s3_var LIMIT_GB "$1")
    if [[ "$gb" =~ ^[0-9]+$ && "$gb" -gt 0 ]]; then
        echo $(( gb * 1024 * 1024 * 1024 ))
    fi
    return 0
}

_s3_measure_usage() {
    local s3_num="$1" out bytes id endpoint_arg="" prefix
    command -v aws &>/dev/null || return 1
    [[ -n "$(_s3_var ENDPOINT "$s3_num")" ]] && endpoint_arg="--endpoint-url $(_s3_var ENDPOINT "$s3_num")"
    prefix=$(_s3_var PREFIX "$s3_num")
    out=$(AWS_ACCESS_KEY_ID="$(_s3_var ACCESS_KEY "$s3_num")" \
          AWS_SECRET_ACCESS_KEY="$(_s3_var SECRET_KEY "$s3_num")" \
          AWS_DEFAULT_REGION="$(_s3_var REGION "$s3_num")" \
          aws s3 ls "s3://$(_s3_var BUCKET "$s3_num")/${prefix:+${prefix}/}" --recursive --summarize \
          $endpoint_arg 2>/dev/null) || return 1
    bytes=$(awk -F': *' '/Total Size/ {print $2; exit}' <<< "$out")
    [[ "$bytes" =~ ^[0-9]+$ ]] || return 1
    id=$(_s3_usage_id "$s3_num")
    if [[ -d "$INSTALL_DIR" ]]; then
        { grep -vF "${id}|" "$STORAGE_CACHE" 2>/dev/null || true; echo "${id}|${bytes}|$(date +%s)"; } > "${STORAGE_CACHE}.tmp" \
            && mv "${STORAGE_CACHE}.tmp" "$STORAGE_CACHE"
        chmod 600 "$STORAGE_CACHE" 2>/dev/null || true
    fi
    echo "$bytes"
}

_s3_cached_usage() {
    local id
    id=$(_s3_usage_id "$1")
    [[ -f "$STORAGE_CACHE" ]] || return 0
    grep -F "${id}|" "$STORAGE_CACHE" 2>/dev/null | tail -1 | awk -F'|' '{print $4}'
    return 0
}

_usage_tg_lines() {
    local lines="" du used total s3_num bytes
    du=$(_disk_usage)
    if [[ -n "$du" ]]; then
        read -r used total <<< "$du"
        lines+=$'\n'"• *$(t usage_disk):* $(_usage_text "$used" "$total")"
    fi
    if [[ "$UPLOAD_METHOD" == "s3" ]]; then
        while IFS= read -r s3_num; do
            bytes=$(_s3_measure_usage "$s3_num" 2>/dev/null) || bytes=""
            [[ -n "$bytes" ]] || continue
            lines+=$'\n'"• *$(_s3_label "$s3_num"):* $(_usage_text "$bytes" "$(_s3_limit_bytes "$s3_num")")"
        done < <(_s3_configured_nums)
    fi
    printf '%s' "$lines"
}

send_s3_document() {
    local file_path="$1"
    local s3_num="$2"
    local file_name=$(basename "$file_path")

    local s3_bucket=$(_s3_var BUCKET "$s3_num")
    local s3_endpoint=$(_s3_var ENDPOINT "$s3_num")
    local s3_access=$(_s3_var ACCESS_KEY "$s3_num")
    local s3_secret=$(_s3_var SECRET_KEY "$s3_num")
    local s3_region=$(_s3_var REGION "$s3_num")
    local s3_prefix=$(_s3_var PREFIX "$s3_num")
    local s3_label=$(_s3_label "$s3_num")

    if ! command -v aws &> /dev/null; then
        print_message "ERROR" "$(t s3_aws_not_found)"
        return 1
    fi
    local s3_endpoint_arg=""
    if [[ -n "$s3_endpoint" ]]; then
        s3_endpoint_arg="--endpoint-url $s3_endpoint"
    fi
    local s3_key="${s3_prefix:+${s3_prefix}/}${file_name}"
    AWS_ACCESS_KEY_ID="$s3_access" \
    AWS_SECRET_ACCESS_KEY="$s3_secret" \
    AWS_DEFAULT_REGION="$s3_region" \
    aws s3 ls "s3://${s3_bucket}/" \
    $s3_endpoint_arg >/dev/null 2>&1 || true

    local s3_upload_output
    if s3_upload_output=$(AWS_ACCESS_KEY_ID="$s3_access" \
         AWS_SECRET_ACCESS_KEY="$s3_secret" \
         AWS_DEFAULT_REGION="$s3_region" \
         aws s3 cp "$file_path" "s3://${s3_bucket}/${s3_key}" \
         $s3_endpoint_arg --quiet 2>&1); then
        print_message "SUCCESS" "$(t s3_upload_ok) (${s3_label})"
        return 0
    fi

    print_message "ERROR" "$(t s3_upload_err) (${s3_label})"
    _s3_print_diagnosis "$s3_upload_output" "$s3_bucket" "$s3_region" "$s3_endpoint"
    return 1
}

cleanup_s3_old_backups() {
    local s3_num="$1"

    local s3_bucket=$(_s3_var BUCKET "$s3_num")
    local s3_endpoint=$(_s3_var ENDPOINT "$s3_num")
    local s3_access=$(_s3_var ACCESS_KEY "$s3_num")
    local s3_secret=$(_s3_var SECRET_KEY "$s3_num")
    local s3_region=$(_s3_var REGION "$s3_num")
    local s3_prefix=$(_s3_var PREFIX "$s3_num")
    local s3_retain=$(_s3_var RETAIN_DAYS "$s3_num")
    local s3_label=$(_s3_label "$s3_num")
    s3_retain="${s3_retain:-30}"

    if [[ -z "$s3_bucket" || -z "$s3_access" || -z "$s3_secret" ]]; then
        return 0
    fi
    if [[ "$s3_retain" -le 0 ]]; then
        return 0
    fi

    local s3_endpoint_arg=""
    if [[ -n "$s3_endpoint" ]]; then
        s3_endpoint_arg="--endpoint-url $s3_endpoint"
    fi

    local s3_prefix_arg="${s3_prefix:+${s3_prefix}/}"
    local cutoff_date=$(date -d "-${s3_retain} days" +%Y-%m-%d 2>/dev/null || date -v-${s3_retain}d +%Y-%m-%d 2>/dev/null)

    if [[ -z "$cutoff_date" ]]; then
        return 0
    fi

    local file_list
    file_list=$(AWS_ACCESS_KEY_ID="$s3_access" \
                AWS_SECRET_ACCESS_KEY="$s3_secret" \
                AWS_DEFAULT_REGION="$s3_region" \
                aws s3 ls "s3://${s3_bucket}/${s3_prefix_arg}" \
                $s3_endpoint_arg 2>/dev/null | grep "remnawave_backup_.*\.tar\.gz")

    if [[ -z "$file_list" ]]; then
        return 0
    fi

    local deleted_count=0
    while IFS= read -r line; do
        local file_date=$(echo "$line" | awk '{print $1}')
        local file_name=$(echo "$line" | awk '{print $NF}')
        if [[ "$file_date" < "$cutoff_date" ]]; then
            if AWS_ACCESS_KEY_ID="$s3_access" \
               AWS_SECRET_ACCESS_KEY="$s3_secret" \
               AWS_DEFAULT_REGION="$s3_region" \
               aws s3 rm "s3://${s3_bucket}/${s3_prefix_arg}${file_name}" \
               $s3_endpoint_arg --quiet 2>/dev/null; then
                ((deleted_count++)) || true
            fi
        fi
    done <<< "$file_list"

    if [[ $deleted_count -gt 0 ]]; then
        print_message "INFO" "$(printf "$(t s3_cleaned)" "$deleted_count") (${s3_label})"
    fi
}

_s3_print_diagnosis() {
    local output="$1"
    local s3_bucket="$2"
    local s3_region="$3"
    local s3_endpoint="$4"

    log_write "ERROR" "S3 ${s3_bucket} ${s3_endpoint}: $(printf '%s' "$output" | head -n 5)"
    echo -e "${RED}──────────────────────────────────${RESET}"
    if echo "$output" | grep -q "SignatureDoesNotMatch"; then
        echo -e "${RED}Invalid secret key${RESET}"
        echo -e "${YELLOW}Details: ${output}${RESET}"
        echo -e "${GREEN}Hint: Secret key is incorrect. Check and re-enter it${RESET}"
    elif echo "$output" | grep -q "Unauthorized"; then
        echo -e "${RED}Unauthorized — secret key is incorrect${RESET}"
        echo -e "${YELLOW}Details: ${output}${RESET}"
        echo -e "${GREEN}Hint: Secret key is incorrect. Check and re-enter it${RESET}"
    elif echo "$output" | grep -q "InvalidArgument"; then
        echo -e "${RED}Invalid access key format${RESET}"
        echo -e "${YELLOW}Details: ${output}${RESET}"
        echo -e "${GREEN}Hint: Access key length or format is incorrect${RESET}"
    elif echo "$output" | grep -q "InvalidAccessKeyId"; then
        echo -e "${RED}Invalid access key${RESET}"
        echo -e "${YELLOW}Details: ${output}${RESET}"
        echo -e "${GREEN}Hint: Access key does not exist. Check and re-enter it${RESET}"
    elif echo "$output" | grep -q "AccessDenied"; then
        echo -e "${RED}Access denied — key has no permission for this operation${RESET}"
        echo -e "${YELLOW}Details: ${output}${RESET}"
        echo -e "${GREEN}Hint: Check S3 access key permissions (PutObject/ListObjects may differ — a key that can list a bucket may still lack write/upload rights)${RESET}"
    elif echo "$output" | grep -q "NoSuchBucket"; then
        echo -e "${RED}Bucket not found${RESET}"
        echo -e "${YELLOW}Details: ${output}${RESET}"
        echo -e "${GREEN}Hint: Bucket '${s3_bucket}' does not exist. Check bucket name${RESET}"
    elif echo "$output" | grep -q "InvalidRegionName"; then
        echo -e "${RED}Invalid region name${RESET}"
        echo -e "${YELLOW}Details: ${output}${RESET}"
        echo -e "${GREEN}Hint: Region '${s3_region}' is not valid. Check available regions for your S3 provider${RESET}"
    elif echo "$output" | grep -q "SSL\|CERTIFICATE\|HANDSHAKE"; then
        echo -e "${RED}SSL error — certificate is untrusted, expired or handshake failed${RESET}"
        echo -e "${YELLOW}Details: ${output}${RESET}"
        echo -e "${GREEN}Hint: Contact your S3 provider. The endpoint may use a self-signed certificate${RESET}"
    elif echo "$output" | grep -q "Could not connect\|ConnectionError\|EndpointResolutionError"; then
        echo -e "${RED}Cannot reach S3 endpoint${RESET}"
        echo -e "${YELLOW}Details: ${output}${RESET}"
        echo -e "${GREEN}Hint: Check endpoint URL '${s3_endpoint}' and network connectivity${RESET}"
    elif [[ -z "$output" ]]; then
        echo -e "${RED}No error output returned by aws-cli${RESET}"
        echo -e "${GREEN}Hint: Check free disk space, file permissions, and that the bucket policy allows PutObject for this key${RESET}"
    else
        echo -e "${RED}Unknown error${RESET}"
        echo -e "${YELLOW}Details: ${output}${RESET}"
        echo -e "${GREEN}Hint: Check all S3 parameters and try again${RESET}"
    fi
    echo -e "${RED}──────────────────────────────────${RESET}"
}

test_s3_connection() {
    local s3_num="$1"

    local s3_bucket=$(_s3_var BUCKET "$s3_num")
    local s3_endpoint=$(_s3_var ENDPOINT "$s3_num")
    local s3_access=$(_s3_var ACCESS_KEY "$s3_num")
    local s3_secret=$(_s3_var SECRET_KEY "$s3_num")
    local s3_region=$(_s3_var REGION "$s3_num")
    local s3_prefix=$(_s3_var PREFIX "$s3_num")
    local s3_label=$(_s3_label "$s3_num")

    if [[ -z "$s3_bucket" || -z "$s3_access" || -z "$s3_secret" ]]; then
        print_message "ERROR" "$(t st_s3_test_missing) (${s3_label})"
        return 1
    fi

    print_message "INFO" "$(t st_s3_testing) (${s3_label})"
    install_aws_cli || return 1

    local s3_test_endpoint=""
    if [[ -n "$s3_endpoint" ]]; then
        s3_test_endpoint="--endpoint-url $s3_endpoint"
    fi
    local test_prefix="${s3_prefix:+${s3_prefix}/}"
    local s3_test_output
    if s3_test_output=$(AWS_ACCESS_KEY_ID="$s3_access" \
       AWS_SECRET_ACCESS_KEY="$s3_secret" \
       AWS_DEFAULT_REGION="$s3_region" \
       aws s3 ls "s3://${s3_bucket}/${test_prefix}" \
       $s3_test_endpoint 2>&1); then
        print_message "SUCCESS" "$(t st_s3_test_ok) (${s3_label})"
        return 0
    fi

    print_message "ERROR" "$(t st_s3_test_fail) (${s3_label})"
    _s3_print_diagnosis "$s3_test_output" "$s3_bucket" "$s3_region" "$s3_endpoint"
    return 1
}

_s3_shift_down() {
    local from_num="$1"
    local fields=(NAME ENDPOINT REGION BUCKET ACCESS_KEY SECRET_KEY PREFIX RETAIN_DAYS LIMIT_GB)
    local i field value
    for ((i=from_num; i<S3_COUNT; i++)); do
        for field in "${fields[@]}"; do
            value=$(_s3_var "$field" "$((i+1))")
            _s3_set "$field" "$i" "$value"
        done
    done
    local last=$S3_COUNT
    for field in "${fields[@]}"; do
        _s3_set "$field" "$last" ""
    done
}

s3_target_menu() {
    local s3_num="$1"
    while true; do
        clear
        local s3_lbl=$(_s3_label "$s3_num")
        local s3_name=$(_s3_var NAME "$s3_num")
        local s3_endpoint=$(_s3_var ENDPOINT "$s3_num")
        local s3_region=$(_s3_var REGION "$s3_num")
        local s3_bucket=$(_s3_var BUCKET "$s3_num")
        local s3_access=$(_s3_var ACCESS_KEY "$s3_num")
        local s3_secret=$(_s3_var SECRET_KEY "$s3_num")
        local s3_prefix=$(_s3_var PREFIX "$s3_num")
        local s3_retain=$(_s3_var RETAIN_DAYS "$s3_num")
        s3_retain="${s3_retain:-30}"
        local is_primary="false"
        [[ -z "$s3_num" || "$s3_num" == "1" ]] && is_primary="true"

        echo -e "${GREEN}${BOLD}$(t st_s3_title) — ${s3_lbl}${RESET}"
        echo ""
        print_message "INFO" "$(t st_s3_name) ${BOLD}${s3_name:-$(t not_set)}${RESET}"
        print_message "INFO" "$(t st_s3_endpoint) ${BOLD}${s3_endpoint:-$(t not_set)}${RESET}"
        print_message "INFO" "$(t st_s3_region) ${BOLD}${s3_region:-$(t not_set)}${RESET}"
        print_message "INFO" "$(t st_s3_bucket) ${BOLD}${s3_bucket:-$(t not_set)}${RESET}"
        print_message "INFO" "$(t st_s3_access) ${BOLD}${s3_access:+****${s3_access: -4}}${RESET}"
        print_message "INFO" "$(t st_s3_secret) ${BOLD}${s3_secret:+****}${RESET}"
        print_message "INFO" "$(t st_s3_prefix) ${BOLD}${s3_prefix:-$(t root_folder)}${RESET}"
        print_message "INFO" "$(t st_retention_s3) ${BOLD}$(_retention_display "$s3_retain" "$(t st_retention_days)")${RESET}"
        local s3_limit_gb s3_used_cached
        s3_limit_gb=$(_s3_var LIMIT_GB "$s3_num")
        if [[ "$s3_limit_gb" =~ ^[0-9]+$ && "$s3_limit_gb" -gt 0 ]]; then
            print_message "INFO" "$(t st_s3_limit) ${BOLD}${s3_limit_gb} $(t gb_unit)${RESET}"
        else
            print_message "INFO" "$(t st_s3_limit) ${BOLD}$(t st_s3_limit_none)${RESET}"
        fi
        s3_used_cached=$(_s3_cached_usage "$s3_num")
        if [[ -n "$s3_used_cached" ]]; then
            print_message "INFO" "$(t st_s3_used) ${BOLD}$(_usage_text "$s3_used_cached" "$(_s3_limit_bytes "$s3_num")")${RESET}"
        fi
        echo ""
        ui_menu_reset
        ui_menu_add 1 "$(t st_s3_change_name)"
        ui_menu_add 2 "$(t st_s3_change_endpoint)"
        ui_menu_add 3 "$(t st_s3_change_region)"
        ui_menu_add 4 "$(t st_s3_change_bucket)"
        ui_menu_add 5 "$(t st_s3_change_access)"
        ui_menu_add 6 "$(t st_s3_change_secret)"
        ui_menu_add 7 "$(t st_s3_change_prefix)"
        ui_menu_add 8 "$(t st_retention_change_s3)"
        ui_menu_add 9 "$(t st_s3_change_limit)"
        ui_menu_add 10 "$(t st_s3_test)"
        if [[ "$is_primary" == "false" ]]; then
            ui_menu_gap
            ui_menu_add D "$(t st_s3_remove)" danger
        fi
        ui_menu_gap
        ui_menu_add 0 "$(t back)"
        ui_menu_choose s3t_choice
        echo ""

        case "$s3t_choice" in
            1)
                ui_input new_val "$(t st_s3_enter_name)"
                _s3_set NAME "$s3_num" "$new_val"
                save_config
                print_message "SUCCESS" "$(t st_s3_name_ok)"
                ;;
            2)
                ui_input new_val "$(t st_s3_enter_endpoint)" "https://s3.example.com"
                _s3_set ENDPOINT "$s3_num" "$new_val"
                save_config
                print_message "SUCCESS" "$(t st_s3_endpoint_ok)"
                ;;
            3)
                ui_input new_val "$(t st_s3_enter_region)"
                _s3_set REGION "$s3_num" "${new_val:-us-east-1}"
                save_config
                print_message "SUCCESS" "$(t st_s3_region_ok)"
                ;;
            4)
                ui_input new_val "$(t st_s3_enter_bucket)" "rw-backups"
                _s3_set BUCKET "$s3_num" "$new_val"
                save_config
                print_message "SUCCESS" "$(t st_s3_bucket_ok)"
                ;;
            5)
                ui_input new_val "$(t st_s3_enter_access)"
                _s3_set ACCESS_KEY "$s3_num" "$new_val"
                save_config
                print_message "SUCCESS" "$(t st_s3_access_ok)"
                ;;
            6)
                ui_input new_val "$(t st_s3_enter_secret)"
                _s3_set SECRET_KEY "$s3_num" "$new_val"
                save_config
                print_message "SUCCESS" "$(t st_s3_secret_ok)"
                ;;
            7)
                echo "   $(t ul_s3_prefix_info1)"
                echo "   $(t ul_s3_prefix_info2)"
                ui_input new_val "$(t st_s3_enter_prefix)" "server-1"
                _s3_set PREFIX "$s3_num" "$new_val"
                save_config
                print_message "SUCCESS" "$(t st_s3_prefix_ok)"
                ;;
            8)
                echo "   $(t st_retention_disable_hint)"
                ui_input new_val "$(printf "$(t st_retention_enter_s3)" "$s3_retain")"
                _s3_set RETAIN_DAYS "$s3_num" "${new_val:-$s3_retain}"
                save_config
                print_message "SUCCESS" "$(t st_retention_s3_ok)"
                ;;
            9)
                echo -e "   ${LIGHT_GRAY}$(t st_s3_limit_hint)${RESET}"
                local cur_limit
                cur_limit=$(_s3_var LIMIT_GB "$s3_num")
                [[ "$cur_limit" =~ ^[0-9]+$ && "$cur_limit" -gt 0 ]] || cur_limit="$(t st_s3_limit_none)"
                ui_input new_val "$(printf "$(t st_s3_limit_enter)" "$cur_limit")" "100"
                if [[ -z "$new_val" ]]; then
                    :
                elif [[ "$new_val" =~ ^[0-9]+$ ]]; then
                    if [[ "$new_val" -eq 0 ]]; then
                        _s3_set LIMIT_GB "$s3_num" ""
                    else
                        _s3_set LIMIT_GB "$s3_num" "$new_val"
                    fi
                    save_config
                    print_message "SUCCESS" "$(t st_s3_limit_ok)"
                    ui_spin_start "$(t st_s3_measuring)"
                    local measured_now
                    if measured_now=$(_s3_measure_usage "$s3_num"); then
                        print_message "INFO" "$(t st_s3_used) ${BOLD}$(_usage_text "$measured_now" "$(_s3_limit_bytes "$s3_num")")${RESET}"
                    else
                        print_message "WARN" "$(t st_s3_measure_fail)"
                    fi
                else
                    print_message "ERROR" "$(t st_s3_limit_bad)"
                fi
                ;;
            10)
                if test_s3_connection "$s3_num"; then
                    local measured
                    if measured=$(_s3_measure_usage "$s3_num"); then
                        print_message "INFO" "$(t st_s3_used) ${BOLD}$(_usage_text "$measured" "$(_s3_limit_bytes "$s3_num")")${RESET}"
                    fi
                fi
                ;;
            [Dd])
                if [[ "$is_primary" == "true" ]]; then
                    print_message "ERROR" "$(t invalid_input_select)"
                else
                    ui_confirm rm_confirm "$(t st_s3_remove_confirm)"
                    echo ""
                    if [[ "$rm_confirm" =~ ^[Yy]$ ]]; then
                        _s3_shift_down "$s3_num"
                        S3_COUNT=$((S3_COUNT - 1))
                        save_config
                        print_message "SUCCESS" "$(t st_s3_removed)"
                        read -rp "$(t press_enter)"
                        return
                    fi
                fi
                ;;
            0) return ;;
            *) print_message "ERROR" "$(t invalid_input_select)" ;;
        esac
        echo ""
        read -rp "$(t press_enter)"
    done
}

s3_settings_menu() {
    while true; do
        clear
        echo -e "${GREEN}${BOLD}$(t st_s3_title)${RESET}"
        echo ""
        local idx=0
        local s3_num
        ui_menu_reset
        while IFS= read -r s3_num; do
            idx=$((idx + 1))
            local lbl=$(_s3_label "$s3_num")
            local bucket=$(_s3_var BUCKET "$s3_num")
            ui_menu_add "$idx" "${lbl} — ${bucket:-$(t not_set)}"
        done < <(_s3_configured_nums)
        ui_menu_gap
        if [[ "${S3_COUNT:-1}" -lt 5 ]]; then
            ui_menu_add A "$(t st_s3_add_new)" primary
        fi
        ui_menu_add 0 "$(t back)"
        ui_menu_choose s3m_choice
        echo ""

        case "$s3m_choice" in
            [Aa])
                if [[ "${S3_COUNT:-1}" -ge 5 ]]; then
                    print_message "ERROR" "$(t st_s3_max_reached)"
                    echo ""
                    read -rp "$(t press_enter)"
                else
                    S3_COUNT=$((${S3_COUNT:-1} + 1))
                    save_config
                    s3_target_menu "$S3_COUNT"
                fi
                ;;
            0) break ;;
            ''|*[!0-9]*)
                print_message "ERROR" "$(t invalid_input_select)"
                echo ""
                read -rp "$(t press_enter)"
                ;;
            *)
                if [[ "$s3m_choice" -ge 1 && "$s3m_choice" -le "${S3_COUNT:-1}" ]]; then
                    local target_num="$s3m_choice"
                    [[ "$target_num" == "1" ]] && target_num=""
                    s3_target_menu "$target_num"
                else
                    print_message "ERROR" "$(t invalid_input_select)"
                    echo ""
                    read -rp "$(t press_enter)"
                fi
                ;;
        esac
    done
}

AGE_VERSION="v1.2.1"

install_age() {
    if command -v age &>/dev/null && command -v age-keygen &>/dev/null; then
        return 0
    fi
    print_message "INFO" "$(t enc_installing)"
    if command -v apt-get &>/dev/null; then
        apt-get update -qq > /dev/null 2>&1 || true
        apt-get install -y age > /dev/null 2>&1 || true
    fi
    if command -v age &>/dev/null && command -v age-keygen &>/dev/null; then
        return 0
    fi

    local arch
    case "$(uname -m)" in
        x86_64|amd64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) return 1 ;;
    esac
    local tmp_dir
    tmp_dir=$(mktemp -d)
    if curl -fsSL "https://github.com/FiloSottile/age/releases/download/${AGE_VERSION}/age-${AGE_VERSION}-linux-${arch}.tar.gz" -o "$tmp_dir/age.tgz" \
        && tar -xzf "$tmp_dir/age.tgz" -C "$tmp_dir" \
        && install -m 755 "$tmp_dir/age/age" /usr/local/bin/age \
        && install -m 755 "$tmp_dir/age/age-keygen" /usr/local/bin/age-keygen; then
        rm -rf "$tmp_dir"
        return 0
    fi
    rm -rf "$tmp_dir"
    return 1
}

prompt_age_private_key() {
    AGE_PRIVATE_KEY=""
    local key_input attempts=0
    while (( attempts < 3 )); do
        ui_secret key_input "$(t enc_enter_private)"
        key_input="${key_input//[[:space:]]/}"
        [[ -z "$key_input" ]] && return 1
        if [[ "$key_input" =~ ^AGE-SECRET-KEY-1[A-Z0-9]+$ ]]; then
            AGE_PRIVATE_KEY="$key_input"
            return 0
        fi
        print_message "ERROR" "$(t enc_bad_private)"
        attempts=$((attempts + 1))
    done
    return 1
}

_age_public_from_private() {
    age-keygen -y 2>/dev/null
}

_age_roundtrip_test() {
    local pub="$1" priv="$2"
    local sample="rw-backup-test-$$"
    local out
    out=$(printf '%s' "$sample" | age -r "$pub" 2>/dev/null | age -d -i <(printf '%s\n' "$priv") 2>/dev/null) || return 1
    [[ "$out" == "$sample" ]]
}

configure_encryption() {
    while true; do
        clear
        echo -e "${GREEN}${BOLD}$(t enc_title)${RESET}"
        echo ""
        if [[ "$ENCRYPT_ENABLED" == "true" && -n "$ENCRYPT_PUBLIC_KEY" ]]; then
            print_message "INFO" "$(t enc_status) ${BOLD}${GREEN}$(t enc_on)${RESET}"
            print_message "INFO" "$(t enc_pubkey) ${BOLD}${ENCRYPT_PUBLIC_KEY}${RESET}"
        else
            print_message "INFO" "$(t enc_status) ${BOLD}${RED}$(t enc_off)${RESET}"
        fi
        echo ""
        print_message "INFO" "$(t enc_info1)"
        print_message "INFO" "$(t enc_info2)"
        echo ""
        ui_menu_reset
        ui_menu_add 1 "$(t enc_use_existing)"
        ui_menu_add 2 "$(t enc_generate_new)"
        if [[ "$ENCRYPT_ENABLED" == "true" ]]; then
            ui_menu_add 3 "$(t enc_disable)" danger
        fi
        ui_menu_gap
        ui_menu_add 0 "$(t back)"
        local enc_choice
        ui_menu_choose enc_choice
        echo ""
        case "$enc_choice" in
            1) _encryption_use_existing_key ;;
            2) _encryption_generate_keys ;;
            3)
                if [[ "$ENCRYPT_ENABLED" == "true" ]]; then
                    print_message "WARN" "$(t enc_disable_warn)"
                    local enc_confirm
                    ui_confirm enc_confirm "$(t enc_disable_confirm)"
                    if [[ "$enc_confirm" =~ ^[YyДд]$ ]]; then
                        ENCRYPT_ENABLED="false"
                        save_config
                        print_message "SUCCESS" "$(t enc_disabled_ok)"
                    fi
                    echo ""
                    read -rp "$(t press_enter)"
                else
                    print_message "ERROR" "$(t invalid_input_select)"
                    read -rp "$(t press_enter)"
                fi
                ;;
            0) return ;;
            *) print_message "ERROR" "$(t invalid_input_select)"; read -rp "$(t press_enter)" ;;
        esac
    done
}

offer_enable_encryption_after_restore() {
    [[ -n "$RESTORE_AGE_PUBLIC" && "$ENCRYPT_ENABLED" != "true" ]] || return 0
    echo ""
    print_message "INFO" "$(t enc_offer_info)"
    local offer_ok
    ui_confirm offer_ok "$(t enc_offer_confirm)"
    if [[ "$offer_ok" =~ ^[YyДд]$ ]]; then
        ENCRYPT_PUBLIC_KEY="$RESTORE_AGE_PUBLIC"
        ENCRYPT_ENABLED="true"
        save_config
        print_message "SUCCESS" "$(t enc_enabled_ok)"
    fi
    RESTORE_AGE_PUBLIC=""
    return 0
}

_encryption_use_existing_key() {
    if ! install_age; then
        print_message "ERROR" "$(t enc_install_fail)"
        read -rp "$(t press_enter)"
        return
    fi
    print_message "INFO" "$(t enc_existing_info)"
    echo -e "   ${GRAY}$(t enc_existing_pub)${RESET}"
    echo -e "   ${GRAY}$(t enc_existing_priv)${RESET}"
    echo -e "   ${GRAY}$(t enc_existing_note)${RESET}"
    echo ""
    local key_input pub=""
    ui_secret key_input "$(t enc_enter_existing)"
    key_input="${key_input//[[:space:]]/}"

    if [[ "$key_input" =~ ^age1[a-z0-9]{58}$ ]]; then
        if printf 'test' | age -r "$key_input" > /dev/null 2>&1; then
            pub="$key_input"
        fi
    elif [[ "$key_input" =~ ^AGE-SECRET-KEY-1[A-Z0-9]+$ ]]; then
        pub=$(printf '%s\n' "$key_input" | _age_public_from_private)
        if [[ ! "$pub" =~ ^age1[a-z0-9]{58}$ ]] || ! _age_roundtrip_test "$pub" "$key_input"; then
            pub=""
        fi
    fi
    key_input=""

    if [[ -z "$pub" ]]; then
        print_message "ERROR" "$(t enc_bad_existing)"
        read -rp "$(t press_enter)"
        return
    fi
    ENCRYPT_PUBLIC_KEY="$pub"
    ENCRYPT_ENABLED="true"
    save_config
    print_message "SUCCESS" "$(t enc_enabled_ok)"
    print_message "INFO" "$(t enc_pubkey) ${BOLD}${pub}${RESET}"
    echo ""
    read -rp "$(t press_enter)"
}

_encryption_generate_keys() {
    if ! install_age; then
        print_message "ERROR" "$(t enc_install_fail)"
        read -rp "$(t press_enter)"
        return
    fi
    print_message "WARN" "$(t enc_new_keys_warn)"
    local enc_ok
    ui_confirm enc_ok "$(t enc_continue_confirm)"
    [[ "$enc_ok" =~ ^[YyДд]$ ]] || return

    local priv pub
    priv=$(age-keygen 2>/dev/null | grep '^AGE-SECRET-KEY-' || true)
    pub=$(printf '%s\n' "$priv" | _age_public_from_private)
    if [[ -z "$priv" || -z "$pub" ]] || ! _age_roundtrip_test "$pub" "$priv"; then
        print_message "ERROR" "$(t enc_gen_fail)"
        read -rp "$(t press_enter)"
        return
    fi

    clear
    echo -e "${RED}${BOLD}$(t enc_warn_title)${RESET}"
    echo ""
    echo -e "${YELLOW}$(t enc_warn1)${RESET}"
    echo -e "${YELLOW}$(t enc_warn2)${RESET}"
    echo -e "${YELLOW}$(t enc_warn3)${RESET}"
    echo ""
    echo -e "${GREEN}${BOLD}$(t enc_private_label)${RESET}"
    echo -e "${BOLD}${priv}${RESET}"
    echo ""
    echo -e "${GRAY}$(t enc_public_label) ${pub}${RESET}"
    echo ""

    local confirmed=false attempts=0 check
    while (( attempts < 3 )); do
        ui_secret check "$(t enc_retype_private)"
        check="${check//[[:space:]]/}"
        if [[ "$check" == "$priv" ]]; then
            confirmed=true
            break
        fi
        print_message "ERROR" "$(t enc_retype_mismatch)"
        attempts=$((attempts + 1))
    done

    if [[ "$confirmed" != "true" ]]; then
        unset priv check
        print_message "WARN" "$(t enc_not_enabled)"
        read -rp "$(t press_enter)"
        return
    fi

    ENCRYPT_PUBLIC_KEY="$pub"
    ENCRYPT_ENABLED="true"
    save_config
    unset priv check
    clear
    print_message "SUCCESS" "$(t enc_enabled_ok)"
    print_message "INFO" "$(t enc_clear_hint)"
    echo ""
    read -rp "$(t press_enter)"
}

create_backup() {
    LOG_CATEGORY="backup"
    log_write "INFO" "=== backup started (v${VERSION}) ==="
    print_message "INFO" "$(t bk_starting)"
    echo ""
    
    if [[ "$DB_CONNECTION_TYPE" == "external" ]]; then
        print_message "INFO" "$(t bk_mode_ext) (${DB_HOST}:${DB_PORT}/${DB_NAME})"
    else
        print_message "INFO" "$(t bk_mode_docker)"
    fi
    echo ""
    
    REMNAWAVE_VERSION=$(get_remnawave_version)
    TIMESTAMP=$(date +%Y-%m-%d"_"%H_%M_%S)
    BACKUP_FILE_DB="dump_${TIMESTAMP}.sql.gz"

    local backup_scope_tag="full"
    if [[ "$SKIP_PANEL_BACKUP" == "true" && "$BOT_BACKUP_ENABLED" == "true" ]]; then
        backup_scope_tag="bot"
    elif [[ "$SKIP_PANEL_BACKUP" != "true" && "$BOT_BACKUP_ENABLED" != "true" ]]; then
        backup_scope_tag="panel"
    fi
    BACKUP_FILE_FINAL="remnawave_backup_${backup_scope_tag}_${TIMESTAMP}.tar.gz"
    
    mkdir -p "$BACKUP_DIR" || { 
        echo -e "${RED}❌ $(t bk_mkdir_err) ${BOLD}$BACKUP_DIR${RESET}.${RESET}"
        send_telegram_message "❌ $(t bk_mkdir_err) ${BOLD}$BACKUP_DIR${RESET}." "None"
        exit 1
    }
    
    BACKUP_ITEMS=()
    
    if [[ "$SKIP_PANEL_BACKUP" == "true" ]]; then
        print_message "INFO" "$(t bk_skip_panel)"
    else
        ui_spin_start "$(t bk_creating_dump)"
        if ! create_panel_db_dump "$BACKUP_DIR/$BACKUP_FILE_DB"; then
            local STATUS=$?
            ui_spin_stop
            echo -e "${RED}❌ $(t bk_dump_err) ${BOLD}$STATUS${RESET}. $(t bk_check_db)${RESET}"
            local error_msg="❌ $(t bk_dump_err) ${STATUS}"
            if [[ -n "$LAST_DB_ERROR" ]]; then
                error_msg+="${LAST_DB_ERROR}"
            fi
            if [[ "$UPLOAD_METHOD" == "telegram" ]]; then
                send_telegram_message "$error_msg" "None"
            fi
            exit $STATUS
        fi
        
        print_message "SUCCESS" "$(t bk_dump_ok)"
        echo ""
        
        print_message "INFO" "$(t bk_archiving)"
        REMNAWAVE_DIR_ARCHIVE="remnawave_dir_${TIMESTAMP}.tar.gz"
        
        if [ -d "$REMNALABS_ROOT_DIR" ]; then
            ui_spin_start "$(t bk_arch_dir) ${BOLD}${REMNALABS_ROOT_DIR}${RESET}..."
            
            local exclude_args=""
            for pattern in $BACKUP_EXCLUDE_PATTERNS; do
                exclude_args+="--exclude=$pattern "
            done
            
            eval "tar --warning=no-file-changed -czf '$BACKUP_DIR/$REMNAWAVE_DIR_ARCHIVE' $exclude_args -C '$(dirname "$REMNALABS_ROOT_DIR")' '$(basename "$REMNALABS_ROOT_DIR")'" || true
            local rw_tar_exit=${PIPESTATUS[0]}
            if [[ $rw_tar_exit -lt 2 ]]; then
                print_message "SUCCESS" "$(t bk_arch_ok)"
                BACKUP_ITEMS=("$BACKUP_FILE_DB" "$REMNAWAVE_DIR_ARCHIVE")
            else
                local STATUS=$rw_tar_exit
                echo -e "${RED}❌ $(t bk_arch_err) ${BOLD}$STATUS${RESET}.${RESET}"
                local error_msg="❌ $(t bk_arch_err) ${BOLD}${STATUS}${RESET}"
                if [[ "$UPLOAD_METHOD" == "telegram" ]]; then
                    send_telegram_message "$error_msg" "None"
                fi
                exit $STATUS
            fi
        else
            print_message "ERROR" "$(t bk_dir_missing) ${BOLD}${REMNALABS_ROOT_DIR}${RESET}"
            exit 1
        fi
    fi
    
    echo ""
    
    META_BOT_VERSION=""
    create_bot_backup
    
    if [[ ${#BACKUP_ITEMS[@]} -eq 0 ]]; then
        print_message "ERROR" "$(t bk_no_data)"
        exit 1
    fi
    
    local DUMP_TYPE
    if [[ "$DB_CONNECTION_TYPE" == "docker" ]]; then
        DUMP_TYPE="dumpall"
    else
        DUMP_TYPE="dump"
    fi
    
    cat > "$BACKUP_DIR/backup_meta.info" <<METAEOF
DUMP_TYPE="$DUMP_TYPE"
DB_CONNECTION_TYPE="$DB_CONNECTION_TYPE"
DB_NAME="$DB_NAME"
BACKUP_VERSION="$VERSION"
PANEL_VERSION="$REMNAWAVE_VERSION"
TIMESTAMP="$TIMESTAMP"
BOT_META_VERSION="$META_BOT_VERSION"
METAEOF
    BACKUP_ITEMS+=("backup_meta.info")
    
    ui_spin_start "$(t bk_packing)"
    if ! tar -czf "$BACKUP_DIR/$BACKUP_FILE_FINAL" -C "$BACKUP_DIR" "${BACKUP_ITEMS[@]}"; then
        STATUS=$?
        ui_spin_stop
        echo -e "${RED}❌ $(t bk_final_err) ${BOLD}$STATUS${RESET}.${RESET}"
        local error_msg="❌ $(t bk_final_err) ${BOLD}${STATUS}${RESET}"
        if [[ "$UPLOAD_METHOD" == "telegram" ]]; then
            send_telegram_message "$error_msg" "None"
        fi
        exit $STATUS
    fi
    
    if [[ "$ENCRYPT_ENABLED" == "true" ]]; then
        ui_spin_start "$(t enc_encrypting)"
        local enc_fail=false
        if [[ -z "$ENCRYPT_PUBLIC_KEY" ]] || ! install_age; then
            enc_fail=true
        elif age -r "$ENCRYPT_PUBLIC_KEY" -o "$BACKUP_DIR/${BACKUP_FILE_FINAL}.age" "$BACKUP_DIR/$BACKUP_FILE_FINAL"; then
            rm -f "$BACKUP_DIR/$BACKUP_FILE_FINAL"
            BACKUP_FILE_FINAL="${BACKUP_FILE_FINAL}.age"
        else
            enc_fail=true
        fi
        if [[ "$enc_fail" == "true" ]]; then
            rm -f "$BACKUP_DIR/${BACKUP_FILE_FINAL}.age" "$BACKUP_DIR/$BACKUP_FILE_FINAL"
            for item in "${BACKUP_ITEMS[@]}"; do rm -f "$BACKUP_DIR/$item"; done
            print_message "ERROR" "$(t enc_failed)"
            if [[ "$UPLOAD_METHOD" == "telegram" ]]; then
                send_telegram_message "❌ $(t enc_failed)" "None"
            fi
            exit 1
        fi
        print_message "SUCCESS" "$(t enc_encrypted_ok)"
    fi

    print_message "SUCCESS" "$(t bk_final_ok) ${BOLD}${BACKUP_DIR}/${BACKUP_FILE_FINAL}${RESET}"
    echo ""
    
    print_message "INFO" "$(t bk_cleaning)"
    for item in "${BACKUP_ITEMS[@]}"; do
        rm -f "$BACKUP_DIR/$item"
    done
    print_message "SUCCESS" "$(t bk_cleaned)"
    echo ""
    
    ui_spin_start "$(t bk_sending) (${UPLOAD_METHOD})..."
    
    local DATE=$(date +'%Y-%m-%d %H:%M:%S')
    local backup_size=$(du -h "$BACKUP_DIR/$BACKUP_FILE_FINAL" | awk '{print $1}')
    
    local backup_info=""
    local db_mode_info=""
    if [[ "$SKIP_PANEL_BACKUP" == "true" ]]; then
        backup_info=$'\n'"• *$(t tg_bk_type)* $(t tg_only_bot)"
    else
        if [[ "$BOT_BACKUP_ENABLED" == "true" ]]; then
            backup_info=$'\n'"• *$(t tg_bk_type)* $(t tg_type_full)"
        else
            backup_info=$'\n'"• *$(t tg_bk_type)* $(t tg_only_panel)"
        fi
        local rw_ver_disp="$REMNAWAVE_VERSION"
        [[ "$rw_ver_disp" =~ ^[0-9] ]] && rw_ver_disp="v${rw_ver_disp}"
        backup_info+=$'\n'"• *Remnawave:* ${rw_ver_disp}"

        local rwp_bot_version=$(get_rwp_shop_version)
        if [[ -n "$rwp_bot_version" ]]; then
            backup_info+=$'\n'"• *$(t tg_bot_version)* v${rwp_bot_version}"
        fi

        if [[ "$DB_CONNECTION_TYPE" == "external" ]]; then
            db_mode_info=$'\n'"• *$(t tg_db_type)* $(t tg_db_ext) (${DB_HOST})"
        else
            db_mode_info=$'\n'"• *$(t tg_db_type)* $(t tg_db_docker)"
        fi
    fi

    local enc_info=""
    [[ "$ENCRYPT_ENABLED" == "true" ]] && enc_info=$'\n'"• *$(t tg_encryption)* $(t tg_enc_enabled)"
    local caption_text="🛠 *Backup & Restore* v${VERSION}"$'\n'"💾 #backup_success"$'\n'"➖➖➖➖➖➖➖➖➖"$'\n'"📨 *$(t tg_bk_success)*${backup_info}${db_mode_info}"$'\n'"• *$(t tg_size)* ${backup_size}"$'\n'"• *$(t tg_date)* ${DATE}${enc_info}"
    
    if [[ -f "$BACKUP_DIR/$BACKUP_FILE_FINAL" ]]; then
        if [[ "$UPLOAD_METHOD" == "telegram" ]]; then
            local file_size_bytes
            file_size_bytes=$(stat -c%s "$BACKUP_DIR/$BACKUP_FILE_FINAL" 2>/dev/null || stat -f%z "$BACKUP_DIR/$BACKUP_FILE_FINAL" 2>/dev/null || echo "0")
            local max_tg_size=$((50 * 1024 * 1024))
            if [[ "$file_size_bytes" -gt "$max_tg_size" ]]; then
                print_message "ERROR" "$(printf "$(t bk_tg_big)" "$backup_size")"
                print_message "INFO" "$(t bk_saved_local) ${BOLD}${BACKUP_DIR}/${BACKUP_FILE_FINAL}${RESET}"
                send_telegram_message "⚠️ $(printf "$(t bk_tg_big_notify)" "$backup_size")" "None" 2>/dev/null
            elif caption_text+="$(_usage_tg_lines)"; send_telegram_document "$BACKUP_DIR/$BACKUP_FILE_FINAL" "$caption_text" "$(donate_keyboard)"; then
                print_message "SUCCESS" "$(t bk_tg_ok)"
            else
                echo -e "${RED}❌ $(t bk_tg_err)${RESET}"
            fi
        elif [[ "$UPLOAD_METHOD" == "s3" ]]; then
            local s3_ok_labels=()
            local s3_fail_labels=()
            local s3_num
            while IFS= read -r s3_num; do
                local s3_chk_bucket=$(_s3_var BUCKET "$s3_num")
                local s3_chk_access=$(_s3_var ACCESS_KEY "$s3_num")
                local s3_chk_secret=$(_s3_var SECRET_KEY "$s3_num")
                if [[ -z "$s3_chk_bucket" || -z "$s3_chk_access" || -z "$s3_chk_secret" ]]; then
                    continue
                fi
                local s3_lbl=$(_s3_label "$s3_num")
                ui_spin_start "$(t bk_sending) (${s3_lbl})..."
                if send_s3_document "$BACKUP_DIR/$BACKUP_FILE_FINAL" "$s3_num"; then
                    s3_ok_labels+=("$s3_lbl")
                else
                    s3_fail_labels+=("$s3_lbl")
                fi
            done < <(_s3_configured_nums)

            if [[ ${#s3_ok_labels[@]} -gt 0 ]]; then
                print_message "SUCCESS" "$(t bk_s3_ok)"
                local tg_success_message="🛠 *Backup & Restore* v${VERSION}"$'\n'"💾 #backup_success"$'\n'"➖➖➖➖➖➖➖➖➖"$'\n'"☁️ *$(t tg_bk_s3)*${backup_info}${db_mode_info}"$'\n'"• *$(t tg_size)* ${backup_size}"$'\n'"• *$(t tg_date)* ${DATE}${enc_info}""$(_usage_tg_lines)"

                if [[ $(( ${#s3_ok_labels[@]} + ${#s3_fail_labels[@]} )) -gt 1 ]]; then
                    tg_success_message+=$'\n'$'\n'"*$(t bk_s3_targets)*"
                    local lbl
                    for lbl in "${s3_ok_labels[@]}"; do
                        tg_success_message+=$'\n'"✅ ${lbl}"
                    done
                    for lbl in "${s3_fail_labels[@]}"; do
                        tg_success_message+=$'\n'"❌ ${lbl}"
                    done
                fi

                if send_telegram_message "$tg_success_message" "MarkdownV2" "$(donate_keyboard)"; then
                    print_message "SUCCESS" "$(t bk_s3_notify_ok)"
                else
                    print_message "ERROR" "$(t bk_s3_notify_fail)"
                fi
            else
                echo -e "${RED}❌ $(t bk_s3_err)${RESET}"
                send_telegram_message "❌ $(t bk_s3_err_tg)" "None"
            fi
        else
            print_message "WARN" "$(t bk_unknown_method) ${BOLD}${UPLOAD_METHOD}${RESET}. $(t bk_not_sent)"
            send_telegram_message "❌ $(t bk_unknown_method) ${BOLD}${UPLOAD_METHOD}${RESET}" "None"
        fi
    else
        echo -e "${RED}❌ $(t bk_file_missing) ${BOLD}${BACKUP_DIR}/${BACKUP_FILE_FINAL}${RESET}. $(t bk_impossible)${RESET}"
        local error_msg="❌ $(t bk_file_missing) ${BOLD}${BACKUP_FILE_FINAL}${RESET}"
        if [[ "$UPLOAD_METHOD" == "telegram" ]]; then
            send_telegram_message "$error_msg" "None"

        elif [[ "$UPLOAD_METHOD" == "s3" ]]; then
            print_message "ERROR" "$(t bk_s3_impossible)"
        fi
        exit 1
    fi
    
    echo ""
    
    if [[ "${RETAIN_BACKUPS_VALUE:-0}" -le 0 ]]; then
        print_message "INFO" "$(t bk_retention_disabled)"
    else
        print_message "INFO" "$(printf "$(t bk_retention)" "$RETAIN_BACKUPS_VALUE")"
        if [[ "$RETAIN_BACKUPS_UNIT" == "hours" ]]; then
            find "$BACKUP_DIR" -maxdepth 1 \( -name "remnawave_backup_*.tar.gz" -o -name "remnawave_backup_*.tar.gz.age" \) -mmin +$((RETAIN_BACKUPS_VALUE * 60)) -delete
        else
            find "$BACKUP_DIR" -maxdepth 1 \( -name "remnawave_backup_*.tar.gz" -o -name "remnawave_backup_*.tar.gz.age" \) -mmin +$((RETAIN_BACKUPS_VALUE * 24 * 60)) -delete
        fi
        print_message "SUCCESS" "$(t bk_retention_ok)"
    fi
    
    if [[ "$UPLOAD_METHOD" == "s3" ]]; then
        local s3_ret_num
        while IFS= read -r s3_ret_num; do
            local s3_ret_chk_bucket=$(_s3_var BUCKET "$s3_ret_num")
            local s3_ret_chk_access=$(_s3_var ACCESS_KEY "$s3_ret_num")
            local s3_ret_chk_secret=$(_s3_var SECRET_KEY "$s3_ret_num")
            if [[ -z "$s3_ret_chk_bucket" || -z "$s3_ret_chk_access" || -z "$s3_ret_chk_secret" ]]; then
                continue
            fi
            local s3_ret_lbl=$(_s3_label "$s3_ret_num")
            local s3_ret_days=$(_s3_var RETAIN_DAYS "$s3_ret_num")
            s3_ret_days="${s3_ret_days:-30}"
            if [[ "$s3_ret_days" -le 0 ]]; then
                print_message "INFO" "$(t bk_retention_disabled) (${s3_ret_lbl})"
                continue
            fi
            print_message "INFO" "$(printf "$(t bk_s3_retention)" "$s3_ret_days") (${s3_ret_lbl})"
            cleanup_s3_old_backups "$s3_ret_num"
        done < <(_s3_configured_nums)
        print_message "SUCCESS" "$(t bk_s3_retention_ok)"
        local s3_usage_num
        while IFS= read -r s3_usage_num; do
            _s3_measure_usage "$s3_usage_num" >/dev/null 2>&1 || true
        done < <(_s3_configured_nums)
    fi
    
    echo ""
    
    {
        check_update_status >/dev/null 2>&1
        
        if [[ "$UPDATE_AVAILABLE" == true ]]; then
            local CURRENT_VERSION="$VERSION"
            local REMOTE_VERSION_LATEST
            REMOTE_VERSION_LATEST=$(curl -fsSL "$SCRIPT_REPO_URL" 2>/dev/null | grep -m 1 "^VERSION=" | cut -d'"' -f2)
            
            if [[ -n "$REMOTE_VERSION_LATEST" ]]; then
                if [[ "$AUTO_UPDATE" == "true" ]]; then
                    local TEMP_SCRIPT_PATH="${INSTALL_DIR}/backup-restore.sh.tmp"
                    if curl -fsSL "$SCRIPT_REPO_URL" -o "$TEMP_SCRIPT_PATH" 2>/dev/null; then
                        if [[ -s "$TEMP_SCRIPT_PATH" ]] && head -n 1 "$TEMP_SCRIPT_PATH" | grep -q -e '^#!.*bash'; then
                            find "$(dirname "$SCRIPT_PATH")" -maxdepth 1 -name "${SCRIPT_NAME}.bak.*" -type f -delete
                            cp "$SCRIPT_PATH" "${SCRIPT_PATH}.bak.$(date +%s)" 2>/dev/null
                            mv "$TEMP_SCRIPT_PATH" "$SCRIPT_PATH" 2>/dev/null
                            chmod +x "$SCRIPT_PATH" 2>/dev/null
                            
                            local base_url="${SCRIPT_REPO_URL%/*}"
                            mkdir -p "$TRANSLATIONS_DIR"
                            for lang_file in ru.sh en.sh; do
                                curl -fsSL "$base_url/translations/$lang_file" -o "$TRANSLATIONS_DIR/$lang_file" 2>/dev/null
                            done
                            
                            local auto_update_msg="✅ *$(t tg_auto_updated)* ${CURRENT_VERSION} *$(t tg_auto_updated_to)* ${REMOTE_VERSION_LATEST}"
                            local release_url="https://github.com/distillium/remnawave-backup-restore/releases/tag/${REMOTE_VERSION_LATEST}"
                            local keyboard="{\"inline_keyboard\":[[{\"text\":\"$(t tg_auto_update_changelog)\",\"url\":\"${release_url}\"}]]}"

                            curl -s -X POST ${TG_PROXY:+--proxy "$TG_PROXY"} "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
                                -d "chat_id=${CHAT_ID}" \
                                --data-urlencode "text=${auto_update_msg}" \
                                -d "parse_mode=Markdown" \
                                -d "reply_markup=${keyboard}" \
                                ${TG_MESSAGE_THREAD_ID:+-d "message_thread_id=${TG_MESSAGE_THREAD_ID}"} \
                                >/dev/null 2>&1
                        else
                            rm -f "$TEMP_SCRIPT_PATH"
                        fi
                    fi
                else
                    local update_msg="⚠️ *$(t tg_update_avail)*"$'\n'"🔄 *$(t tg_cur_ver)* ${CURRENT_VERSION}"$'\n'"🆕 *$(t tg_new_ver)* ${REMOTE_VERSION_LATEST}"$'\n\n'"📥 $(t tg_update_menu)"
                    send_telegram_message "$update_msg" >/dev/null 2>&1
                fi
            fi
        fi
    } &
}

setup_auto_send() {
    echo ""
    if [[ $EUID -ne 0 ]]; then
        print_message "WARN" "$(t cron_root)"
        read -rp "$(t press_enter)"
        return
    fi
    while true; do
        clear
        echo -e "${GREEN}${BOLD}$(t cron_title)${RESET}"
        echo ""
        if [[ -n "$CRON_TIMES" ]]; then
            print_message "INFO" "$(t cron_on) ${BOLD}${CRON_TIMES}${RESET} $(t cron_utc)"
        else
            print_message "INFO" "$(t cron_off)"
        fi
        echo ""
        ui_menu_reset
        ui_menu_add 1 "$(t cron_enable)"
        ui_menu_add 2 "$(t cron_disable)"
        ui_menu_add 0 "$(t back_to_menu)"
        ui_menu_choose choice
        echo ""
        case $choice in
            1)
                local server_offset_str=$(date +%z)
                local offset_sign="${server_offset_str:0:1}"
                local offset_hours=$((10#${server_offset_str:1:2}))
                local offset_minutes=$((10#${server_offset_str:3:2}))

                local server_offset_total_minutes=$((offset_hours * 60 + offset_minutes))
                if [[ "$offset_sign" == "-" ]]; then
                    server_offset_total_minutes=$(( -server_offset_total_minutes ))
                fi

                echo "$(t cron_variant)"
                ui_menu_reset
                ui_menu_add 1 "$(t cron_time)"
                ui_menu_add 2 "$(t cron_hourly)"
                ui_menu_add 3 "$(t cron_daily)"
                ui_menu_gap
                ui_menu_add 0 "$(t back)"
                ui_menu_choose send_choice
                echo ""
                [[ "$send_choice" == "0" ]] && continue

                cron_times_to_write=()
                user_friendly_times_local=""
                invalid_format=false

                if [[ "$send_choice" == "1" ]]; then
                    echo "$(t cron_enter_utc)"
                    ui_input times "$(t cron_time_space)" "03:00 15:00"
                    IFS=' ' read -ra arr <<< "$times"

                    for t_val in "${arr[@]}"; do
                        if [[ $t_val =~ ^([0-9]{1,2}):([0-9]{2})$ ]]; then
                            local hour_utc_input=$((10#${BASH_REMATCH[1]}))
                            local min_utc_input=$((10#${BASH_REMATCH[2]}))

                            if (( hour_utc_input >= 0 && hour_utc_input <= 23 && min_utc_input >= 0 && min_utc_input <= 59 )); then
                                local total_minutes_utc=$((hour_utc_input * 60 + min_utc_input))
                                local total_minutes_local=$((total_minutes_utc + server_offset_total_minutes))

                                while (( total_minutes_local < 0 )); do
                                    total_minutes_local=$((total_minutes_local + 24 * 60))
                                done
                                while (( total_minutes_local >= 24 * 60 )); do
                                    total_minutes_local=$((total_minutes_local - 24 * 60))
                                done

                                local hour_local=$((total_minutes_local / 60))
                                local min_local=$((total_minutes_local % 60))

                                cron_times_to_write+=("$min_local $hour_local")
                                user_friendly_times_local+="$t_val "
                            else
                                print_message "ERROR" "$(t cron_bad_value) ${BOLD}$t_val${RESET} $(t cron_hm_range)"
                                invalid_format=true
                                break
                            fi
                        else
                            print_message "ERROR" "$(t cron_bad_fmt) ${BOLD}$t_val${RESET} $(t cron_expect_hhmm)"
                            invalid_format=true
                            break
                        fi
                    done
                elif [[ "$send_choice" == "2" ]]; then
                    cron_times_to_write=("@hourly")
                    user_friendly_times_local="@hourly"
                elif [[ "$send_choice" == "3" ]]; then
                    cron_times_to_write=("@daily")
                    user_friendly_times_local="@daily"
                else
                    print_message "ERROR" "$(t cron_bad_choice)"
                    continue
                fi

                echo ""

                if [ "$invalid_format" = true ] || [ ${#cron_times_to_write[@]} -eq 0 ]; then
                    print_message "ERROR" "$(t cron_err_input)"
                    continue
                fi

                print_message "INFO" "$(t cron_setting)"

                mkdir -p "$LOG_DIR" && chmod 700 "$LOG_DIR"
                local temp_crontab_file=$(mktemp)

                if ! crontab -l > "$temp_crontab_file" 2>/dev/null; then
                    touch "$temp_crontab_file"
                fi

                if ! grep -q "^SHELL=" "$temp_crontab_file"; then
                    echo "SHELL=/bin/bash" | cat - "$temp_crontab_file" > "$temp_crontab_file.tmp"
                    mv "$temp_crontab_file.tmp" "$temp_crontab_file"
                    print_message "INFO" "$(t cron_shell)"
                fi

                if ! grep -q "^PATH=" "$temp_crontab_file"; then
                    echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin" | cat - "$temp_crontab_file" > "$temp_crontab_file.tmp"
                    mv "$temp_crontab_file.tmp" "$temp_crontab_file"
                    print_message "INFO" "$(t cron_path_add)"
                else
                    print_message "INFO" "$(t cron_path_exists)"
                fi

                grep -vF "$SCRIPT_PATH backup" "$temp_crontab_file" > "$temp_crontab_file.tmp"
                mv "$temp_crontab_file.tmp" "$temp_crontab_file"

                for time_entry_local in "${cron_times_to_write[@]}"; do
                    if [[ "$time_entry_local" == "@hourly" ]] || [[ "$time_entry_local" == "@daily" ]]; then
                        echo "$time_entry_local $SCRIPT_PATH backup >> $LOG_DIR/cron.log 2>&1" >> "$temp_crontab_file"
                    else
                        echo "$time_entry_local * * * $SCRIPT_PATH backup >> $LOG_DIR/cron.log 2>&1" >> "$temp_crontab_file"
                    fi
                done

                if crontab "$temp_crontab_file"; then
                    print_message "SUCCESS" "$(t cron_ok)"
                else
                    print_message "ERROR" "$(t cron_fail)"
                fi

                rm -f "$temp_crontab_file"

                CRON_TIMES="${user_friendly_times_local% }"
                save_config
                print_message "SUCCESS" "$(t cron_set) ${BOLD}${CRON_TIMES}${RESET} $(t cron_utc)"
                ;;
            2)
                print_message "INFO" "$(t cron_disabling)"
                (crontab -l 2>/dev/null | grep -vF "$SCRIPT_PATH backup") | crontab -

                CRON_TIMES=""
                save_config
                print_message "SUCCESS" "$(t cron_disabled)"
                ;;
            0) break ;;
            *) print_message "ERROR" "$(t invalid_input_select)" ;;
        esac
        echo ""
        read -rp "$(t press_enter)"
    done
    echo ""
}

prepare_donate_qr() {
    local panel_status="$1" bot_status="$2"
    [[ "$panel_status" == "0" || "$bot_status" == "0" ]] || return 0
    if ! command -v qrencode &>/dev/null && command -v apt-get &>/dev/null && [[ $EUID -eq 0 ]]; then
        apt-get update -qq > /dev/null 2>&1 || true
        apt-get install -y qrencode > /dev/null 2>&1 || true
    fi
    command -v qrencode &>/dev/null || return 0
    local f
    f=$(mktemp 2>/dev/null) || return 0
    if ! qrencode -t UTF8 -m 1 "$DONATE_URL" > "$f" 2>/dev/null || [[ ! -s "$f" ]]; then
        rm -f "$f"; return 0
    fi
    echo "$f"
}

show_donate_after_restore() {
    local panel_status="$1" bot_status="$2" qr_file="$3"
    [[ "$panel_status" == "0" || "$bot_status" == "0" ]] || return 0
    local LC_ALL=C.UTF-8
    local -a qr=() txt=() txt_style=()
    local line word cur
    [[ -n "$qr_file" && -s "$qr_file" ]] && mapfile -t qr < "$qr_file"

    local text_w=${#DONATE_URL}
    (( text_w < 40 )) && text_w=40

    txt+=("$(t rs_donate_title)"); txt_style+=("title")
    txt+=(""); txt_style+=("")
    local para
    for para in rs_donate_text rs_donate_scan; do
        cur=""
        for word in $(t "$para"); do
            if [[ -z "$cur" ]]; then
                cur="$word"
            elif (( ${#cur} + 1 + ${#word} <= text_w )); then
                cur+=" $word"
            else
                txt+=("$cur"); txt_style+=("text"); cur="$word"
            fi
        done
        [[ -n "$cur" ]] && { txt+=("$cur"); txt_style+=("text"); }
        [[ "$para" == "rs_donate_text" ]] && { txt+=(""); txt_style+=(""); }
    done
    txt+=("$DONATE_URL"); txt_style+=("link")

    local qr_w=0
    (( ${#qr[@]} > 0 )) && qr_w=${#qr[0]}
    local inner
    if (( qr_w > 0 )); then
        inner=$((1 + qr_w + 3 + text_w + 1))
    else
        inner=$((2 + text_w + 2))
    fi

    local cols
    cols=$(tput cols 2>/dev/null || echo 80)
    if (( inner + 2 > cols )); then
        echo ""
        echo -e "${GREEN}${BOLD}$(t rs_donate_title)${RESET}"
        echo -e "${GRAY}$(t rs_donate_text)${RESET}"
        echo -e "${GRAY}$(t rs_donate_scan)${RESET}"
        echo ""
        (( ${#qr[@]} > 0 )) && { printf '\e[97;40m%s\e[0m\n' "${qr[@]}"; echo ""; }
        print_message "LINK" "$(t rs_donate_link) ${BOLD}${DONATE_URL}${RESET}"
        echo ""
        return 0
    fi

    local rows=${#qr[@]}
    (( ${#txt[@]} > rows )) && rows=${#txt[@]}
    local off=$(( (rows - ${#txt[@]}) / 2 ))
    local B="$GREEN" hr="" i
    for ((i = 0; i < inner; i++)); do hr+="─"; done

    echo ""
    echo -e "${B}╭${hr}╮${RESET}"
    echo -e "${B}│${RESET}$(printf '%*s' "$inner" '')${B}│${RESET}"
    for ((i = 0; i < rows; i++)); do
        local left="" right="" plain_r="" ti=$((i - off)) st=""
        if (( qr_w > 0 )); then
            if (( i < ${#qr[@]} )); then
                left=" "$'\e[97;40m'"${qr[$i]}"$'\e[0m'"   "
            else
                left="$(printf '%*s' $((qr_w + 4)) '')"
            fi
        else
            left="  "
        fi
        if (( ti >= 0 && ti < ${#txt[@]} )); then
            plain_r="${txt[$ti]}"; st="${txt_style[$ti]}"
        fi
        case "$st" in
            title) right="${GREEN}${BOLD}${plain_r}${RESET}" ;;
            text)  right="${GRAY}${plain_r}${RESET}" ;;
            link)  right="${CYAN}${BOLD}${plain_r}${RESET}" ;;
            *)     right="$plain_r" ;;
        esac
        local used
        if (( qr_w > 0 )); then used=$((1 + qr_w + 3 + ${#plain_r})); else used=$((2 + ${#plain_r})); fi
        echo -e "${B}│${RESET}${left}${right}$(printf '%*s' $((inner - used)) '')${B}│${RESET}"
    done
    echo -e "${B}│${RESET}$(printf '%*s' "$inner" '')${B}│${RESET}"
    echo -e "${B}╰${hr}╯${RESET}"
    echo ""
    return 0
}

restore_backup() {
    RESTORE_AGE_PUBLIC=""
    LOG_CATEGORY="restore"
    log_write "INFO" "=== restore started (v${VERSION}) ==="
    clear
    echo "${GREEN}${BOLD}$(t rs_title)${RESET}"
    echo ""
    
    if [[ "$DB_CONNECTION_TYPE" == "external" ]]; then
        print_message "INFO" "$(t rs_mode_ext) (${DB_HOST}:${DB_PORT}/${DB_NAME})"
    else
        print_message "INFO" "$(t rs_mode_docker)"
    fi
    echo ""

    local S3_STREAM_RESTORE=false

    echo "$(t rs_source_select)"
    ui_menu_reset
    ui_menu_add 1 "$(t rs_source_local)"
    ui_menu_add 2 "$(t rs_source_s3)"
    ui_menu_gap
    ui_menu_add 0 "$(t back_to_menu)"
    local source_choice
    ui_menu_choose source_choice

    case "$source_choice" in
        0) return ;;
        2)
            local rs_s3_num="" rs_s3_n
            local rs_s3_endpoint="" rs_s3_region="" rs_s3_bucket="" rs_s3_access="" rs_s3_secret="" rs_s3_prefix=""
            local rs_s3_manual=false
            local -a rs_s3_nums=()
            while IFS= read -r rs_s3_n; do
                if [[ -n "$(_s3_var BUCKET "$rs_s3_n")" && -n "$(_s3_var ACCESS_KEY "$rs_s3_n")" && -n "$(_s3_var SECRET_KEY "$rs_s3_n")" ]]; then
                    rs_s3_nums+=("$rs_s3_n")
                fi
            done < <(_s3_configured_nums)

            if [[ ${#rs_s3_nums[@]} -eq 0 ]]; then
                rs_s3_manual=true
            else
                echo ""
                echo "$(t rs_s3_pick_target)"
                local rs_pick_i=0
                ui_menu_reset
                for rs_s3_n in "${rs_s3_nums[@]}"; do
                    rs_pick_i=$((rs_pick_i + 1))
                    ui_menu_add "$rs_pick_i" "$(_s3_label "$rs_s3_n") ($(_s3_var BUCKET "$rs_s3_n"))"
                done
                ui_menu_add "$((${#rs_s3_nums[@]} + 1))" "$(t rs_s3_manual_entry)"
                ui_menu_gap
                ui_menu_add 0 "$(t back)"
                local rs_pick
                while true; do
                    ui_menu_choose rs_pick
                    [[ "$rs_pick" == "0" ]] && return
                    if [[ "$rs_pick" =~ ^[0-9]+$ ]] && (( rs_pick >= 1 && rs_pick <= ${#rs_s3_nums[@]} + 1 )); then
                        if (( rs_pick == ${#rs_s3_nums[@]} + 1 )); then
                            rs_s3_manual=true
                        else
                            rs_s3_num="${rs_s3_nums[$((rs_pick - 1))]}"
                        fi
                        break
                    fi
                    print_message "ERROR" "$(t rs_invalid_num)"
                done
            fi

            if [[ "$rs_s3_manual" == "true" ]]; then
                print_message "ACTION" "$(t rs_s3_enter_creds)"
                echo ""
                ui_input rs_s3_endpoint "$(t ul_s3_enter_endpoint)" "https://s3.example.com"
                ui_input rs_s3_region "$(t ul_s3_enter_region)"
                ui_input rs_s3_bucket "$(t ul_s3_enter_bucket)" "rw-backups"
                ui_input rs_s3_access "$(t ul_s3_enter_access)"
                ui_input rs_s3_secret "$(t ul_s3_enter_secret)"
                echo ""
                echo "   $(t ul_s3_prefix_info1)"
                echo "   $(t ul_s3_prefix_info2)"
                ui_input rs_s3_prefix "$(t ul_s3_enter_prefix)" "server-1"
                echo ""
            else
                rs_s3_endpoint="$(_s3_var ENDPOINT "$rs_s3_num")"
                rs_s3_region="$(_s3_var REGION "$rs_s3_num")"
                rs_s3_bucket="$(_s3_var BUCKET "$rs_s3_num")"
                rs_s3_access="$(_s3_var ACCESS_KEY "$rs_s3_num")"
                rs_s3_secret="$(_s3_var SECRET_KEY "$rs_s3_num")"
                rs_s3_prefix="$(_s3_var PREFIX "$rs_s3_num")"
            fi
            rs_s3_region="${rs_s3_region:-us-east-1}"

            if [[ -z "$rs_s3_bucket" || -z "$rs_s3_access" || -z "$rs_s3_secret" || -z "$rs_s3_endpoint" ]]; then
                print_message "ERROR" "$(t ul_s3_fail)"
                read -rp "$(t press_enter_back)"
                return
            fi

            if ! command -v aws &> /dev/null; then
                if ! install_aws_cli; then
                    print_message "ERROR" "$(t s3_aws_not_found)"
                    read -rp "$(t press_enter_back)"
                    return
                fi
            fi

            print_message "INFO" "$(t rs_s3_listing)"

            local s3_endpoint_arg="--endpoint-url $rs_s3_endpoint"
            local s3_prefix_arg="${rs_s3_prefix:+${rs_s3_prefix}/}"

            local s3_file_list s3_ls_out s3_ls_rc=0
            if s3_ls_out=$(AWS_ACCESS_KEY_ID="$rs_s3_access" \
                AWS_SECRET_ACCESS_KEY="$rs_s3_secret" \
                AWS_DEFAULT_REGION="$rs_s3_region" \
                aws s3 ls "s3://${rs_s3_bucket}/${s3_prefix_arg}" \
                $s3_endpoint_arg 2>&1); then
                s3_ls_rc=0
            else
                s3_ls_rc=$?
            fi

            if [[ $s3_ls_rc -ne 0 ]]; then
                print_message "ERROR" "$(t rs_s3_conn_failed)"
                echo -e "${GRAY}$(echo "$s3_ls_out" | head -n 3)${RESET}"
                read -rp "$(t press_enter_back)"
                return
            fi

            s3_file_list=$(echo "$s3_ls_out" | grep "remnawave_backup_.*\.tar\.gz" | sort -r || true)

            if [[ -z "$s3_file_list" ]]; then
                print_message "ERROR" "$(t rs_s3_no_files)"
                read -rp "$(t press_enter_back)"
                return
            fi

            local -a s3_files=()
            local -a s3_sizes=()
            while IFS= read -r line; do
                local fname
                fname=$(echo "$line" | awk '{print $NF}')
                local fsize
                fsize=$(echo "$line" | awk '{print $3}')
                if [[ -n "$fname" ]]; then
                    s3_files+=("$fname")
                    s3_sizes+=("$fsize")
                fi
            done <<< "$s3_file_list"

            echo ""
            echo "$(t rs_s3_select)"
            local i=1
            ui_menu_reset
            for idx in "${!s3_files[@]}"; do
                ui_menu_add "$i" "${s3_files[$idx]} ${LIGHT_GRAY}($(_ui_human_size "${s3_sizes[$idx]}"))${RESET}"
                i=$((i+1))
            done
            ui_menu_gap
            ui_menu_add 0 "$(t back)"

            local s3_choice s3_index
            while true; do
                ui_menu_choose s3_choice
                [[ "$s3_choice" == "0" ]] && return
                [[ "$s3_choice" =~ ^[0-9]+$ ]] || { print_message "ERROR" "$(t invalid_input)"; continue; }
                s3_index=$((s3_choice - 1))
                (( s3_index >= 0 && s3_index < ${#s3_files[@]} )) && break
                print_message "ERROR" "$(t rs_invalid_num)"
            done

            local selected_s3_file="${s3_files[$s3_index]}"
            local s3_full_key="${s3_prefix_arg}${selected_s3_file}"

            S3_STREAM_RESTORE=true
            S3_RESTORE_KEY="$s3_full_key"
            S3_RESTORE_FILE="$selected_s3_file"
            S3_RESTORE_ENDPOINT_ARG="$s3_endpoint_arg"
            S3_RESTORE_ACCESS="$rs_s3_access"
            S3_RESTORE_SECRET="$rs_s3_secret"
            S3_RESTORE_REGION="$rs_s3_region"
            S3_RESTORE_BUCKET="$rs_s3_bucket"
            ;;
        1) ;;
        *) print_message "ERROR" "$(t invalid_input_select)"; read -rp "$(t press_enter)"; return ;;
    esac

    local temp_restore_dir="$BACKUP_DIR/restore_temp_$$"
    mkdir -p "$temp_restore_dir"

    if [[ "$S3_STREAM_RESTORE" == true ]]; then
        clear
        print_message "INFO" "$(t rs_s3_stream) ${BOLD}${S3_RESTORE_FILE}${RESET}..."

        local s3_stream_ok=true
        if [[ "$S3_RESTORE_FILE" == *.age ]]; then
            if ! install_age || ! prompt_age_private_key; then
                print_message "ERROR" "$(t enc_restore_no_key)"
                rm -rf "$temp_restore_dir"
                read -rp "$(t press_enter_back)"
                return
            fi
            ui_spin_start "$(t rs_s3_streaming)"
            (set -o pipefail
             AWS_ACCESS_KEY_ID="$S3_RESTORE_ACCESS" \
             AWS_SECRET_ACCESS_KEY="$S3_RESTORE_SECRET" \
             AWS_DEFAULT_REGION="$S3_RESTORE_REGION" \
             aws s3 cp "s3://${S3_RESTORE_BUCKET}/${S3_RESTORE_KEY}" - \
             $S3_RESTORE_ENDPOINT_ARG 2>/dev/null \
             | age -d -i <(printf '%s\n' "$AGE_PRIVATE_KEY") \
             | tar -xzf - -C "$temp_restore_dir") || s3_stream_ok=false
            [[ "$s3_stream_ok" == "true" ]] && RESTORE_AGE_PUBLIC=$(printf '%s\n' "$AGE_PRIVATE_KEY" | _age_public_from_private)
            AGE_PRIVATE_KEY=""
            [[ "$s3_stream_ok" == "false" ]] && print_message "ERROR" "$(t enc_decrypt_failed)"
        else
            ui_spin_start "$(t rs_s3_streaming)"
            (set -o pipefail
             AWS_ACCESS_KEY_ID="$S3_RESTORE_ACCESS" \
             AWS_SECRET_ACCESS_KEY="$S3_RESTORE_SECRET" \
             AWS_DEFAULT_REGION="$S3_RESTORE_REGION" \
             aws s3 cp "s3://${S3_RESTORE_BUCKET}/${S3_RESTORE_KEY}" - \
             $S3_RESTORE_ENDPOINT_ARG 2>/dev/null \
             | tar -xzf - -C "$temp_restore_dir") || s3_stream_ok=false
        fi
        if [[ "$s3_stream_ok" != "true" ]]; then
            print_message "ERROR" "$(t rs_s3_stream_err)"
            rm -rf "$temp_restore_dir"
            read -rp "$(t press_enter_back)"
            return
        fi

        print_message "SUCCESS" "$(t rs_s3_stream_ok)"
        echo ""
    else
        print_message "INFO" "$(t rs_place_file) ${BOLD}${BACKUP_DIR}${RESET}"
        echo ""

        if ! compgen -G "$BACKUP_DIR/remnawave_backup_*.tar.gz" > /dev/null && ! compgen -G "$BACKUP_DIR/remnawave_backup_*.tar.gz.age" > /dev/null; then
            print_message "ERROR" "$(t rs_no_files) ${BOLD}${BACKUP_DIR}${RESET}."
            rm -rf "$temp_restore_dir"
            read -rp "$(t press_enter_back)"
            return
        fi

        readarray -t SORTED_BACKUP_FILES < <(
            find "$BACKUP_DIR" -maxdepth 1 \( -name "remnawave_backup_*.tar.gz" -o -name "remnawave_backup_*.tar.gz.age" \) -printf "%T@ %p\n" | sort -nr | cut -d' ' -f2-
        )

        echo ""
        echo "$(t rs_select_file)"
        local i=1
        ui_menu_reset
        for file in "${SORTED_BACKUP_FILES[@]}"; do
            ui_menu_add "$i" "${file##*/} ${LIGHT_GRAY}($(_ui_human_size "$(stat -c %s "$file" 2>/dev/null || echo 0)"))${RESET}"
            i=$((i+1))
        done
        ui_menu_gap
        ui_menu_add 0 "$(t back_to_menu)"

        local user_choice selected_index
        while true; do
            ui_menu_choose user_choice
            [[ "$user_choice" == "0" ]] && { rm -rf "$temp_restore_dir"; return; }
            [[ "$user_choice" =~ ^[0-9]+$ ]] || { print_message "ERROR" "$(t invalid_input)"; continue; }
            selected_index=$((user_choice - 1))
            (( selected_index >= 0 && selected_index < ${#SORTED_BACKUP_FILES[@]} )) && break
            print_message "ERROR" "$(t rs_invalid_num)"
        done

        SELECTED_BACKUP="${SORTED_BACKUP_FILES[$selected_index]}"

        clear

        local local_extract_ok=true
        if [[ "$SELECTED_BACKUP" == *.age ]]; then
            if ! install_age || ! prompt_age_private_key; then
                print_message "ERROR" "$(t enc_restore_no_key)"
                rm -rf "$temp_restore_dir"
                read -rp "$(t press_enter_back)"
                return
            fi
            ui_spin_start "$(t rs_unpacking)"
            (set -o pipefail; age -d -i <(printf '%s\n' "$AGE_PRIVATE_KEY") "$SELECTED_BACKUP" | tar -xzf - -C "$temp_restore_dir") || local_extract_ok=false
            [[ "$local_extract_ok" == "true" ]] && RESTORE_AGE_PUBLIC=$(printf '%s\n' "$AGE_PRIVATE_KEY" | _age_public_from_private)
            AGE_PRIVATE_KEY=""
            [[ "$local_extract_ok" == "false" ]] && print_message "ERROR" "$(t enc_decrypt_failed)"
        else
            ui_spin_start "$(t rs_unpacking)"
            tar -xzf "$SELECTED_BACKUP" -C "$temp_restore_dir" || local_extract_ok=false
        fi
        if [[ "$local_extract_ok" != "true" ]]; then
            print_message "ERROR" "$(t rs_unpack_err)"
            rm -rf "$temp_restore_dir"
            read -rp "$(t press_enter_back)"
            return
        fi

        print_message "SUCCESS" "$(t rs_unpacked)"
        echo ""
    fi

    local BACKUP_DUMP_TYPE="dumpall"
    local BOT_META_VERSION=""
    local BACKUP_META_VERSION=""
    local BACKUP_META_DB_NAME=""
    
    if [[ -f "$temp_restore_dir/backup_meta.info" ]]; then
        local -a _meta=()
        mapfile -t _meta < <(
            DUMP_TYPE="" BACKUP_VERSION="" DB_NAME="" PANEL_VERSION="" BOT_META_VERSION=""
            source "$temp_restore_dir/backup_meta.info" >/dev/null 2>&1
            printf '%s\n' "$DUMP_TYPE" "$BACKUP_VERSION" "$DB_NAME" "$PANEL_VERSION" "$BOT_META_VERSION"
        )
        BACKUP_DUMP_TYPE="${_meta[0]:-dumpall}"
        BACKUP_META_VERSION="${_meta[1]:-}"
        BACKUP_META_DB_NAME="${_meta[2]:-}"
        BACKUP_PANEL_VERSION="${_meta[3]:-}"
        BOT_META_VERSION="${_meta[4]:-}"
        local -a meta_rows=(
            "$(t rs_meta_dump):" "$BACKUP_DUMP_TYPE"
            "$(t rs_meta_ver):" "$(_ver_disp "$BACKUP_META_VERSION")"
            "$(t rs_meta_panel):" "$(_ver_disp "$BACKUP_PANEL_VERSION")"
        )
        [[ -n "${BOT_META_VERSION:-}" ]] && meta_rows+=("$(t rs_meta_bot_ver):" "$(_ver_disp "$BOT_META_VERSION")")
        print_message "INFO" "$(t rs_meta)"
        print_aligned_rows "${meta_rows[@]}"
    else
        print_message "INFO" "$(t rs_no_meta)"
    fi
    
    local CURRENT_DUMP_TYPE
    if [[ "$DB_CONNECTION_TYPE" == "docker" ]]; then
        CURRENT_DUMP_TYPE="dumpall"
    else
        CURRENT_DUMP_TYPE="dump"
    fi
    
    if [[ "$BACKUP_DUMP_TYPE" != "$CURRENT_DUMP_TYPE" ]]; then
        echo ""
        print_message "WARN" "${YELLOW}$(t rs_mismatch)${RESET}"
        print_message "WARN" "$(t rs_bk_mode) ${BOLD}${BACKUP_DUMP_TYPE}${RESET}"
        print_message "WARN" "$(t rs_cur_mode) ${BOLD}${CURRENT_DUMP_TYPE}${RESET}"
        echo ""
        
        if [[ "$BACKUP_DUMP_TYPE" == "dump" && "$CURRENT_DUMP_TYPE" == "dumpall" ]]; then
            print_message "INFO" "$(t rs_ext_options)"
            echo ""
            ui_menu_reset
            ui_menu_add 1 "$(t rs_opt_ext)"
            ui_menu_add 2 "$(t rs_opt_docker)"
            ui_menu_add 0 "$(t rs_opt_cancel)"
            
            local ext_choice
            ui_menu_choose ext_choice
            
            case "$ext_choice" in
                1)
                    print_message "ACTION" "$(t rs_enter_ext)"
                    echo ""
                    ui_input DB_HOST "$(t rs_host)" "db.example.com"
                    ui_input input_db_port "$(t rs_port)"
                    DB_PORT="${input_db_port:-5432}"
                    ui_input input_db_name "$(t rs_dbname)"
                    DB_NAME="${input_db_name:-postgres}"
                    ui_input input_db_user "$(t rs_user)"
                    DB_USER="${input_db_user:-postgres}"
                    ui_secret DB_PASSWORD "$(t rs_pass)"
                    ui_input input_ssl "$(t rs_ssl)"
                    DB_SSL_MODE="${input_ssl:-prefer}"
                    ui_input input_pg_ver "$(t rs_pgver)"
                    DB_POSTGRES_VERSION="${input_pg_ver:-17}"
                    
                    DB_CONNECTION_TYPE="external"
                    CURRENT_DUMP_TYPE="dump"
                    
                    echo ""
                    print_message "INFO" "$(t rs_testing)"
                    local pg_image=$(get_postgres_image)
                    if docker run --rm --network host \
                        -e PGPASSWORD="$DB_PASSWORD" \
                        -e PGSSLMODE="$DB_SSL_MODE" \
                        "$pg_image" \
                        pg_isready -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" 2>/dev/null; then
                        print_message "SUCCESS" "$(t rs_conn_ok)"
                        save_config
                        print_message "SUCCESS" "$(t rs_ext_saved)"
                    else
                        print_message "ERROR" "$(t rs_conn_fail)"
                        rm -rf "$temp_restore_dir"
                        read -rp "$(t press_enter_back)"
                        return
                    fi
                    ;;
                2)
                    print_message "WARN" "$(t rs_globals_skip)"
                    print_message "INFO" "$(t rs_cont_docker)"
                    ;;
                0|*)
                    print_message "INFO" "$(t rs_cancelled)"
                    rm -rf "$temp_restore_dir"
                    read -rp "$(t press_enter_back)"
                    return
                    ;;
            esac
        elif [[ "$BACKUP_DUMP_TYPE" == "dumpall" && "$CURRENT_DUMP_TYPE" == "dump" ]]; then
            print_message "WARN" "$(t rs_dumpall_ext)"
            print_message "WARN" "$(t rs_dumpall_warn)"
            echo ""
            ui_confirm compat_confirm "$(t rs_continue_q)"
            if [[ ! "$compat_confirm" =~ ^[yY]$ ]]; then
                print_message "INFO" "$(t rs_cancelled)"
                rm -rf "$temp_restore_dir"
                read -rp "$(t press_enter_back)"
                return
            fi
        fi
    fi

    local PANEL_DUMP
    PANEL_DUMP=$(find "$temp_restore_dir" -name "dump_*.sql.gz" | head -n 1)
    local PANEL_DIR_ARCHIVE
    PANEL_DIR_ARCHIVE=$(find "$temp_restore_dir" -name "remnawave_dir_*.tar.gz" | head -n 1)

    local PANEL_STATUS=2 
    local BOT_STATUS=2

    if [[ -z "$PANEL_DUMP" && -z "$PANEL_DIR_ARCHIVE" ]]; then
        print_message "WARN" "$(t rs_panel_missing)"
        PANEL_STATUS=2
    else
        local restore_scope="all"
        local scope_cancelled=false

        echo ""
        print_message "INFO" "$(t rs_panel_found)"
        echo ""
        ui_confirm confirm_panel "$(t rs_panel_q)"
        echo ""
        if [[ ! "$confirm_panel" =~ ^[Yy]$ ]]; then
            scope_cancelled=true
        elif [[ -n "$PANEL_DUMP" && -n "$PANEL_DIR_ARCHIVE" ]]; then
            echo "$(t rs_panel_scope_title)"
            ui_menu_reset
            ui_menu_add 1 "$(t rs_scope_all)"
            ui_menu_add 2 "$(t rs_scope_db)"
            ui_menu_add 3 "$(t rs_scope_files)"
            ui_menu_add 0 "$(t back)"
            local scope_choice
            ui_menu_choose scope_choice
            echo ""
            case "$scope_choice" in
                1) restore_scope="all" ;;
                2) restore_scope="db" ;;
                3) restore_scope="files" ;;
                0) scope_cancelled=true ;;
                *) print_message "ERROR" "$(t invalid_input_select)"; scope_cancelled=true ;;
            esac
        elif [[ -n "$PANEL_DUMP" ]]; then
            restore_scope="db"
            print_message "WARN" "$(t rs_scope_only_db_found)"
        else
            restore_scope="files"
            print_message "WARN" "$(t rs_scope_only_files_found)"
        fi

        if [[ "$scope_cancelled" == true ]]; then
            print_message "INFO" "$(t rs_panel_skipped)"
            PANEL_STATUS=2
        else
            check_docker_installed || { rm -rf "$temp_restore_dir"; return 1; }

            if [[ "$restore_scope" == "db" ]]; then
                if ! (cd "$REMNALABS_ROOT_DIR" 2>/dev/null && { [[ -f docker-compose.yml ]] || [[ -f docker-compose.yaml ]] || [[ -f compose.yml ]] || [[ -f compose.yaml ]]; }); then
                    print_message "ERROR" "$(t rs_files_required_first)"
                    rm -rf "$temp_restore_dir"
                    read -rp "$(t press_enter_back)"
                    return 1
                fi
            fi

            if [[ -d "$REMNALABS_ROOT_DIR" ]]; then
                cd "$REMNALABS_ROOT_DIR" 2>/dev/null && docker compose down 2>/dev/null
                cd ~
            fi

            if [[ "$restore_scope" != "db" ]]; then
                rm -rf "$REMNALABS_ROOT_DIR"
                mkdir -p "$REMNALABS_ROOT_DIR"
                local extract_dir="$BACKUP_DIR/extract_temp_$$"
                mkdir -p "$extract_dir"
                tar -xzf "$PANEL_DIR_ARCHIVE" -C "$extract_dir"
                local extracted_dir
                extracted_dir=$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1)
                cp -rf "$extracted_dir"/. "$REMNALABS_ROOT_DIR/"
                rm -rf "$extract_dir"
            fi

            if [[ "$restore_scope" == "files" ]]; then
                print_message "INFO" "$(t rs_start_containers)"
                cd "$REMNALABS_ROOT_DIR" || { print_message "ERROR" "$(t rs_dir_missing)"; return; }
                if docker compose up -d; then
                    print_message "SUCCESS" "$(t rs_panel_ok)"
                    PANEL_STATUS=0
                else
                    print_message "ERROR" "$(t rs_panel_fail)"
                    rm -rf "$temp_restore_dir"
                    read -rp "$(t press_enter_back)"
                    return 1
                fi
            else
                if [[ "$DB_CONNECTION_TYPE" == "docker" ]]; then
                    docker volume rm remnawave-db-data 2>/dev/null || true
                    cd "$REMNALABS_ROOT_DIR" || { print_message "ERROR" "$(t rs_dir_missing)"; return; }
                    docker compose up -d remnawave-db

                    print_message "INFO" "$(t rs_wait_db)"
                    until [[ "$(docker inspect --format='{{.State.Health.Status}}' remnawave-db)" == "healthy" ]]; do
                        sleep 2
                        echo -n "."
                    done
                    echo ""
                else
                    print_message "INFO" "$(t rs_check_ext)"
                    local pg_image=$(get_postgres_image)
                    if ! docker run --rm --network host \
                        -e PGPASSWORD="$DB_PASSWORD" \
                        -e PGSSLMODE="$DB_SSL_MODE" \
                        "$pg_image" \
                        pg_isready -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" 2>/dev/null; then
                        print_message "ERROR" "$(t rs_ext_unavail) (${DB_HOST}:${DB_PORT}). $(t rs_check_conn)"
                        rm -rf "$temp_restore_dir"
                        read -rp "$(t press_enter_back)"
                        return 1
                    fi
                    print_message "SUCCESS" "$(t rs_ext_ok)"
                fi

                ui_spin_start "$(t rs_restoring_db)"
                gunzip "$PANEL_DUMP"
                local sql_file="${PANEL_DUMP%.gz}"
                local restore_log="$temp_restore_dir/restore_errors.log"

                local restore_db_name
                if [[ "$DB_CONNECTION_TYPE" == "docker" ]]; then
                    restore_db_name="postgres"
                else
                    restore_db_name="${DB_NAME:-postgres}"
                fi

                if ! restore_panel_db_dump "$sql_file" "$restore_db_name" "$restore_log"; then
                    ui_spin_stop
                    echo ""
                    print_message "ERROR" "$(t rs_db_err)"
                    [[ -f "$restore_log" ]] && cat "$restore_log"
                    rm -rf "$temp_restore_dir"
                    read -rp "$(t press_enter_back)"
                    return 1
                fi

                print_message "SUCCESS" "$(t rs_db_ok)"
                echo ""

                if [[ "$DB_CONNECTION_TYPE" == "docker" ]]; then
                    print_message "INFO" "$(t rs_start_containers)"
                else
                    print_message "INFO" "$(t rs_start_no_db)"
                fi
                cd "$REMNALABS_ROOT_DIR" || { print_message "ERROR" "$(t rs_dir_missing)"; return; }
                if docker compose up -d; then
                    print_message "SUCCESS" "$(t rs_panel_ok)"
                    PANEL_STATUS=0
                else
                    print_message "ERROR" "$(t rs_panel_fail)"
                    rm -rf "$temp_restore_dir"
                    read -rp "$(t press_enter_back)"
                    return 1
                fi
            fi
        fi
    fi

    echo ""

    if [[ "$PANEL_STATUS" == "0" ]]; then
        print_message "SUCCESS" "$(t rs_panel_ready)"
        read -rp ""
    fi

    if restore_bot_backup "$temp_restore_dir"; then
        BOT_STATUS=0
    else
        local res=$?
        if [[ "$res" == "2" ]]; then BOT_STATUS=2; else BOT_STATUS=1; fi
    fi

    rm -rf "$temp_restore_dir"
    sleep 2
    
    REMNAWAVE_VERSION=$(get_remnawave_version)
    local telegram_msg
    local rw_ver_disp="$REMNAWAVE_VERSION"
    [[ "$rw_ver_disp" =~ ^[0-9] ]] && rw_ver_disp="v${rw_ver_disp}"
    telegram_msg="💾 #restore_success"$'\n'"➖➖➖➖➖➖➖➖➖"$'\n'"✅ *$(t tg_restore_done)*"$'\n'"• *Remnawave:* ${rw_ver_disp}"

    if [[ "$PANEL_STATUS" == "0" && "$BOT_STATUS" == "0" ]]; then
        telegram_msg+=$'\n'"✨ *$(t tg_panel_bot)*"
    elif [[ "$PANEL_STATUS" == "0" ]]; then
        telegram_msg+=$'\n'"• *$(t tg_only_panel)*"
    elif [[ "$BOT_STATUS" == "0" ]]; then
        telegram_msg+=$'\n'"• *$(t tg_only_bot)*"
    else
        telegram_msg+=$'\n'"⚠️ *$(t tg_nothing)*"
    fi

    if [[ "$PANEL_STATUS" == "0" || "$BOT_STATUS" == "0" ]]; then
        local donate_qr_file
        donate_qr_file=$(prepare_donate_qr "$PANEL_STATUS" "$BOT_STATUS")
        echo ""
        print_message "SUCCESS" "${BOLD}$(t rs_complete)${RESET}"
        show_donate_after_restore "$PANEL_STATUS" "$BOT_STATUS" "$donate_qr_file"
        [[ -n "$donate_qr_file" ]] && rm -f "$donate_qr_file"
        offer_enable_encryption_after_restore
        send_telegram_message "$telegram_msg" "MarkdownV2" "$(donate_keyboard)" >/dev/null 2>&1
    else
        echo ""
        print_message "WARN" "${BOLD}$(t rs_nothing_restored)${RESET}"
        echo ""
    fi
    read -rp "$(t press_enter_back)"
}

update_script() {
    print_message "INFO" "$(t upd_checking)"
    echo ""
    if [[ "$EUID" -ne 0 ]]; then
        echo -e "${RED}⛔ $(t upd_root)${RESET}"
        read -rp "$(t press_enter)"
        return
    fi

    print_message "INFO" "$(t upd_fetching)"
    local TEMP_REMOTE_VERSION_FILE
    TEMP_REMOTE_VERSION_FILE=$(mktemp)

    if ! curl -fsSL "$SCRIPT_REPO_URL" 2>/dev/null | head -n 100 > "$TEMP_REMOTE_VERSION_FILE"; then
        print_message "ERROR" "$(t upd_fetch_fail)"
        rm -f "$TEMP_REMOTE_VERSION_FILE"
        read -rp "$(t press_enter)"
        return
    fi

    REMOTE_VERSION=$(grep -m 1 "^VERSION=" "$TEMP_REMOTE_VERSION_FILE" | cut -d'"' -f2)
    rm -f "$TEMP_REMOTE_VERSION_FILE"

    if [[ -z "$REMOTE_VERSION" ]]; then
        print_message "ERROR" "$(t upd_parse_fail)"
        read -rp "$(t press_enter)"
        return
    fi

    print_message "INFO" "$(t upd_current) ${BOLD}${YELLOW}${VERSION}${RESET}"
    print_message "INFO" "$(t upd_available) ${BOLD}${GREEN}${REMOTE_VERSION}${RESET}"
    echo ""

    compare_versions() {
        local v1="$1"
        local v2="$2"

        local v1_num="${v1//[^0-9.]/}"
        local v2_num="${v2//[^0-9.]/}"

        local v1_sfx="${v1//$v1_num/}"
        local v2_sfx="${v2//$v2_num/}"

        if [[ "$v1_num" == "$v2_num" ]]; then
            if [[ -z "$v1_sfx" && -n "$v2_sfx" ]]; then
                return 0
            elif [[ -n "$v1_sfx" && -z "$v2_sfx" ]]; then
                return 1
            elif [[ "$v1_sfx" < "$v2_sfx" ]]; then
                return 0
            else
                return 1
            fi
        else
            if printf '%s\n' "$v1_num" "$v2_num" | sort -V | head -n1 | grep -qx "$v1_num"; then
                return 0
            else
                return 1
            fi
        fi
    }

    if compare_versions "$VERSION" "$REMOTE_VERSION"; then
        print_message "ACTION" "$(t upd_new_avail) ${BOLD}${REMOTE_VERSION}${RESET}."
        ui_confirm confirm_update "$(t upd_confirm)"
        echo ""

        if [[ "${confirm_update,,}" != "y" ]]; then
            print_message "WARN" "$(t upd_cancelled)"
            read -rp "$(t press_enter)"
            return
        fi
    else
        print_message "INFO" "$(t upd_latest)"
        read -rp "$(t press_enter)"
        return
    fi

    local TEMP_SCRIPT_PATH="${INSTALL_DIR}/backup-restore.sh.tmp"
    print_message "INFO" "$(t upd_downloading)"
    if ! curl -fsSL "$SCRIPT_REPO_URL" -o "$TEMP_SCRIPT_PATH"; then
        print_message "ERROR" "$(t upd_download_fail)"
        read -rp "$(t press_enter)"
        return
    fi

    if [[ ! -s "$TEMP_SCRIPT_PATH" ]] || ! head -n 1 "$TEMP_SCRIPT_PATH" | grep -q -e '^#!.*bash'; then
        print_message "ERROR" "$(t upd_invalid_file)"
        rm -f "$TEMP_SCRIPT_PATH"
        read -rp "$(t press_enter)"
        return
    fi

    download_translations

    print_message "INFO" "$(t upd_rm_old_bak)"
    find "$(dirname "$SCRIPT_PATH")" -maxdepth 1 -name "${SCRIPT_NAME}.bak.*" -type f -delete
    echo ""

    local BACKUP_PATH_SCRIPT="${SCRIPT_PATH}.bak.$(date +%s)"
    print_message "INFO" "$(t upd_creating_bak)"
    cp "$SCRIPT_PATH" "$BACKUP_PATH_SCRIPT" || {
        echo -e "${RED}❌ $(t upd_bak_fail)${RESET}"
        rm -f "$TEMP_SCRIPT_PATH"
        read -rp "$(t press_enter)"
        return
    }
    echo ""

    mv "$TEMP_SCRIPT_PATH" "$SCRIPT_PATH" || {
        echo -e "${RED}❌ $(t upd_move_fail)${RESET}"
        echo -e "${YELLOW}⚠️ $(t upd_restoring_bak)${RESET}"
        mv "$BACKUP_PATH_SCRIPT" "$SCRIPT_PATH"
        rm -f "$TEMP_SCRIPT_PATH"
        read -rp "$(t press_enter)"
        return
    }

    chmod +x "$SCRIPT_PATH"
    print_message "SUCCESS" "$(t upd_done) ${BOLD}${GREEN}${REMOTE_VERSION}${RESET}."
    echo ""
    print_message "INFO" "$(t upd_restart)"
    read -rp "$(t press_enter_restart)"
    exec "$SCRIPT_PATH" "$@"
    exit 0
}

remove_script() {
    print_message "WARN" "${YELLOW}$(t rm_warn)${RESET}"
    echo  " - $(t rm_script)"
    echo  " - $(t rm_dir)"
    echo  " - $(t rm_symlink)"
    echo  " - $(t rm_cron)"
    echo ""
    ui_confirm confirm "$(t rm_confirm)"
    echo ""
    
    if [[ "${confirm,,}" != "y" ]]; then
    print_message "WARN" "$(t rm_cancelled)"
    read -rp "$(t press_enter)"
    return
    fi

    if [[ "$EUID" -ne 0 ]]; then
        print_message "WARN" "$(t rm_root) ${BOLD}sudo${RESET}."
        read -rp "$(t press_enter)"
        return
    fi

    local keep_backups="n"
    if [[ -d "$BACKUP_DIR" ]] && compgen -G "$BACKUP_DIR"/* > /dev/null 2>&1; then
        ui_confirm keep_backups "$(t rm_keep_backups_q)"
        echo ""
        if [[ "${keep_backups,,}" == "y" ]]; then
            local saved_backups_dir="/opt/rw-backup-restore-saved"
            mkdir -p "$saved_backups_dir"
            if mv "$BACKUP_DIR"/* "$saved_backups_dir"/ 2>/dev/null; then
                print_message "SUCCESS" "$(t rm_backups_saved) ${BOLD}${saved_backups_dir}${RESET}"
            else
                print_message "WARN" "$(t rm_backups_save_fail)"
            fi
            echo ""
        fi
    fi

    print_message "INFO" "$(t rm_cron_removing)"
    if crontab -l 2>/dev/null | grep -qF "$SCRIPT_PATH backup"; then
        (crontab -l 2>/dev/null | grep -vF "$SCRIPT_PATH backup") | crontab -
        print_message "SUCCESS" "$(t rm_cron_removed)"
    else
        print_message "INFO" "$(t rm_cron_none)"
    fi
    echo ""

    print_message "INFO" "$(t rm_symlink_removing)"
    if [[ -L "$SYMLINK_PATH" ]]; then
        rm -f "$SYMLINK_PATH" && print_message "SUCCESS" "$(t rm_symlink_removed) ${BOLD}${SYMLINK_PATH}${RESET}" || print_message "WARN" "$(t rm_symlink_fail) ${BOLD}${SYMLINK_PATH}${RESET}"
    elif [[ -e "$SYMLINK_PATH" ]]; then
        print_message "WARN" "${BOLD}${SYMLINK_PATH}${RESET} $(t rm_symlink_not_link)"
    else
        print_message "INFO" "$(t rm_symlink_none) ${BOLD}${SYMLINK_PATH}${RESET}"
    fi
    echo ""

    print_message "INFO" "$(t rm_dir_removing)"
    if [[ -d "$INSTALL_DIR" ]]; then
        rm -rf "$INSTALL_DIR" && print_message "SUCCESS" "${BOLD}${INSTALL_DIR}${RESET} $(t rm_dir_removed)" || echo -e "${RED}❌ $(t rm_dir_fail)${RESET}"
    else
        print_message "INFO" "$(t rm_dir_none) ${BOLD}${INSTALL_DIR}${RESET}"
    fi

    if [[ "${keep_backups,,}" == "y" ]]; then
        echo ""
        print_message "SUCCESS" "$(t rm_backups_reminder_title)"
        echo -e "${BOLD}/opt/rw-backup-restore-saved${RESET}"
        echo ""
        echo "$(t rm_backups_reminder_howto)"
    fi

    exit 0
}

configure_upload_method() {
    while true; do
        clear
        echo -e "${GREEN}${BOLD}$(t ul_title)${RESET}"
        echo ""
        local cur_method cur_mark
        case "$UPLOAD_METHOD" in
            s3) cur_method="$(printf "$(t sum_upload_s3)" "$(_s3_configured_nums | wc -l)")" ;;

            *) cur_method="Telegram" ;;
        esac
        print_message "INFO" "$(t ul_current) ${BOLD}${cur_method}${RESET}"
        echo -e "   ${LIGHT_GRAY}$(t ul_tg_note)${RESET}"
        echo ""
        cur_mark=" ${GREEN}✓ $(t ul_current_mark)${RESET}"
        ui_menu_reset
        ui_menu_add 1 "$(t ul_set_tg)$([[ "$UPLOAD_METHOD" == "telegram" ]] && echo "$cur_mark")"
        ui_menu_add 2 "$(t ul_set_s3)$([[ "$UPLOAD_METHOD" == "s3" ]] && echo "$cur_mark")"
        ui_menu_gap
        ui_menu_add 3 "$(t st_s3_settings)"
        ui_menu_add 4 "$(t st_retention_settings)"
        ui_menu_gap
        ui_menu_add 0 "$(t back)"
        ui_menu_choose choice
        echo ""

        case $choice in
            3) s3_settings_menu; continue ;;
            4) settings_retention; continue ;;
            1)
                UPLOAD_METHOD="telegram"
                save_config
                print_message "SUCCESS" "$(t ul_tg_set)"
                if [[ -z "$BOT_TOKEN" || -z "$CHAT_ID" ]]; then
                    print_message "ACTION" "$(t ul_tg_enter)"
                    echo ""
                    print_message "INFO" "$(t cfg_create_bot) ${CYAN}@BotFather${RESET}"
                    ui_input BOT_TOKEN "$(t ul_enter_token)" "123456789:AAH..."
                    echo ""
                    print_message "INFO" "$(t ul_tg_id_help) ${CYAN}@userinfobot${RESET}"
                    ui_input CHAT_ID "$(t ul_enter_tg_id)" "-1001234567890"
                    save_config
                    print_message "SUCCESS" "$(t ul_tg_saved)"
                fi
                ;;
            2)
                if ! install_aws_cli; then
                    print_message "WARN" "$(t ul_s3_aws_needed)"
                    echo ""
                    read -rp "$(t press_enter)"
                    continue
                fi
                
                UPLOAD_METHOD="s3"
                print_message "SUCCESS" "$(t ul_s3_set)"
                
                local s3_setup_successful=true

                if [[ -z "$S3_BUCKET" || -z "$S3_ACCESS_KEY" || -z "$S3_SECRET_KEY" ]]; then
                    print_message "ACTION" "$(t ul_s3_enter)"
                    echo ""
                    ui_input S3_ENDPOINT "$(t ul_s3_enter_endpoint)" "https://s3.example.com"
                    ui_input S3_REGION "$(t ul_s3_enter_region)"
                    S3_REGION="${S3_REGION:-us-east-1}"
                    ui_input S3_BUCKET "$(t ul_s3_enter_bucket)" "rw-backups"
                    ui_input S3_ACCESS_KEY "$(t ul_s3_enter_access)"
                    ui_input S3_SECRET_KEY "$(t ul_s3_enter_secret)"
                    echo ""
                    echo "   $(t ul_s3_prefix_info1)"
                    echo "   $(t ul_s3_prefix_info2)"
                    ui_input S3_PREFIX "$(t ul_s3_enter_prefix)" "server-1"
                    echo ""
                    print_message "INFO" "$(t ul_s3_retain_info)"
                    ui_input input_s3_retain "$(printf "$(t ul_s3_enter_retain)" "$S3_RETAIN_DAYS")"
                    S3_RETAIN_DAYS="${input_s3_retain:-$S3_RETAIN_DAYS}"
                    
                    if [[ -z "$S3_ACCESS_KEY" || -z "$S3_SECRET_KEY" || -z "$S3_BUCKET" ]]; then
                        print_message "ERROR" "$(t ul_s3_fail)"
                        print_message "WARN" "$(t ul_s3_not_done)"
                        UPLOAD_METHOD="telegram"
                        s3_setup_successful=false
                    fi
                fi

                save_config

                if $s3_setup_successful; then
                    print_message "SUCCESS" "$(t ul_s3_saved)"
                else
                    print_message "SUCCESS" "$(t ul_tg_set)"
                fi
                ;;
            0) break ;;
            *) print_message "ERROR" "$(t invalid_input_select)" ;;
        esac
        echo ""
        read -rp "$(t press_enter)"
    done
    echo ""
}

settings_telegram() {
    while true; do
        clear
        echo -e "${GREEN}${BOLD}$(t st_tg_title)${RESET}"
        echo ""
        local tg_token_shown="$(t not_set)"
        if [[ -n "$BOT_TOKEN" ]]; then
            local tg_token_tail="${BOT_TOKEN#*:}"
            tg_token_shown="${BOT_TOKEN%%:*}:****${tg_token_tail: -4}"
        fi
        print_message "INFO" "$(t st_tg_token) ${BOLD}${tg_token_shown}${RESET}"
        print_message "INFO" "$(t st_tg_chatid) ${BOLD}${CHAT_ID}${RESET}"
        print_message "INFO" "$(t st_tg_thread) ${BOLD}${TG_MESSAGE_THREAD_ID:-$(t not_set)}${RESET}"
        print_message "INFO" "$(t st_tg_proxy) ${BOLD}${TG_PROXY:-$(t not_set)}${RESET}"
        echo ""
        echo ""
        ui_menu_reset
        ui_menu_add 1 "$(t st_tg_change_token)"
        ui_menu_add 2 "$(t st_tg_change_id)"
        ui_menu_add 3 "$(t st_tg_change_thread)"
        ui_menu_add 4 "$(t st_tg_change_proxy)"
        ui_menu_add 5 "$(t st_tg_test_proxy)"
        ui_menu_add 6 "$(t st_tg_test_msg)"
        ui_menu_gap
        ui_menu_add 0 "$(t back)"
        ui_menu_choose telegram_choice
        echo ""

        case $telegram_choice in
            6)
                if [[ -z "$BOT_TOKEN" || -z "$CHAT_ID" ]]; then
                    print_message "ERROR" "$(t st_tg_test_msg_nocfg)"
                else
                    ui_spin_start "$(t st_tg_test_msg_sending)"
                    local tg_test_out
                    if tg_test_out=$(send_telegram_message "✅ $(t st_tg_test_msg_text)" "None" 2>&1); then
                        print_message "SUCCESS" "$(t st_tg_test_msg_ok)"
                    else
                        print_message "ERROR" "$(t st_tg_test_msg_fail)"
                        [[ -n "$tg_test_out" ]] && echo -e "$tg_test_out"
                    fi
                fi
                ;;
            1)
                print_message "INFO" "$(t cfg_create_bot)"
                ui_input NEW_BOT_TOKEN "$(t st_tg_enter_token)" "123456789:AAH..."
                BOT_TOKEN="$NEW_BOT_TOKEN"
                save_config
                print_message "SUCCESS" "$(t st_tg_token_ok)"
                ;;
            2)
                print_message "INFO" "$(t st_tg_chatid_desc)"
                echo -e "   $(t cfg_chatid_help)"
                ui_input NEW_CHAT_ID "$(t st_tg_enter_id)" "-1001234567890"
                CHAT_ID="$NEW_CHAT_ID"
                save_config
                print_message "SUCCESS" "$(t st_tg_id_ok)"
                ;;
            3)
                print_message "INFO" "$(t st_tg_thread_info)"
                echo -e "   $(t cfg_thread_empty)"
                ui_input NEW_TG_MESSAGE_THREAD_ID "$(t st_tg_enter_thread)"
                TG_MESSAGE_THREAD_ID="$NEW_TG_MESSAGE_THREAD_ID"
                save_config
                print_message "SUCCESS" "$(t st_tg_thread_ok)"
                ;;
            4)
                print_message "INFO" "$(t st_tg_proxy_info)"
                print_message "INFO" "$(t st_tg_proxy_examples)"
                echo ""
                ui_input NEW_TG_PROXY "$(t st_tg_enter_proxy)"
                TG_PROXY="$NEW_TG_PROXY"
                save_config
                if [[ -n "$TG_PROXY" ]]; then
                    print_message "SUCCESS" "$(t st_tg_proxy_ok)"
                else
                    print_message "SUCCESS" "$(t st_tg_proxy_cleared)"
                fi
                ;;
            5)
                if [[ -z "$TG_PROXY" ]]; then
                    print_message "ERROR" "$(t st_tg_proxy_not_set)"
                else
                    print_message "INFO" "$(t st_tg_proxy_testing)"
                    local max_attempts=3
                    local attempt=1
                    local success=false
                    while [[ $attempt -le $max_attempts ]]; do
                        print_message "INFO" "$(printf "$(t st_tg_proxy_attempt)" "$attempt" "$max_attempts")"
                        local start_time=$SECONDS
                        local curl_output curl_exit
                        if curl_output=$(curl -s --connect-timeout 10 --max-time 15 \
                            --proxy "$TG_PROXY" \
                            "https://api.telegram.org/bot$BOT_TOKEN/getMe" 2>&1); then
                            curl_exit=0
                        else
                            curl_exit=$?
                        fi
                        local elapsed=$((SECONDS - start_time))
                        if [[ $curl_exit -eq 0 && "$curl_output" == *'"ok":true'* ]]; then
                            print_message "SUCCESS" "$(printf "$(t st_tg_proxy_test_ok)" "$elapsed")"
                            success=true
                            break
                        else
                            print_message "ERROR" "$(printf "$(t st_tg_proxy_attempt_fail)" "$attempt" "$elapsed")"
                            case $curl_exit in
                                0)  echo -e "${YELLOW}Details: Connected, but Telegram did not confirm the bot token: ${curl_output}${RESET}" ;;
                                7)  echo -e "${YELLOW}Details: Could not connect to proxy (exit $curl_exit)${RESET}" ;;
                                28) echo -e "${YELLOW}Details: Connection timed out (exit $curl_exit)${RESET}" ;;
                                35) echo -e "${YELLOW}Details: SSL handshake failed (exit $curl_exit)${RESET}" ;;
                                *)  echo -e "${YELLOW}Details: curl error (exit $curl_exit): ${curl_output}${RESET}" ;;
                            esac
                            if [[ $attempt -lt $max_attempts ]]; then
                                sleep 5
                            fi
                        fi
                        ((attempt++)) || true
                    done
                    if [[ "$success" == "false" ]]; then
                        print_message "ERROR" "$(t st_tg_proxy_test_fail)"
                    fi
                fi
                ;;
            0) break ;;
            *) print_message "ERROR" "$(t invalid_input_select)" ;;
        esac
        echo ""
        read -rp "$(t press_enter)"
    done
}

settings_panel_db() {
    while true; do
        clear
        echo -e "${GREEN}${BOLD}$(t st_db_title)${RESET}"
        echo ""
        if [[ "$DB_CONNECTION_TYPE" == "external" ]]; then
            print_message "INFO" "$(t st_db_type) ${BOLD}${GREEN}$(t st_db_type_ext)${RESET}"
            print_message "INFO" "$(t st_db_host_label) ${BOLD}${DB_HOST:-$(t not_set)}${RESET}"
            print_message "INFO" "$(t st_db_port_label) ${BOLD}${DB_PORT}${RESET}"
            print_message "INFO" "$(t st_db_user_label) ${BOLD}${DB_USER}${RESET}"
            print_message "INFO" "$(t st_db_name_label) ${BOLD}${DB_NAME}${RESET}"
            print_message "INFO" "$(t st_db_ssl_label) ${BOLD}${DB_SSL_MODE}${RESET}"
            print_message "INFO" "$(t st_db_pgver_label) ${BOLD}${DB_POSTGRES_VERSION}${RESET}"
        else
            print_message "INFO" "$(t st_db_type) ${BOLD}${GREEN}$(t st_db_type_docker)${RESET} (remnawave-db)"
            print_message "INFO" "$(t st_db_user_label) ${BOLD}${DB_USER}${RESET}"
        fi
        echo ""
        ui_menu_reset
        ui_menu_add 1 "$(t st_db_change_type)"
        ui_menu_add 2 "$(t st_db_change_user)"
        if [[ "$DB_CONNECTION_TYPE" == "external" ]]; then
            ui_menu_add 3 "$(t st_db_ext_settings)"
            ui_menu_add 4 "$(t st_db_test)"
        fi
        ui_menu_gap
        ui_menu_add 0 "$(t back)"
        ui_menu_choose db_choice
        echo ""

        case $db_choice in
            1)
                echo "$(t st_db_select_type)"
                ui_menu_reset
                ui_menu_add 1 "$(t st_db_docker)"
                ui_menu_add 2 "$(t st_db_external)"
                ui_menu_gap
                ui_menu_add 0 "$(t back)"
                ui_menu_choose conn_type_choice
                case "$conn_type_choice" in
                    0) continue ;;
                    1)
                        DB_CONNECTION_TYPE="docker"
                        save_config
                        print_message "SUCCESS" "$(t st_db_switched_docker)"
                        ;;
                    2)
                        DB_CONNECTION_TYPE="external"
                        if [[ -z "$DB_HOST" ]]; then
                            echo ""
                            print_message "ACTION" "$(t st_db_need_ext_params)"
                            echo ""
                            ui_input DB_HOST "$(t rs_host)" "db.example.com"
                            ui_input input_db_port "$(t rs_port)"
                            DB_PORT="${input_db_port:-5432}"
                            ui_input input_db_name "$(t rs_dbname)"
                            DB_NAME="${input_db_name:-postgres}"
                            ui_secret DB_PASSWORD "$(t rs_pass)"
                            ui_input input_ssl "$(t rs_ssl)"
                            DB_SSL_MODE="${input_ssl:-prefer}"
                            ui_input input_pg_ver "$(t rs_pgver)"
                            DB_POSTGRES_VERSION="${input_pg_ver:-17}"
                        fi
                        save_config
                        print_message "SUCCESS" "$(t st_db_switched_ext)"
                        ;;
                    *)
                        print_message "ERROR" "$(t invalid_input)"
                        ;;
                esac
                ;;
            2)
                print_message "INFO" "$(t st_db_user_label) ${BOLD}${DB_USER}${RESET}"
                echo ""
                ui_input NEW_DB_USER "$(printf "$(t st_db_enter_user)" "$DB_USER")"
                DB_USER="${NEW_DB_USER:-postgres}"
                save_config
                print_message "SUCCESS" "$(t st_db_user_ok) ${BOLD}${DB_USER}${RESET}."
                ;;
            3)
                if [[ "$DB_CONNECTION_TYPE" != "external" ]]; then
                    print_message "ERROR" "$(t invalid_input)"
                else
                    clear
                    echo -e "${GREEN}${BOLD}$(t st_db_ext_settings)${RESET}"
                    echo ""
                    print_message "INFO" "$(t st_db_host_label) ${BOLD}${DB_HOST:-$(t not_set)}${RESET}"
                    print_message "INFO" "$(t st_db_port_label) ${BOLD}${DB_PORT}${RESET}"
                    print_message "INFO" "$(t st_db_name_label) ${BOLD}${DB_NAME}${RESET}"
                    print_message "INFO" "$(t st_db_ssl_label) ${BOLD}${DB_SSL_MODE}${RESET}"
                    print_message "INFO" "$(t st_db_pgver_label) ${BOLD}${DB_POSTGRES_VERSION}${RESET}"
                    echo ""
                    ui_input new_host "$(printf "$(t st_db_enter_host)" "$DB_HOST")"
                    [[ -n "$new_host" ]] && DB_HOST="$new_host"
                    ui_input new_port "$(printf "$(t st_db_enter_port)" "$DB_PORT")"
                    [[ -n "$new_port" ]] && DB_PORT="$new_port"
                    ui_input new_dbname "$(printf "$(t st_db_enter_name)" "$DB_NAME")"
                    [[ -n "$new_dbname" ]] && DB_NAME="$new_dbname"
                    ui_secret new_pass "$(t st_db_enter_pass)"
                    [[ -n "$new_pass" ]] && DB_PASSWORD="$new_pass"
                    ui_input new_ssl "$(printf "$(t st_db_enter_ssl)" "$DB_SSL_MODE")"
                    [[ -n "$new_ssl" ]] && DB_SSL_MODE="$new_ssl"
                    ui_input new_pgver "$(printf "$(t st_db_enter_pgver)" "$DB_POSTGRES_VERSION")"
                    [[ -n "$new_pgver" ]] && DB_POSTGRES_VERSION="$new_pgver"
                    
                    save_config
                    print_message "SUCCESS" "$(t st_db_ext_saved)"
                fi
                ;;
            4)
                if [[ "$DB_CONNECTION_TYPE" != "external" ]]; then
                    print_message "ERROR" "$(t st_db_only_ext)"
                else
                    print_message "INFO" "$(t st_db_testing) ${BOLD}${DB_HOST}:${DB_PORT}${RESET}..."
                    local pg_image=$(get_postgres_image)
                    
                    if docker run --rm --network host \
                        -e PGPASSWORD="$DB_PASSWORD" \
                        -e PGSSLMODE="$DB_SSL_MODE" \
                        "$pg_image" \
                        pg_isready -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" 2>/dev/null; then
                        print_message "SUCCESS" "$(t st_db_test_ok)"
                    else
                        print_message "ERROR" "$(t st_db_test_fail)"
                    fi
                fi
                ;;
            0) break ;;
            *) print_message "ERROR" "$(t invalid_input)" ;;
        esac
        echo ""
        read -rp "$(t press_enter)"
    done
}

settings_panel_path() {
    clear
    echo -e "${GREEN}${BOLD}$(t st_path_title)${RESET}"
    echo ""
    print_message "INFO" "$(t st_path_current) ${BOLD}${REMNALABS_ROOT_DIR}${RESET}"
    echo ""
    print_message "ACTION" "$(t st_path_select)"
    ui_menu_reset
    ui_menu_add 1 "/opt/remnawave"
    ui_menu_add 2 "/root/remnawave"
    ui_menu_add 3 "/opt/stacks/remnawave"
    ui_menu_add 4 "$(t custom_path)"
    ui_menu_gap
    ui_menu_add 0 "$(t back)"

    local new_remnawave_path_choice
    while true; do
        ui_menu_choose new_remnawave_path_choice
        case "$new_remnawave_path_choice" in
        1) REMNALABS_ROOT_DIR="/opt/remnawave"; break ;;
        2) REMNALABS_ROOT_DIR="/root/remnawave"; break ;;
        3) REMNALABS_ROOT_DIR="/opt/stacks/remnawave"; break ;;
        4) 
            echo ""
            print_message "INFO" "$(t st_path_enter)"
            ui_input new_custom_remnawave_path "$(t path_prompt)" "/opt/remnawave"
            if [[ -z "$new_custom_remnawave_path" ]]; then
                print_message "ERROR" "$(t cfg_path_empty)"
                echo ""
                read -rp "$(t press_enter)"
                continue
            fi

            if [[ ! "$new_custom_remnawave_path" = /* ]]; then
                print_message "ERROR" "$(t cfg_path_abs)"
                echo ""
                read -rp "$(t press_enter)"
                continue
            fi

            new_custom_remnawave_path="${new_custom_remnawave_path%/}"

            if [[ ! -d "$new_custom_remnawave_path" ]]; then
                print_message "WARN" "$(t st_path_missing) ${BOLD}${new_custom_remnawave_path}${RESET}"
                ui_confirm confirm_new_custom_path "$(t st_path_continue)"
                if [[ "$confirm_new_custom_path" != "y" ]]; then
                    echo ""
                    read -rp "$(t press_enter)"
                    continue
                fi
            fi

            REMNALABS_ROOT_DIR="$new_custom_remnawave_path"
            print_message "SUCCESS" "$(t st_path_set) ${BOLD}${REMNALABS_ROOT_DIR}${RESET}"
            break 
            ;;
        0) 
            return
            ;;
        *) print_message "ERROR" "$(t invalid_input)" ;;
        esac
    done
    save_config
    print_message "SUCCESS" "$(t st_path_ok) ${BOLD}${REMNALABS_ROOT_DIR}${RESET}."
    echo ""
    read -rp "$(t press_enter)"
}

settings_retention() {
    clear
    echo -e "${GREEN}${BOLD}$(t st_retention_title)${RESET}"
    echo ""
    print_message "INFO" "$(t st_retention_local) ${BOLD}$(_retention_display "$RETAIN_BACKUPS_VALUE" "$RETAIN_BACKUPS_UNIT")${RESET}"

    local -a ret_s3_nums=()
    while IFS= read -r ret_s3_num; do
        local ret_s3_chk_bucket=$(_s3_var BUCKET "$ret_s3_num")
        local ret_s3_chk_access=$(_s3_var ACCESS_KEY "$ret_s3_num")
        local ret_s3_chk_secret=$(_s3_var SECRET_KEY "$ret_s3_num")
        if [[ -z "$ret_s3_chk_bucket" || -z "$ret_s3_chk_access" || -z "$ret_s3_chk_secret" ]]; then
            continue
        fi
        ret_s3_nums+=("$ret_s3_num")
        local ret_s3_lbl=$(_s3_label "$ret_s3_num")
        local ret_s3_days=$(_s3_var RETAIN_DAYS "$ret_s3_num")
        print_message "INFO" "$(t st_retention_s3) ${BOLD}$(_retention_display "$ret_s3_days" "$(t st_retention_days)")${RESET} (${ret_s3_lbl})"
    done < <(_s3_configured_nums)

    echo ""
    ui_menu_reset
    ui_menu_add 1 "$(t st_retention_change_local)"
    ui_menu_add 2 "$(t st_retention_change_s3)"
    ui_menu_gap
    ui_menu_add 0 "$(t back)"
    ui_menu_choose ret_choice
    echo ""

    case $ret_choice in
        1)
            ui_menu_reset
            ui_menu_add 1 "$(t st_retention_days)"
            ui_menu_add 2 "$(t st_retention_hours)"
            ui_menu_gap
            ui_menu_add 0 "$(t back)"
            ui_menu_choose unit_choice
            case $unit_choice in
                0) return ;;
                1) RETAIN_BACKUPS_UNIT="days" ;;
                2) RETAIN_BACKUPS_UNIT="hours" ;;
            esac
            echo "   $(t st_retention_disable_hint)"
            ui_input new_local_ret "$(printf "$(t st_retention_enter_local)" "$RETAIN_BACKUPS_VALUE")"
            RETAIN_BACKUPS_VALUE="${new_local_ret:-$RETAIN_BACKUPS_VALUE}"
            save_config
            print_message "SUCCESS" "$(t st_retention_local_ok) ${BOLD}$(_retention_display "$RETAIN_BACKUPS_VALUE" "$RETAIN_BACKUPS_UNIT")${RESET}"
            ;;

        2)
            local ret_target_num=""
            if [[ "${#ret_s3_nums[@]}" -gt 1 ]]; then
                echo "   $(t st_retention_pick_s3)"
                local ri=0
                local ret_pick_num
                ui_menu_reset
                for ret_pick_num in "${ret_s3_nums[@]}"; do
                    ri=$((ri + 1))
                    ui_menu_add "$ri" "$(_s3_label "$ret_pick_num")"
                done
                ui_menu_gap
                ui_menu_add 0 "$(t back)"
                local ret_pick_choice
                ui_menu_choose ret_pick_choice
                if [[ "$ret_pick_choice" =~ ^[0-9]+$ ]] && [[ "$ret_pick_choice" -ge 1 ]] && [[ "$ret_pick_choice" -le "${#ret_s3_nums[@]}" ]]; then
                    ret_target_num="${ret_s3_nums[$((ret_pick_choice - 1))]}"
                else
                    return
                fi
            elif [[ "${#ret_s3_nums[@]}" -eq 1 ]]; then
                ret_target_num="${ret_s3_nums[0]}"
            fi

            local ret_target_days
            ret_target_days=$(_s3_var RETAIN_DAYS "$ret_target_num")
            echo "   $(t st_retention_disable_hint)"
            ui_input new_s3_ret "$(printf "$(t st_retention_enter_s3)" "$ret_target_days")"
            _s3_set RETAIN_DAYS "$ret_target_num" "${new_s3_ret:-$ret_target_days}"
            save_config
            print_message "SUCCESS" "$(t st_retention_s3_ok) ${BOLD}$(_retention_display "$(_s3_var RETAIN_DAYS "$ret_target_num")" "$(t st_retention_days)")${RESET} ($(_s3_label "$ret_target_num"))"
            ;;
        0) return ;;
        *) print_message "ERROR" "$(t invalid_input_select)" ;;
    esac
    unset ret_s3_nums
    echo ""
    read -rp "$(t press_enter)"
}

settings_language() {
    clear
    echo -e "${GREEN}${BOLD}$(t st_lang)${RESET}"
    echo ""
    print_message "INFO" "$(t st_lang_current) ${BOLD}${LANG_CODE}${RESET}"
    echo ""
    select_language_interactive
    save_config
    print_message "SUCCESS" "$(t st_lang_changed) ${BOLD}${LANG_CODE}${RESET}"
    echo ""
    read -rp "$(t press_enter)"
}

settings_autoupdate() {
    clear
    echo -e "${GREEN}${BOLD}$(t st_auto_update)${RESET}"
    echo ""
    if [[ "$AUTO_UPDATE" == "true" ]]; then
        print_message "INFO" "$(t st_auto_update_status) ${BOLD}${GREEN}$(t st_auto_update_on)${RESET}"
    else
        print_message "INFO" "$(t st_auto_update_status) ${BOLD}${RED}$(t st_auto_update_off)${RESET}"
    fi
    echo ""
    ui_menu_reset
    ui_menu_add 1 "$(t st_auto_update_enable)"
    ui_menu_add 2 "$(t st_auto_update_disable)"
    ui_menu_gap
    ui_menu_add 0 "$(t back)"
    ui_menu_choose auto_upd_choice
    echo ""
    case $auto_upd_choice in
        1)
            AUTO_UPDATE="true"
            save_config
            print_message "SUCCESS" "$(t st_auto_update_enabled)"
            ;;
        2)
            AUTO_UPDATE="false"
            save_config
            print_message "SUCCESS" "$(t st_auto_update_disabled)"
            ;;
        0) return ;;
        *) print_message "ERROR" "$(t invalid_input_select)" ;;
    esac
    echo ""
    read -rp "$(t press_enter)"
}

configure_settings() {
    while true; do
        clear
        echo -e "${GREEN}${BOLD}$(t st_title)${RESET}"
        echo ""
        ui_menu_reset
        ui_menu_add 1 "$(t st_tg_settings)"
        ui_menu_add 2 "$(t enc_title)"
        ui_menu_add 3 "$(t st_lang)"
        ui_menu_add 4 "$(t st_auto_update)"
        ui_menu_gap
        ui_menu_add 0 "$(t back)"
        ui_menu_choose choice
        echo ""
        case $choice in
            1) settings_telegram ;;
            2) configure_encryption ;;
            3) settings_language ;;
            4) settings_autoupdate ;;
            0) break ;;
        esac
    done
}

menu_what_to_backup() {
    while true; do
        clear
        echo -e "${GREEN}${BOLD}$(t wb_title)${RESET}"
        echo ""
        if [[ "$SKIP_PANEL_BACKUP" == "true" ]]; then
            print_message "INFO" "$(t wb_panel) ${BOLD}${YELLOW}$(t wb_panel_off)${RESET}"
        else
            print_message "INFO" "$(t wb_panel) ${BOLD}${GREEN}$(t wb_on)${RESET} · ${REMNALABS_ROOT_DIR:-$(t not_set)}"
            if [[ "$DB_CONNECTION_TYPE" == "external" ]]; then
                print_message "INFO" "$(t wb_panel_db) ${BOLD}$(printf "$(t sum_db_ext)" "${DB_HOST}:${DB_PORT}")${RESET}"
            else
                print_message "INFO" "$(t wb_panel_db) ${BOLD}$(t sum_db_docker)${RESET}"
            fi
        fi
        if [[ "$BOT_BACKUP_ENABLED" == "true" ]]; then
            print_message "INFO" "$(t wb_bot) ${BOLD}${GREEN}${BOT_BACKUP_SELECTED}${RESET} · ${BOT_BACKUP_PATH}"
        else
            print_message "INFO" "$(t wb_bot) ${BOLD}$(t sum_bot_off)${RESET}"
        fi
        echo ""
        ui_menu_reset
        ui_menu_add 1 "$(t wb_panel_path)"
        ui_menu_add 2 "$(t wb_panel_db_settings)"
        ui_menu_add 3 "$(t wb_bot_settings)"
        ui_menu_gap
        ui_menu_add 0 "$(t back)"
        ui_menu_choose choice
        echo ""
        case $choice in
            1) settings_panel_path ;;
            2) settings_panel_db ;;
            3) configure_bot_backup ;;
            0) break ;;
        esac
    done
}

show_logs() {
    while true; do
        clear
        echo -e "${GREEN}${BOLD}$(t lg_title)${RESET}"
        echo ""
        print_message "INFO" "$(t lg_dir) ${BOLD}${LOG_DIR}${RESET}"
        echo ""
        ui_menu_reset
        ui_menu_add 1 "$(t lg_backup)"
        ui_menu_add 2 "$(t lg_restore)"
        ui_menu_add 3 "$(t lg_system)"
        ui_menu_add 4 "$(t lg_errors)"
        ui_menu_add 5 "$(t lg_cron)"
        ui_menu_gap
        ui_menu_add 0 "$(t back)"
        local lg_choice lg_file=""
        ui_menu_choose lg_choice
        echo ""
        case "$lg_choice" in
            1) lg_file="backup.log" ;;
            2) lg_file="restore.log" ;;
            3) lg_file="system.log" ;;
            4) lg_file="error.log" ;;
            5) lg_file="cron.log" ;;
            0) return ;;
            *) print_message "ERROR" "$(t invalid_input_select)"; read -rp "$(t press_enter)"; continue ;;
        esac
        clear
        echo -e "${GREEN}${BOLD}${LOG_DIR}/${lg_file}${RESET}"
        echo ""
        if [[ -s "$LOG_DIR/$lg_file" ]]; then
            tail -n 100 "$LOG_DIR/$lg_file" | sed \
                -e "s/\[ERROR\]/${RED}[ERROR]${RESET}/" \
                -e "s/\[WARN\]/${YELLOW}[WARN]${RESET}/" \
                -e "s/\[SUCCESS\]/${GREEN}[SUCCESS]${RESET}/"
            echo ""
            print_message "INFO" "$(t lg_last_lines)"
        else
            print_message "INFO" "$(t lg_empty)"
        fi
        echo ""
        read -rp "$(t press_enter)"
    done
}

migrate_cron_log_path() {
    command -v crontab &> /dev/null || return 0
    local current
    current=$(crontab -l 2>/dev/null) || return 0
    echo "$current" | grep -qF "/var/log/rw_backup_cron.log" || return 0
    mkdir -p "$LOG_DIR" 2>/dev/null && chmod 700 "$LOG_DIR" 2>/dev/null
    echo "$current" | sed "s#/var/log/rw_backup_cron.log#${LOG_DIR}/cron.log#g" | crontab - 2>/dev/null || return 0
    log_write "INFO" "cron entries migrated to ${LOG_DIR}/cron.log"
    return 0
}

check_update_status() {
    local TEMP_REMOTE_VERSION_FILE
    TEMP_REMOTE_VERSION_FILE=$(mktemp)

    if ! curl -fsSL "$SCRIPT_REPO_URL" 2>/dev/null | head -n 100 > "$TEMP_REMOTE_VERSION_FILE"; then
        UPDATE_AVAILABLE=false
        rm -f "$TEMP_REMOTE_VERSION_FILE"
        return
    fi

    local REMOTE_VERSION
    REMOTE_VERSION=$(grep -m 1 "^VERSION=" "$TEMP_REMOTE_VERSION_FILE" | cut -d'"' -f2)
    UPDATE_REMOTE_VERSION="$REMOTE_VERSION"
    rm -f "$TEMP_REMOTE_VERSION_FILE"

    if [[ -z "$REMOTE_VERSION" ]]; then
        UPDATE_AVAILABLE=false
        return
    fi

    compare_versions_for_check() {
        local v1="$1"
        local v2="$2"

        local v1_num="${v1//[^0-9.]/}"
        local v2_num="${v2//[^0-9.]/}"

        local v1_sfx="${v1//$v1_num/}"
        local v2_sfx="${v2//$v2_num/}"

        if [[ "$v1_num" == "$v2_num" ]]; then
            if [[ -z "$v1_sfx" && -n "$v2_sfx" ]]; then
                return 0
            elif [[ -n "$v1_sfx" && -z "$v2_sfx" ]]; then
                return 1
            elif [[ "$v1_sfx" < "$v2_sfx" ]]; then
                return 0
            else
                return 1
            fi
        else
            if printf '%s\n' "$v1_num" "$v2_num" | sort -V | head -n1 | grep -qx "$v1_num"; then
                return 0
            else
                return 1
            fi
        fi
    }

    if compare_versions_for_check "$VERSION" "$REMOTE_VERSION"; then
        UPDATE_AVAILABLE=true
    else
        UPDATE_AVAILABLE=false
    fi
}

_ui_human_size() {
    local bytes="$1" units
    if [[ "$LANG_CODE" == "en" ]]; then units="B KB MB GB TB"; else units="Б КБ МБ ГБ ТБ"; fi
    awk -v b="$bytes" -v u="$units" -v ru="$([[ "$LANG_CODE" == "en" ]] && echo 0 || echo 1)" 'BEGIN{
        split(u, n, " "); i = 1
        while (b >= 1024 && i < 5) { b /= 1024; i++ }
        s = (i == 1) ? sprintf("%d %s", b, n[i]) : sprintf("%.1f %s", b, n[i])
        sub(/\.0 /, " ", s)
        if (ru) gsub(/\./, ",", s)
        print s
    }'
}

_ui_strip() {
    sed $'s/\x1b\\[[0-9;]*m//g' <<< "$1"
}

_ui_status_card() {
    local LC_ALL=C.UTF-8
    local title="$1"; shift
    local title_plain lw=0 vw=0 i j label plain inner cols hr="" pad
    title_plain=$(_ui_strip "$title")
    for ((i = 1; i <= $#; i += 2)); do
        j=$((i + 1))
        label="${!i}"
        plain=$(_ui_strip "${!j}")
        (( ${#label} > lw )) && lw=${#label}
        (( ${#plain} > vw )) && vw=${#plain}
    done
    inner=$(( lw + 3 + vw ))
    (( ${#title_plain} > inner )) && inner=${#title_plain}
    cols=$(tput cols 2>/dev/null || echo 80)

    if (( inner + 6 > cols )); then
        echo -e "  ${title/  /${RESET}\\n  }${RESET}"
        echo ""
        for ((i = 1; i <= $#; i += 2)); do
            j=$((i + 1)); label="${!i}"
            echo -e "  ${LIGHT_GRAY}${label}${RESET}$(printf '%*s' $((lw - ${#label} + 3)) '')${!j}${RESET}"
        done
        return 0
    fi

    for ((i = 0; i < inner + 4; i++)); do hr+="─"; done
    echo -e "${GREEN}╭${hr}╮${RESET}"
    echo -e "${GREEN}│${RESET}  ${title}${RESET}$(printf '%*s' $((inner - ${#title_plain} + 2)) '')${GREEN}│${RESET}"
    echo -e "${GREEN}├${hr}┤${RESET}"
    for ((i = 1; i <= $#; i += 2)); do
        j=$((i + 1)); label="${!i}"
        plain=$(_ui_strip "${!j}")
        pad=$(( inner - lw - 3 - ${#plain} + 2 ))
        echo -e "${GREEN}│${RESET}  ${LIGHT_GRAY}${label}${RESET}$(printf '%*s' $((lw - ${#label} + 3)) '')${!j}${RESET}$(printf '%*s' "$pad" '')${GREEN}│${RESET}"
    done
    echo -e "${GREEN}╰${hr}╯${RESET}"
}

show_status_card() {
    local title title_main title_by db_val last_val sched_val enc_val up_val bot_val newest

    title_main="$(t menu_title)"
    title_by=""
    if [[ "$title_main" == *" by "* ]]; then
        title_by="${title_main##* by }"
        title_main="${title_main% by *}"
        title_by="by ${title_by} · "
    fi
    title="${GREEN}${BOLD}${title_main}${RESET}  ${LIGHT_GRAY}${title_by}v${VERSION}${RESET}"

    if [[ "$DB_CONNECTION_TYPE" == "external" ]]; then
        db_val="${BOLD}$(printf "$(t sum_db_ext)" "${DB_HOST}:${DB_PORT}")"
    else
        db_val="${BOLD}$(t sum_db_docker)"
    fi

    newest=$(find "$BACKUP_DIR" -maxdepth 1 \( -name "remnawave_backup_*.tar.gz" -o -name "remnawave_backup_*.tar.gz.age" \) -printf "%T@ %s %p\n" 2>/dev/null | sort -nr | head -1)
    if [[ -n "$newest" ]]; then
        local ts size
        ts=${newest%%.*}
        size=$(awk '{print $2}' <<< "$newest")
        last_val="${BOLD}$(date -d "@$ts" '+%d.%m.%Y %H:%M') · $(_ui_human_size "$size")"
    else
        last_val="${YELLOW}$(t sum_none)"
    fi

    if [[ -n "$CRON_TIMES" ]]; then
        sched_val="${BOLD}$(printf "$(t sum_schedule_utc)" "$CRON_TIMES")"
    else
        sched_val="${YELLOW}$(t sum_schedule_off)"
    fi

    if [[ "$ENCRYPT_ENABLED" == "true" ]]; then
        enc_val="${BOLD}$(t sum_enc_on)"
    else
        enc_val="$(t sum_enc_off)"
    fi

    case "$UPLOAD_METHOD" in
        s3) up_val="${BOLD}$(printf "$(t sum_upload_s3)" "$(_s3_configured_nums | wc -l)")" ;;

        *) up_val="${BOLD}$(t sum_upload_tg)" ;;
    esac

    if [[ "$BOT_BACKUP_ENABLED" == "true" && -n "$BOT_BACKUP_SELECTED" ]]; then
        bot_val="${BOLD}${BOT_BACKUP_SELECTED}"
    else
        bot_val="$(t sum_bot_off)"
    fi

    local -a rows=(
        "$(t sum_db)" "$db_val"
        "$(t sum_last_backup)" "$last_val"
        "$(t sum_schedule)" "$sched_val"
        "$(t sum_encryption)" "$enc_val"
        "$(t sum_upload)" "$up_val"
        "$(t sum_bot)" "$bot_val"
    )
    local du used total s3_num s3_bytes s3_limit
    du=$(_disk_usage)
    if [[ -n "$du" ]]; then
        read -r used total <<< "$du"
        rows+=("$(t usage_disk)" "$(_usage_color "$used" "$total")$(_usage_text "$used" "$total")")
    fi
    if [[ "$UPLOAD_METHOD" == "s3" ]]; then
        while IFS= read -r s3_num; do
            s3_bytes=$(_s3_cached_usage "$s3_num")
            s3_limit=$(_s3_limit_bytes "$s3_num")
            if [[ -n "$s3_bytes" ]]; then
                rows+=("$(_s3_label "$s3_num")" "$(_usage_color "$s3_bytes" "$s3_limit")$(_usage_text "$s3_bytes" "$s3_limit")")
            elif [[ -n "$s3_limit" ]]; then
                rows+=("$(_s3_label "$s3_num")" "${LIGHT_GRAY}$(printf "$(t usage_no_data_limit)" "$(_ui_human_size "$s3_limit")")")
            else
                rows+=("$(_s3_label "$s3_num")" "${LIGHT_GRAY}$(t usage_no_data)")
            fi
        done < <(_s3_configured_nums)
    fi

    if [[ "$UPDATE_AVAILABLE" == true ]]; then
        rows+=("$(t sum_update)" "${YELLOW}● $(printf "$(t sum_update_avail)" "${UPDATE_REMOTE_VERSION:-?}")")
    fi
    _ui_status_card "$title" "${rows[@]}"
}

main_menu() {
    while true; do
        LOG_CATEGORY="system"
        check_update_status
        clear

        show_status_card
        echo ""

        ui_menu_reset
        ui_menu_add 1 "$(t menu_create_backup)" primary
        ui_menu_add 2 "$(t menu_restore)" primary
        ui_menu_gap
        ui_menu_add 3 "$(t menu_what)"
        ui_menu_add 4 "$(t menu_where)"
        ui_menu_add 5 "$(t menu_schedule)"
        ui_menu_add 6 "$(t menu_settings)"
        ui_menu_add 7 "$(t menu_logs)"
        ui_menu_gap
        ui_menu_add 8 "$(t menu_update)" warn
        ui_menu_add 9 "$(t menu_remove)" danger
        ui_menu_gap
        ui_menu_add 0 "$(t exit)"
        ui_menu_footer "$(t menu_shortcut)"
        ui_menu_footer "$(t menu_docs)"
        ui_menu_choose choice "${choice:-}"
        echo ""
        case $choice in
            1) create_backup ; read -rp "$(t press_enter)" ;;
            2) restore_backup ;;
            3) menu_what_to_backup ;;
            4) configure_upload_method ;;
            5) setup_auto_send ;;
            6) configure_settings ;;
            7) show_logs ;;
            8) update_script ;;
            9) remove_script ;;
            0) echo "$(t exit_dots)"; exit 0 ;;
            *) print_message "ERROR" "$(t invalid_input_select)" ; read -rp "$(t press_enter)" ;;
        esac
    done
}

if ! command -v jq &> /dev/null; then
    print_message "INFO" "$(t jq_installing)"
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}❌ $(t jq_root)${RESET}"
        exit 1
    fi
    if command -v apt-get &> /dev/null; then
        apt-get update -qq > /dev/null 2>&1
        apt-get install -y jq > /dev/null 2>&1 || { echo -e "${RED}❌ $(t jq_fail)${RESET}"; exit 1; }
        print_message "SUCCESS" "$(t jq_installed)"
    else
        print_message "ERROR" "$(t jq_no_apt)"
        exit 1
    fi
fi

if [[ -z "$1" ]]; then
    load_or_create_config
    migrate_cron_log_path
    setup_symlink
    main_menu
elif [[ "$1" == "backup" ]]; then
    load_or_create_config
    migrate_cron_log_path
    create_backup
elif [[ "$1" == "restore" ]]; then
    load_or_create_config
    migrate_cron_log_path
    restore_backup
elif [[ "$1" == "update" ]]; then
    load_or_create_config
    update_script
elif [[ "$1" == "remove" ]]; then
    load_or_create_config
    remove_script
else
    echo -e "${RED}❌ $(t jq_bad_usage) ${BOLD}${0} [backup|restore|update|remove]${RESET}${RESET}"
    exit 1
fi
