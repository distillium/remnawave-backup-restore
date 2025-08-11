#!/bin/bash

set -e

INSTALL_DIR="/opt/rw-backup-restore"
BACKUP_DIR="$INSTALL_DIR/backup"
CONFIG_FILE="$INSTALL_DIR/config.env"
SCRIPT_NAME="backup-restore.sh"
SCRIPT_PATH="$INSTALL_DIR/$SCRIPT_NAME"
RETAIN_BACKUPS_DAYS=7
SYMLINK_PATH="/usr/local/bin/rw-backup"
REMNALABS_ROOT_DIR=""
ENV_NODE_FILE=".env-node"
ENV_FILE=".env"
SCRIPT_REPO_URL="https://raw.githubusercontent.com/distillium/remnawave-backup-restore/main/backup-restore.sh"
SCRIPT_RUN_PATH="$(realpath "$0")"
GD_CLIENT_ID=""
GD_CLIENT_SECRET=""
GD_REFRESH_TOKEN=""
GD_FOLDER_ID=""
UPLOAD_METHOD="telegram"
CRON_TIMES=""
TG_MESSAGE_THREAD_ID=""
UPDATE_AVAILABLE=false
VERSION="1.1.0"
ADDITIONAL_BACKUPS_ENABLED=false
ADDITIONAL_PATHS=""
ADDITIONAL_DB_CONTAINER=""
ADDITIONAL_DB_USER=""
ADDITIONAL_DB_NAME=""

if [[ -t 0 ]]; then
    RED=$'\e[31m'
    GREEN=$'\e[32m'
    YELLOW=$'\e[33m'
    GRAY=$'\e[37m'
    LIGHT_GRAY=$'\e[90m'
    CYAN=$'\e[36m'
    RESET=$'\e[0m'
    BOLD=$'\e[1m'
else
    RED=""
    GREEN=""
    YELLOW=""
    GRAY=""
    LIGHT_GRAY=""
    CYAN=""
    RESET=""
    BOLD=""
fi

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

    echo -e "${color_code}[$type]${RESET} $message"
}

setup_symlink() {
    echo ""
    if [[ "$EUID" -ne 0 ]]; then
        print_message "WARN" "Для управления символической ссылкой ${BOLD}${SYMLINK_PATH}${RESET} требуются права root. Пропускаем настройку."
        return 1
    fi

    if [[ -L "$SYMLINK_PATH" && "$(readlink -f "$SYMLINK_PATH")" == "$SCRIPT_PATH" ]]; then
        print_message "SUCCESS" "Символическая ссылка ${BOLD}${SYMLINK_PATH}${RESET} уже настроена и указывает на ${BOLD}${SCRIPT_PATH}${RESET}."
        return 0
    fi

    print_message "INFO" "Создание или обновление символической ссылки ${BOLD}${SYMLINK_PATH}${RESET}..."
    rm -f "$SYMLINK_PATH"
    if [[ -d "$(dirname "$SYMLINK_PATH")" ]]; then
        if ln -s "$SCRIPT_PATH" "$SYMLINK_PATH"; then
            print_message "SUCCESS" "Символическая ссылка ${BOLD}${SYMLINK_PATH}${RESET} успешно настроена."
        else
            print_message "ERROR" "Не удалось создать символическую ссылку ${BOLD}${SYMLINK_PATH}${RESET}. Проверьте права доступа."
            return 1
        fi
    else
        print_message "ERROR" "Каталог ${BOLD}$(dirname "$SYMLINK_PATH")${RESET} не найден. Символическая ссылка не создана."
        return 1
    fi
    echo ""
    return 0
}

install_dependencies() {
    print_message "INFO" "Проверка и установка необходимых пакетов..."
    echo ""

    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}❌ Ошибка: Этот скрипт требует прав root для установки зависимостей. Пожалуйста, запустите его с '${BOLD}sudo${RESET}' или от пользователя '${BOLD}root${RESET}'.${RESET}"
        exit 1
    fi

    if command -v apt-get &> /dev/null; then
        print_message "INFO" "Обновление списка пакетов ${BOLD}apt${RESET}..."
        apt-get update -qq > /dev/null 2>&1 || { echo -e "${RED}❌ Ошибка: Не удалось обновить список пакетов ${BOLD}apt${RESET}. Проверьте подключение к интернету.${RESET}"; exit 1; }
        apt-get install -y toilet figlet procps lsb-release whiptail curl gzip cron > /dev/null 2>&1 || { echo -e "${RED}❌ Ошибка: Не удалось установить необходимые пакеты. Проверьте ошибки установки.${RESET}"; exit 1; }
        print_message "SUCCESS" "Все необходимые пакеты установлены или уже присутствуют в системе."
    else
        print_message "WARN" "Внимание: Не удалось найти менеджер пакетов ${BOLD}'apt-get'${RESET}. Установка зависимостей может потребоваться вручную."
        command -v curl &> /dev/null || { echo -e "${RED}❌ Ошибка: ${BOLD}'curl'${RESET} не найден. Установите его вручную.${RESET}"; exit 1; }
        command -v docker &> /dev/null || { echo -e "${RED}❌ Ошибка: ${BOLD}'docker'${RESET} не найден. Установите его вручную.${RESET}"; exit 1; }
        command -v gzip &> /dev/null || { echo -e "${RED}❌ Ошибка: ${BOLD}'gzip'${RESET} не найден. Установите его вручную.${RESET}"; exit 1; }
        print_message "SUCCESS" "Основные зависимости (${BOLD}curl${RESET}, ${BOLD}docker${RESET}, ${BOLD}gzip${RESET}) найдены."
    fi
    echo ""
}

save_config() {
    print_message "INFO" "Сохранение конфигурации в ${BOLD}${CONFIG_FILE}${RESET}..."
    cat > "$CONFIG_FILE" <<EOF
BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
DB_USER="$DB_USER"
UPLOAD_METHOD="$UPLOAD_METHOD"
GD_CLIENT_ID="$GD_CLIENT_ID"
GD_CLIENT_SECRET="$GD_CLIENT_SECRET"
GD_REFRESH_TOKEN="$GD_REFRESH_TOKEN"
GD_FOLDER_ID="$GD_FOLDER_ID"
CRON_TIMES="$CRON_TIMES"
REMNALABS_ROOT_DIR="$REMNALABS_ROOT_DIR"
TG_MESSAGE_THREAD_ID="$TG_MESSAGE_THREAD_ID"
ADDITIONAL_BACKUPS_ENABLED="$ADDITIONAL_BACKUPS_ENABLED"
ADDITIONAL_PATHS="$ADDITIONAL_PATHS"
ADDITIONAL_DB_CONTAINER="$ADDITIONAL_DB_CONTAINER"
ADDITIONAL_DB_USER="$ADDITIONAL_DB_USER"
ADDITIONAL_DB_NAME="$ADDITIONAL_DB_NAME"
EOF
    chmod 600 "$CONFIG_FILE" || { print_message "ERROR" "Не удалось установить права доступа (600) для ${BOLD}${CONFIG_FILE}${RESET}. Проверьте разрешения."; exit 1; }
    print_message "SUCCESS" "Конфигурация сохранена."
}

load_or_create_config() {

    if [[ -f "$CONFIG_FILE" ]]; then
        print_message "INFO" "Загрузка конфигурации..."
        source "$CONFIG_FILE"
        echo ""

        UPLOAD_METHOD=${UPLOAD_METHOD:-telegram}
        DB_USER=${DB_USER:-postgres}
        CRON_TIMES=${CRON_TIMES:-}
        REMNALABS_ROOT_DIR=${REMNALABS_ROOT_DIR:-}
        TG_MESSAGE_THREAD_ID=${TG_MESSAGE_THREAD_ID:-}
        ADDITIONAL_BACKUPS_ENABLED=${ADDITIONAL_BACKUPS_ENABLED:-false}
        ADDITIONAL_PATHS=${ADDITIONAL_PATHS:-}
        ADDITIONAL_DB_CONTAINER=${ADDITIONAL_DB_CONTAINER:-}
        ADDITIONAL_DB_USER=${ADDITIONAL_DB_USER:-}
        ADDITIONAL_DB_NAME=${ADDITIONAL_DB_NAME:-}

        local config_updated=false
        config_updated=true

        if [[ -z "$BOT_TOKEN" || -z "$CHAT_ID" ]]; then
            print_message "WARN" "В файле конфигурации отсутствуют необходимые переменные для Telegram."
            print_message "ACTION" "Пожалуйста, введите недостающие данные для Telegram (обязательно):"
            echo ""
            print_message "INFO" "Создайте Telegram бота в ${CYAN}@BotFather${RESET} и получите API Token"
            [[ -z "$BOT_TOKEN" ]] && read -rp "    Введите API Token: " BOT_TOKEN
            echo ""
            print_message "INFO" "Введите Chat ID (для отправки в группу) или свой Telegram ID (для прямой отправки в бота)"
            echo -e "       Chat ID/Telegram ID можно узнать у этого бота ${CYAN}@username_to_id_bot${RESET}"
            [[ -z "$CHAT_ID" ]] && read -rp "    Введите ID: " CHAT_ID
            echo ""
            print_message "INFO" "Опционально: для отправки в определенный топик группы, введите ID топика (Message Thread ID)"
            echo -e "       Оставьте пустым для общего потока или отправки напрямую в бота"
            read -rp "    Введите Message Thread ID: " TG_MESSAGE_THREAD_ID
            echo ""
            config_updated=true
        fi

        [[ -z "$DB_USER" ]] && read -rp "    Введите имя пользователя вашей БД (по умолчанию postgres): " DB_USER
        DB_USER=${DB_USER:-postgres}
        config_updated=true
        echo ""
        
        if [[ -z "$REMNALABS_ROOT_DIR" ]]; then
            print_message "ACTION" "Где установлена/устанавливается ваша панель Remnawave?"
            echo "    1. /opt/remnawave"
            echo "    2. /root/remnawave"
            echo "    3. /opt/stacks/remnawave"
            echo ""
            local remnawave_path_choice
            while true; do
                read -rp "    ${GREEN}[?]${RESET} Выберите вариант: " remnawave_path_choice
                case "$remnawave_path_choice" in
                    1) REMNALABS_ROOT_DIR="/opt/remnawave"; break ;;
                    2) REMNALABS_ROOT_DIR="/root/remnawave"; break ;;
                    3) REMNALABS_ROOT_DIR="/opt/stacks/remnawave"; break ;;
                    *) print_message "ERROR" "Неверный ввод." ;;
                esac
            done
            config_updated=true
            echo ""
        fi


        if [[ "$UPLOAD_METHOD" == "google_drive" ]]; then
            if [[ -z "$GD_CLIENT_ID" || -z "$GD_CLIENT_SECRET" || -z "$GD_REFRESH_TOKEN" ]]; then
                print_message "WARN" "В файле конфигурации обнаружены неполные данные для Google Drive."
                print_message "WARN" "Способ отправки будет изменён на ${BOLD}Telegram${RESET}."
                UPLOAD_METHOD="telegram"
                config_updated=true
            fi
        fi

        if [[ "$UPLOAD_METHOD" == "google_drive" && ( -z "$GD_CLIENT_ID" || -z "$GD_CLIENT_SECRET" || -z "$GD_REFRESH_TOKEN" ) ]]; then
            print_message "WARN" "В файле конфигурации отсутствуют необходимые переменные для Google Drive."
            print_message "ACTION" "Пожалуйста, введите недостающие данные для Google Drive:"
            echo ""
            echo "Если у вас нет Client ID и Client Secret токенов"
            local guide_url="https://telegra.ph/Nastrojka-Google-API-06-02"
                print_message "LINK" "Изучите этот гайд: ${CYAN}${guide_url}${RESET}"
                echo ""
            [[ -z "$GD_CLIENT_ID" ]] && read -rp "    Введите Google Client ID: " GD_CLIENT_ID
            [[ -z "$GD_CLIENT_SECRET" ]] && read -rp "    Введите Google Client Secret: " GD_CLIENT_SECRET
            clear
            
            if [[ -z "$GD_REFRESH_TOKEN" ]]; then
                print_message "WARN" "Для получения Refresh Token необходимо пройти авторизацию в браузере."
                print_message "INFO" "Откройте следующую ссылку в браузере, авторизуйтесь и скопируйте код:"
                echo ""
                local auth_url="https://accounts.google.com/o/oauth2/auth?client_id=${GD_CLIENT_ID}&redirect_uri=urn:ietf:wg:oauth:2.0:oob&scope=https://www.googleapis.com/auth/drive&response_type=code&access_type=offline"
                print_message "INFO" "${CYAN}${auth_url}${RESET}"
                echo ""
                read -rp "    Введите код из браузера: " AUTH_CODE
                
                print_message "INFO" "Получение Refresh Token..."
                local token_response=$(curl -s -X POST https://oauth2.googleapis.com/token \
                    -d client_id="$GD_CLIENT_ID" \
                    -d client_secret="$GD_CLIENT_SECRET" \
                    -d code="$AUTH_CODE" \
                    -d redirect_uri="urn:ietf:wg:oauth:2.0:oob" \
                    -d grant_type="authorization_code")
                
                GD_REFRESH_TOKEN=$(echo "$token_response" | jq -r .refresh_token 2>/dev/null)
                
                if [[ -z "$GD_REFRESH_TOKEN" || "$GD_REFRESH_TOKEN" == "null" ]]; then
                    print_message "ERROR" "Не удалось получить Refresh Token. Проверьте Client ID, Client Secret и введенный 'Code'."
                    print_message "WARN" "Так как настройка Google Drive не завершена, способ отправки будет изменён на ${BOLD}Telegram${RESET}."
                    UPLOAD_METHOD="telegram"
                    config_updated=true
                fi
            fi
            echo
                    echo "    📁 Чтобы указать папку Google Drive:"
                    echo "    1. Создайте и откройте нужную папку в браузере."
                    echo "    2. Посмотрите на ссылку в адресной строке,она выглядит так:"
                    echo "      https://drive.google.com/drive/folders/1a2B3cD4eFmNOPqRstuVwxYz"
                    echo "    3. Скопируйте часть после /folders/ — это и есть Folder ID:"
                    echo "    4. Если оставить поле пустым — бекап будет отправлен в корневую папку Google Drive."
                    echo

                    read -rp "    Введите Google Drive Folder ID (оставьте пустым для корневой папки): " GD_FOLDER_ID
            config_updated=true
            echo ""
        fi

        if $config_updated; then
            save_config
            print_message "SUCCESS" "Конфигурация дополнена и сохранена в ${BOLD}${CONFIG_FILE}${RESET}"
        else
            print_message "SUCCESS" "Конфигурация успешно загружена из ${BOLD}${CONFIG_FILE}${RESET}."
        fi

    else
        if [[ "$SCRIPT_RUN_PATH" != "$SCRIPT_PATH" ]]; then
            print_message "INFO" "Конфигурация не найдена. Скрипт запущен из временного расположения."
            print_message "INFO" "Перемещаем скрипт в основной каталог установки: ${BOLD}${SCRIPT_PATH}${RESET}..."
            mkdir -p "$INSTALL_DIR" || { print_message "ERROR" "Не удалось создать каталог установки ${BOLD}${INSTALL_DIR}${RESET}. Проверьте права доступа."; exit 1; }
            mkdir -p "$BACKUP_DIR" || { print_message "ERROR" "Не удалось создать каталог для бэкапов ${BOLD}${BACKUP_DIR}${RESET}. Проверьте права доступа."; exit 1; }

            if mv "$SCRIPT_RUN_PATH" "$SCRIPT_PATH"; then
                chmod +x "$SCRIPT_PATH"
                clear
                print_message "SUCCESS" "Скрипт успешно перемещен в ${BOLD}${SCRIPT_PATH}${RESET}."
                print_message "ACTION" "Перезапускаем скрипт из нового расположения для завершения настройки."
                exec "$SCRIPT_PATH" "$@"
                exit 0
            else
                print_message "ERROR" "Не удалось переместить скрипт в ${BOLD}${SCRIPT_PATH}${RESET}. Проверьте права доступа."
                exit 1
            fi
        else
            print_message "INFO" "Конфигурация не найдена, создаем новую..."
            echo ""
            print_message "INFO" "Создайте Telegram бота в ${CYAN}@BotFather${RESET} и получите API Token"
            read -rp "    Введите API Token: " BOT_TOKEN
            echo ""
            print_message "INFO" "Введите Chat ID (для отправки в группу) или свой Telegram ID (для прямой отправки в бота)"
            echo -e "       Chat ID/Telegram ID можно узнать у этого бота ${CYAN}@username_to_id_bot${RESET}"
            read -rp "    Введите ID: " CHAT_ID
            echo ""
            print_message "INFO" "Опционально: для отправки в определенный топик группы, введите ID топика (Message Thread ID)"
            echo -e "       Оставьте пустым для общего потока или отправки напрямую в бота"
            read -rp "    Введите Message Thread ID: " TG_MESSAGE_THREAD_ID
            echo ""
            read -rp "    Введите имя пользователя PostgreSQL (по умолчанию postgres): " DB_USER
            DB_USER=${DB_USER:-postgres}
            echo ""

            print_message "ACTION" "Где установлена/устанавливается ваша панель Remnawave?"
            echo "    1. /opt/remnawave"
            echo "    2. /root/remnawave"
            echo "    3. /opt/stacks/remnawave"
            echo ""
            local remnawave_path_choice
            while true; do
                read -rp "    ${GREEN}[?]${RESET} Выберите вариант: " remnawave_path_choice
                case "$remnawave_path_choice" in
                    1) REMNALABS_ROOT_DIR="/opt/remnawave"; break ;;
                    2) REMNALABS_ROOT_DIR="/root/remnawave"; break ;;
                    3) REMNALABS_ROOT_DIR="/opt/stacks/remnawave"; break ;;
                    *) print_message "ERROR" "Неверный ввод." ;;
                esac
            done
            echo ""

            mkdir -p "$INSTALL_DIR" || { print_message "ERROR" "Не удалось создать каталог установки ${BOLD}${INSTALL_DIR}${RESET}. Проверьте права доступа."; exit 1; }
            mkdir -p "$BACKUP_DIR" || { print_message "ERROR" "Не удалось создать каталог для бэкапов ${BOLD}${BACKUP_DIR}${RESET}. Проверьте права доступа."; exit 1; }
            save_config
            print_message "SUCCESS" "Новая конфигурация сохранена в ${BOLD}${CONFIG_FILE}${RESET}"
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
        -e 's/~/\~/g' \
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
        -e 's/!/\!/g'
}

get_remnawave_version() {
    local version_output
    version_output=$(docker exec remnawave sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' package.json
 2>/dev/null)
    if [[ -z "$version_output" ]]; then
        echo "не определена"
    else
        echo "$version_output"
    fi
}

send_telegram_message() {
    local message="$1"
    local parse_mode="${2:-MarkdownV2}"
    local escaped_message
    escaped_message=$(escape_markdown_v2 "$message")

    if [[ -z "$BOT_TOKEN" || -z "$CHAT_ID" ]]; then
        print_message "ERROR" "Telegram BOT_TOKEN или CHAT_ID не настроены. Сообщение не отправлено."
        return 1
    fi

    local data_params=(
        -d chat_id="$CHAT_ID"
        -d text="$escaped_message"
        -d parse_mode="$parse_mode"
    )

    if [[ -n "$TG_MESSAGE_THREAD_ID" ]]; then
        data_params+=(-d message_thread_id="$TG_MESSAGE_THREAD_ID")
    fi

    local http_code=$(curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        "${data_params[@]}" \
        -w "%{http_code}" -o /dev/null 2>&1)

    if [[ "$http_code" -eq 200 ]]; then
        return 0
    else
        echo -e "${RED}❌ Ошибка отправки сообщения в Telegram. HTTP код: ${BOLD}$http_code${RESET}. Убедитесь, что ${BOLD}BOT_TOKEN${RESET} и ${BOLD}CHAT_ID${RESET} верны.${RESET}"
        return 1
    fi
}

send_telegram_document() {
    local file_path="$1"
    local caption="$2"
    local parse_mode="MarkdownV2"
    local escaped_caption
    escaped_caption=$(escape_markdown_v2 "$caption")

    if [[ -z "$BOT_TOKEN" || -z "$CHAT_ID" ]]; then
        print_message "ERROR" "Telegram BOT_TOKEN или CHAT_ID не настроены. Документ не отправлен."
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

    local api_response=$(curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" \
        "${form_params[@]}" \
        -w "%{http_code}" -o /dev/null 2>&1)

    local curl_status=$?

    if [ $curl_status -ne 0 ]; then
        echo -e "${RED}❌ Ошибка ${BOLD}CURL${RESET} при отправке документа в Telegram. Код выхода: ${BOLD}$curl_status${RESET}. Проверьте сетевое соединение.${RESET}"
        return 1
    fi

    local http_code="${api_response: -3}"

    if [[ "$http_code" == "200" ]]; then
        return 0
    else
        echo -e "${RED}❌ Telegram API вернул ошибку HTTP. Код: ${BOLD}$http_code${RESET}. Ответ: ${BOLD}$api_response${RESET}. Возможно, файл слишком большой или ${BOLD}BOT_TOKEN${RESET}/${BOLD}CHAT_ID${RESET} неверны.${RESET}"
        return 1
    fi
}

get_google_access_token() {
    if [[ -z "$GD_CLIENT_ID" || -z "$GD_CLIENT_SECRET" || -z "$GD_REFRESH_TOKEN" ]]; then
        print_message "ERROR" "Google Drive Client ID, Client Secret или Refresh Token не настроены."
        return 1
    fi

    local token_response=$(curl -s -X POST https://oauth2.googleapis.com/token \
        -d client_id="$GD_CLIENT_ID" \
        -d client_secret="$GD_CLIENT_SECRET" \
        -d refresh_token="$GD_REFRESH_TOKEN" \
        -d grant_type="refresh_token")
    
    local access_token=$(echo "$token_response" | jq -r .access_token 2>/dev/null)
    local expires_in=$(echo "$token_response" | jq -r .expires_in 2>/dev/null)

    if [[ -z "$access_token" || "$access_token" == "null" ]]; then
        local error_msg=$(echo "$token_response" | jq -r .error_description 2>/dev/null)
        print_message "ERROR" "Не удалось получить Access Token для Google Drive. Возможно, Refresh Token устарел или недействителен. Ошибка: ${error_msg:-Unknown error}."
        print_message "ACTION" "Пожалуйста, перенастройте Google Drive в меню 'Настроить способ отправки'."
        return 1
    fi
    echo "$access_token"
    return 0
}

send_google_drive_document() {
    local file_path="$1"
    local file_name=$(basename "$file_path")
    local access_token=$(get_google_access_token)

    if [[ -z "$access_token" ]]; then
        print_message "ERROR" "Не удалось отправить бэкап в Google Drive: не получен Access Token."
        return 1
    fi

    local mime_type="application/gzip"
    local upload_url="https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart"

    local metadata_file=$(mktemp)
    
    local metadata="{\"name\": \"$file_name\", \"mimeType\": \"$mime_type\""
    if [[ -n "$GD_FOLDER_ID" ]]; then
        metadata="${metadata}, \"parents\": [\"$GD_FOLDER_ID\"]"
    fi
    metadata="${metadata}}"
    
    echo "$metadata" > "$metadata_file"

    local response=$(curl -s -X POST "$upload_url" \
        -H "Authorization: Bearer $access_token" \
        -F "metadata=@$metadata_file;type=application/json" \
        -F "file=@$file_path;type=$mime_type")

    rm -f "$metadata_file"

    local file_id=$(echo "$response" | jq -r .id 2>/dev/null)
    local error_message=$(echo "$response" | jq -r .error.message 2>/dev/null)
    local error_code=$(echo "$response" | jq -r .error.code 2>/dev/null)

    if [[ -n "$file_id" && "$file_id" != "null" ]]; then
        return 0
    else
        print_message "ERROR" "Ошибка при загрузке в Google Drive. Код: ${error_code:-Unknown}. Сообщение: ${error_message:-Unknown error}. Полный ответ API: ${response}"
        return 1
    fi
}

create_backup() {
    print_message "INFO" "Начинаю процесс создания резервной копии..."
    echo ""

    REMNAWAVE_VERSION=$(get_remnawave_version)
    TIMESTAMP=$(date +%Y-%m-%d"_"%H_%M_%S)
    BACKUP_FILE_DB="dump_${TIMESTAMP}.sql.gz"
    BACKUP_FILE_FINAL="remnawave_backup_${TIMESTAMP}.tar.gz"
    ENV_NODE_PATH="$REMNALABS_ROOT_DIR/$ENV_NODE_FILE"
    ENV_PATH="$REMNALABS_ROOT_DIR/$ENV_FILE"

    mkdir -p "$BACKUP_DIR" || { echo -e "${RED}❌ Ошибка: Не удалось создать каталог для бэкапов. Проверьте права доступа.${RESET}"; send_telegram_message "❌ Ошибка: Не удалось создать каталог бэкапов ${BOLD}$BACKUP_DIR${RESET}." "None"; exit 1; }

    if ! docker inspect remnawave-db > /dev/null 2>&1 || ! docker container inspect -f '{{.State.Running}}' remnawave-db 2>/dev/null | grep -q "true"; then
        echo -e "${RED}❌ Ошибка: Контейнер ${BOLD}'remnawave-db'${RESET} не найден или не запущен. Невозможно создать бэкап базы данных.${RESET}"
        local error_msg="❌ Ошибка: Контейнер ${BOLD}'remnawave-db'${RESET} не найден или не запущен. Не удалось создать бэкап."
        if [[ "$UPLOAD_METHOD" == "telegram" ]]; then
            send_telegram_message "$error_msg" "None"
        elif [[ "$UPLOAD_METHOD" == "google_drive" ]]; then
            print_message "ERROR" "Отправка в Google Drive невозможна из-за ошибки с контейнером DB."
        fi
        exit 1
    fi
    print_message "INFO" "Создание PostgreSQL дампа и сжатие в файл..."
    if ! docker exec -t "remnawave-db" pg_dumpall -c -U "$DB_USER" | gzip -9 > "$BACKUP_DIR/$BACKUP_FILE_DB"; then
        STATUS=$?
        echo -e "${RED}❌ Ошибка при создании дампа PostgreSQL. Код выхода: ${BOLD}$STATUS${RESET}. Проверьте имя пользователя БД и доступ к контейнеру.${RESET}"
        local error_msg="❌ Ошибка при создании дампа PostgreSQL. Код выхода: ${BOLD}${STATUS}${RESET}"
        if [[ "$UPLOAD_METHOD" == "telegram" ]]; then
            send_telegram_message "$error_msg" "None"
        elif [[ "$UPLOAD_METHOD" == "google_drive" ]]; then
            print_message "ERROR" "Отправка в Google Drive невозможна из-за ошибки с дампом DB."
        fi
        exit $STATUS
    fi
    print_message "SUCCESS" "Дамп PostgreSQL успешно создан."
    echo ""
    print_message "INFO" "Архивирование бэкапа в файл..."
    
    FILES_TO_ARCHIVE=("$BACKUP_FILE_DB")
    
    if [ -f "$ENV_NODE_PATH" ]; then
        print_message "INFO" "Обнаружен файл ${BOLD}${ENV_NODE_FILE}${RESET}. Добавляем его в архив."
        cp "$ENV_NODE_PATH" "$BACKUP_DIR/" || { 
            echo -e "${RED}❌ Ошибка при копировании ${BOLD}${ENV_NODE_FILE}${RESET} для бэкапа.${RESET}"; 
            local error_msg="❌ Ошибка: Не удалось скопировать ${BOLD}${ENV_NODE_FILE}${RESET} для бэкапа."
            if [[ "$UPLOAD_METHOD" == "telegram" ]]; then send_telegram_message "$error_msg" "None"; fi
            exit 1; 
        }
        FILES_TO_ARCHIVE+=("$ENV_NODE_FILE")
    else
        print_message "WARN" "Файл ${BOLD}${ENV_NODE_FILE}${RESET} не найден. Продолжаем без него."
    fi

    if [ -f "$ENV_PATH" ]; then
        print_message "INFO" "Обнаружен файл ${BOLD}${ENV_FILE}${RESET}. Добавляем его в архив."
        cp "$ENV_PATH" "$BACKUP_DIR/" || { 
            echo -e "${RED}❌ Ошибка при копировании ${BOLD}${ENV_FILE}${RESET} для бэкапа.${RESET}"; 
            local error_msg="❌ Ошибка: Не удалось скопировать ${BOLD}${ENV_FILE}${RESET} для бэкапа."
            if [[ "$UPLOAD_METHOD" == "telegram" ]]; then send_telegram_message "$error_msg" "None"; fi
            exit 1; 
        }
        FILES_TO_ARCHIVE+=("$ENV_FILE")
    else
        print_message "WARN" "Файл ${BOLD}${ENV_FILE}${RESET} не найден по пути. Продолжаем без него."
    fi
    echo ""

    if ! tar -czf "$BACKUP_DIR/$BACKUP_FILE_FINAL" -C "$BACKUP_DIR" "${FILES_TO_ARCHIVE[@]}"; then
        STATUS=$?
        echo -e "${RED}❌ Ошибка при архивировании бэкапа. Код выхода: ${BOLD}$STATUS${RESET}. Проверьте наличие свободного места и права доступа.${RESET}"
        local error_msg="❌ Ошибка при архивировании бэкапа. Код выхода: ${BOLD}${STATUS}${RESET}"
        if [[ "$UPLOAD_METHOD" == "telegram" ]]; then
            send_telegram_message "$error_msg" "None"
        elif [[ "$UPLOAD_METHOD" == "google_drive" ]]; then
            print_message "ERROR" "Отправка в Google Drive невозможна из-за ошибки архивации."
        fi
        exit $STATUS
    fi
    print_message "SUCCESS" "Архив бэкапа успешно создан: ${BOLD}${BACKUP_DIR}/${BACKUP_FILE_FINAL}${RESET}"
    echo ""

    print_message "INFO" "Очистка промежуточных файлов бэкапа..."
    rm -f "$BACKUP_DIR/$BACKUP_FILE_DB"
    rm -f "$BACKUP_DIR/$ENV_NODE_FILE"
    rm -f "$BACKUP_DIR/$ENV_FILE"
    print_message "SUCCESS" "Промежуточные файлы удалены."
    echo ""

    print_message "INFO" "Отправка бэкапа (${UPLOAD_METHOD})..."
    local DATE=$(date +'%Y-%m-%d %H:%M:%S')
    local caption_text=$'💾 #backup_success\n➖➖➖➖➖➖➖➖➖\n✅ *Бэкап успешно создан*\n🌊 *Remnawave:* '"${REMNAWAVE_VERSION}"$'\n📅 *Дата:* '"${DATE}"

    if [[ -f "$BACKUP_DIR/$BACKUP_FILE_FINAL" ]]; then
        if [[ "$UPLOAD_METHOD" == "telegram" ]]; then
            if send_telegram_document "$BACKUP_DIR/$BACKUP_FILE_FINAL" "$caption_text"; then
                print_message "SUCCESS" "Бэкап успешно отправлен в Telegram."
            else
                echo -e "${RED}❌ Ошибка при отправке бэкапа в Telegram. Проверьте настройки Telegram API (токен, ID чата).${RESET}"
            fi
        elif [[ "$UPLOAD_METHOD" == "google_drive" ]]; then
            if send_google_drive_document "$BACKUP_DIR/$BACKUP_FILE_FINAL"; then
                print_message "SUCCESS" "Бэкап успешно отправлен в Google Drive."
                local tg_success_message=$'💾 #backup_success\n➖➖➖➖➖➖➖➖➖\n✅ *Бэкап успешно создан и отправлен в Google Drive*\n🌊 *Remnawave:* '"${REMNAWAVE_VERSION}"$'\n📅 *Дата:* '"${DATE}"
                if send_telegram_message "$tg_success_message"; then
                    print_message "SUCCESS" "Уведомление об успешной отправке на Google Drive отправлено в Telegram."
                else
                    print_message "ERROR" "Не удалось отправить уведомление в Telegram после загрузки на Google Drive."
                fi
            else
                echo -e "${RED}❌ Ошибка при отправке бэкапа в Google Drive. Проверьте настройки Google Drive API.${RESET}"
                send_telegram_message "❌ Ошибка: Не удалось отправить бэкап в Google Drive. Подробности в логах сервера." "None"
            fi
        else
            print_message "WARN" "Неизвестный метод отправки: ${BOLD}${UPLOAD_METHOD}${RESET}. Бэкап не отправлен."
            send_telegram_message "❌ Ошибка: Неизвестный метод отправки бэкапа: ${BOLD}${UPLOAD_METHOD}${RESET}. Файл: ${BOLD}${BACKUP_FILE_FINAL}${RESET} не отправлен." "None"
        fi
    else
        echo -e "${RED}❌ Ошибка: Финальный файл бэкапа не найден после создания: ${BOLD}${BACKUP_DIR}/${BACKUP_FILE_FINAL}${RESET}. Отправка невозможна.${RESET}"
        local error_msg="❌ Ошибка: Файл бэкапа не найден после создания: ${BOLD}${BACKUP_FILE_FINAL}${RESET}"
        if [[ "$UPLOAD_METHOD" == "telegram" ]]; then
            send_telegram_message "$error_msg" "None"
        elif [[ "$UPLOAD_METHOD" == "google_drive" ]]; then
            print_message "ERROR" "Отправка в Google Drive невозможна: файл бэкапа не найден."
        fi
        exit 1
    fi
    echo ""

    print_message "INFO" "Применение политики хранения бэкапов (оставляем за последние ${BOLD}${RETAIN_BACKUPS_DAYS}${RESET} дней)..."
    find "$BACKUP_DIR" -maxdepth 1 -name "remnawave_backup_*.tar.gz" -mtime +$RETAIN_BACKUPS_DAYS -delete
    print_message "SUCCESS" "Политика хранения применена. Старые бэкапы удалены."
    echo ""

    if [[ "$ADDITIONAL_BACKUPS_ENABLED" == true ]]; then
        create_additional_backup
    fi

    {
        check_update_status >/dev/null 2>&1
        if [[ "$UPDATE_AVAILABLE" == true ]]; then
            local CURRENT_VERSION="$VERSION"
            local REMOTE_VERSION_LATEST

            REMOTE_VERSION_LATEST=$(curl -fsSL "$SCRIPT_REPO_URL" 2>/dev/null | grep -m 1 "^VERSION=" | cut -d'"' -f2)

            if [[ -n "$REMOTE_VERSION_LATEST" ]]; then
                local update_msg=$'⚠️ *Доступно обновление скрипта*\n🔄 *Текущая версия:* '"${CURRENT_VERSION}"$'\n🆕 *Актуальная версия:* '"${REMOTE_VERSION_LATEST}"$'\n\n📥 Обновите через пункт *«Обновление скрипта»* в главном меню'
                send_telegram_message "$update_msg" >/dev/null 2>&1
            fi
        fi
    } &
}

create_additional_backup() {
    print_message "INFO" "Создание дополнительного бэкапа..."
    local ADD_DIR="$BACKUP_DIR/additional"
    local ADD_DB_FILE="additional_dump_${TIMESTAMP}.sql.gz"
    local ADD_FINAL_FILE="additional_backup_${TIMESTAMP}.tar.gz"

    mkdir -p "$ADD_DIR" || { print_message "ERROR" "Не удалось создать каталог дополнительных бэкапов."; return 1; }

    local tmp_dir
    tmp_dir=$(mktemp -d)
    local have_data=false

    if [[ -n "$ADDITIONAL_DB_CONTAINER" && -n "$ADDITIONAL_DB_USER" && -n "$ADDITIONAL_DB_NAME" ]]; then
        print_message "INFO" "Создание дампа дополнительной БД..."
        if docker inspect "$ADDITIONAL_DB_CONTAINER" > /dev/null 2>&1 && docker container inspect -f '{{.State.Running}}' "$ADDITIONAL_DB_CONTAINER" 2>/dev/null | grep -q "true"; then
            if docker exec -t "$ADDITIONAL_DB_CONTAINER" pg_dump -U "$ADDITIONAL_DB_USER" "$ADDITIONAL_DB_NAME" | gzip -9 > "$ADD_DIR/$ADD_DB_FILE"; then
                cp "$ADD_DIR/$ADD_DB_FILE" "$tmp_dir/"
                have_data=true
                print_message "SUCCESS" "Дамп дополнительной БД создан."
            else
                print_message "ERROR" "Не удалось создать дамп дополнительной БД."
            fi
        else
            print_message "ERROR" "Контейнер дополнительной БД не найден или не запущен."
        fi
    fi

    if [[ -n "$ADDITIONAL_PATHS" ]]; then
        print_message "INFO" "Добавление файловых путей в дополнительный бэкап..."
        for p in $ADDITIONAL_PATHS; do
            if [[ -e "$p" ]]; then
                cp -r "$p" "$tmp_dir/" 2>/dev/null || print_message "WARN" "Не удалось добавить путь $p"
                have_data=true
            else
                print_message "WARN" "Путь $p не найден. Пропуск."
            fi
        done
    fi

    if [[ "$have_data" == true ]]; then
        if tar -czf "$ADD_DIR/$ADD_FINAL_FILE" -C "$tmp_dir" .; then
            print_message "SUCCESS" "Дополнительный архив создан: ${BOLD}${ADD_DIR}/${ADD_FINAL_FILE}${RESET}"
            rm -rf "$tmp_dir"
            rm -f "$ADD_DIR/$ADD_DB_FILE"

            print_message "INFO" "Отправка дополнительного бэкапа (${UPLOAD_METHOD})..."
            if [[ "$UPLOAD_METHOD" == "telegram" ]]; then
                local caption=$'💾 #extra_backup\n📅 *Дата:* '"${DATE}"
                if send_telegram_document "$ADD_DIR/$ADD_FINAL_FILE" "$caption"; then
                    print_message "SUCCESS" "Дополнительный бэкап отправлен в Telegram."
                else
                    print_message "ERROR" "Не удалось отправить дополнительный бэкап в Telegram."
                fi
            elif [[ "$UPLOAD_METHOD" == "google_drive" ]]; then
                if send_google_drive_document "$ADD_DIR/$ADD_FINAL_FILE"; then
                    print_message "SUCCESS" "Дополнительный бэкап отправлен в Google Drive."
                    send_telegram_message $'💾 #extra_backup\n✅ *Дополнительный бэкап отправлен в Google Drive*\n📅 *Дата:* '"${DATE}" "None"
                else
                    print_message "ERROR" "Не удалось отправить дополнительный бэкап в Google Drive."
                    send_telegram_message "❌ Ошибка: Не удалось отправить дополнительный бэкап в Google Drive." "None"
                fi
            else
                print_message "WARN" "Неизвестный метод отправки: ${BOLD}${UPLOAD_METHOD}${RESET}. Дополнительный бэкап не отправлен."
                send_telegram_message "❌ Ошибка: Неизвестный метод отправки дополнительного бэкапа: ${BOLD}${UPLOAD_METHOD}${RESET}." "None"
            fi

            print_message "INFO" "Применение политики хранения для дополнительных бэкапов..."
            find "$ADD_DIR" -maxdepth 1 -name "additional_backup_*.tar.gz" -mtime +$RETAIN_BACKUPS_DAYS -delete
            print_message "SUCCESS" "Политика хранения дополнительных бэкапов применена."
        else
            print_message "ERROR" "Не удалось создать архив дополнительного бэкапа."
            rm -rf "$tmp_dir"
            rm -f "$ADD_DIR/$ADD_DB_FILE"
            return 1
        fi
    else
        print_message "WARN" "Нет данных для дополнительного бэкапа."
        rm -rf "$tmp_dir"
        rm -f "$ADD_DIR/$ADD_DB_FILE"
    fi

    return 0
}

setup_auto_send() {
    echo ""
    if [[ $EUID -ne 0 ]]; then
        print_message "WARN" "Для настройки cron требуются права root. Пожалуйста, запустите с '${BOLD}sudo'${RESET}.${RESET}"
        read -rp "Нажмите Enter для продолжения..."
        return
    fi
    while true; do
        clear
        echo -e "${GREEN}${BOLD}Настройка автоматической отправки${RESET}"
        echo ""
        if [[ -n "$CRON_TIMES" ]]; then
            print_message "INFO" "Автоматическая отправка настроена на: ${BOLD}${CRON_TIMES}${RESET} по UTC+0."
        else
            print_message "INFO" "Автоматическая отправка ${BOLD}выключена${RESET}."
        fi
        echo ""
        echo "   1. Включить/перезаписать автоматическую отправку бэкапов"
        echo "   2. Выключить автоматическую отправку бэкапов"
        echo ""
        echo "   0. Вернуться в главное меню"
        echo ""
        read -rp "${GREEN}[?]${RESET} Выберите пункт: " choice
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

                echo "Введите желаемое время отправки по UTC+0 (например, 08:00)"
                read -rp "Вы можете указать несколько времен через пробел: " times
                
                valid_times_cron=()
                local user_friendly_times_local=""
                cron_times_to_write=()

                invalid_format=false
                IFS=' ' read -ra arr <<< "$times"
                for t in "${arr[@]}"; do
                    if [[ $t =~ ^([0-9]{1,2}):([0-9]{2})$ ]]; then
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
                            user_friendly_times_local+="$t "
                        else
                            print_message "ERROR" "Неверное значение времени: ${BOLD}$t${RESET} (часы 0-23, минуты 0-59)."
                            invalid_format=true
                            break
                        fi
                    else
                        print_message "ERROR" "Неверный формат времени: ${BOLD}$t${RESET} (ожидается HH:MM)."
                        invalid_format=true
                        break
                    fi
                done
                echo ""

                if [ "$invalid_format" = true ] || [ ${#cron_times_to_write[@]} -eq 0 ]; then
                    print_message "ERROR" "Автоматическая отправка не настроена из-за ошибок ввода времени. Пожалуйста, попробуйте еще раз."
                    continue
                fi

                print_message "INFO" "Настройка cron-задачи для автоматической отправки..."
                
                local temp_crontab_file=$(mktemp)

                if ! crontab -l > "$temp_crontab_file" 2>/dev/null; then
                    touch "$temp_crontab_file"
                fi

                if ! grep -q "^SHELL=" "$temp_crontab_file"; then
                    echo "SHELL=/bin/bash" | cat - "$temp_crontab_file" > "$temp_crontab_file.tmp"
                    mv "$temp_crontab_file.tmp" "$temp_crontab_file"
                    print_message "INFO" "SHELL=/bin/bash добавлен в crontab."
                fi

                if ! grep -q "^PATH=" "$temp_crontab_file"; then
                    echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin" | cat - "$temp_crontab_file" > "$temp_crontab_file.tmp"
                    mv "$temp_crontab_file.tmp" "$temp_crontab_file"
                    print_message "INFO" "PATH переменная добавлена в crontab."
                else
                    print_message "INFO" "PATH переменная уже существует в crontab."
                fi

                grep -vF "$SCRIPT_PATH backup" "$temp_crontab_file" > "$temp_crontab_file.tmp"
                mv "$temp_crontab_file.tmp" "$temp_crontab_file"

                for time_entry_local in "${cron_times_to_write[@]}"; do
                    echo "$time_entry_local * * * $SCRIPT_PATH backup >> /var/log/rw_backup_cron.log 2>&1" >> "$temp_crontab_file"
                done
                
                if crontab "$temp_crontab_file"; then
                    print_message "SUCCESS" "CRON-задача для автоматической отправки успешно установлена."
                else
                    print_message "ERROR" "Не удалось установить CRON-задачу. Проверьте права доступа и наличие crontab."
                fi

                rm -f "$temp_crontab_file"

                CRON_TIMES="${user_friendly_times_local% }"
                save_config
                print_message "SUCCESS" "Автоматическая отправка установлена на: ${BOLD}${CRON_TIMES}${RESET} по UTC+0."
                ;;
            2)
                print_message "INFO" "Отключение автоматической отправки..."
                (crontab -l 2>/dev/null | grep -vF "$SCRIPT_PATH backup") | crontab -
                
                CRON_TIMES=""
                save_config
                print_message "SUCCESS" "Автоматическая отправка успешно отключена."
                ;;
            0) break ;;
            *) print_message "ERROR" "Неверный ввод. Пожалуйста, выберите один из предложенных пунктов." ;;
        esac
        echo ""
        read -rp "Нажмите Enter для продолжения..."
    done
    echo ""
}
    
restore_backup() {
    clear
    echo "${GREEN}${BOLD}Восстановление из бэкапа${RESET}"
    echo ""
    print_message "INFO" "Поместите файл бэкапа в папку: ${BOLD}${BACKUP_DIR}${RESET}"

    ENV_NODE_RESTORE_PATH="$REMNALABS_ROOT_DIR/$ENV_NODE_FILE"
    ENV_RESTORE_PATH="$REMNALABS_ROOT_DIR/$ENV_FILE"

    if ! compgen -G "$BACKUP_DIR/remnawave_backup_*.tar.gz" > /dev/null; then
        print_message "ERROR" "Ошибка: Не найдено файлов бэкапов в ${BOLD}${BACKUP_DIR}${RESET}. Пожалуйста, поместите файл бэкапа в этот каталог."
        read -rp "Нажмите Enter для возврата в меню..."
        return 1
    fi

    readarray -t SORTED_BACKUP_FILES < <(find "$BACKUP_DIR" -maxdepth 1 -name "remnawave_backup_*.tar.gz" -printf "%T@ %p\n" | sort -nr | cut -d' ' -f2-)

    if [ ${#SORTED_BACKUP_FILES[@]} -eq 0 ]; then
        print_message "ERROR" "Ошибка: Не найдено файлов бэкапов в ${BOLD}${BACKUP_DIR}${RESET}."
        read -rp "Нажмите Enter для возврата в меню..."
        return 1
    fi

    echo ""
    echo "Выберите файл для восстановления:"
    local i=1
    for file in "${SORTED_BACKUP_FILES[@]}"; do
        echo "  $i) ${file##*/}"
        i=$((i+1))
    done
    echo ""
    echo "  0) Вернуться в главное меню"
    echo ""

    local user_choice
    local selected_index

    while true; do
        read -rp "${GREEN}[?]${RESET} Введите номер файла для восстановления (0 для выхода): " user_choice
        
        if [[ "$user_choice" == "0" ]]; then
            print_message "INFO" "Восстановление отменено пользователем."
            read -rp "Нажмите Enter для возврата в меню..."
            return
        fi

        if ! [[ "$user_choice" =~ ^[0-9]+$ ]]; then
            print_message "ERROR" "Неверный ввод. Пожалуйста, введите номер."
            continue
        fi

        selected_index=$((user_choice - 1))

        if (( selected_index >= 0 && selected_index < ${#SORTED_BACKUP_FILES[@]} )); then
            SELECTED_BACKUP="${SORTED_BACKUP_FILES[$selected_index]}"
            break
        else
            print_message "ERROR" "Неверный номер. Пожалуйста, выберите номер из списка."
        fi
    done

    echo ""
    print_message "WARN" "Операция восстановления полностью перезапишет текущую БД"
    print_message "INFO" "В конфигурации скрипта вы указали имя пользователя БД: ${BOLD}${GREEN}${DB_USER}${RESET}"
    read -rp "$(echo -e "${GREEN}[?]${RESET} Введите ${GREEN}${BOLD}Y${RESET}/${RED}${BOLD}N${RESET} для продолжения: ")" db_user_confirm
    if [[ "$db_user_confirm" != "y" ]]; then
        print_message "INFO" "Операция восстановления отменена пользователем."
        read -rp "Нажмите Enter для возврата в меню..."
        return
    fi

    clear
    print_message "INFO" "Начало процесса полного сброса и восстановления базы данных..."
    echo ""

    print_message "INFO" "Остановка контейнеров и удаление тома базы данных..."
    if ! cd "$REMNALABS_ROOT_DIR"; then
        print_message "ERROR" "Ошибка: Не удалось перейти в каталог ${BOLD}${REMNALABS_ROOT_DIR}${RESET}. Убедитесь, что файл ${BOLD}docker-compose.yml${RESET} находится там."
        read -rp "Нажмите Enter для возврата в меню..."
        return 1
    fi

    docker compose down || {
        print_message "WARN" "Не удалось корректно остановить сервисы. Возможно, они уже остановлены."
    }
    
    if docker volume ls -q | grep -q "remnawave-db-data"; then
        if ! docker volume rm remnawave-db-data; then
            echo -e "${RED}Критическая ошибка: Не удалось удалить том ${BOLD}remnawave-db-data${RESET}. Восстановление невозможно. Проверьте права или занятость тома.${RESET}"
            read -rp "Нажмите Enter для возврата в меню..."
            return 1
        fi
        print_message "SUCCESS" "Том ${BOLD}remnawave-db-data${RESET} успешно удален."
    else
        print_message "INFO" "Том ${BOLD}remnawave-db-data${RESET} не найден, пропуск удаления."
    fi
    echo ""

    print_message "INFO" "Распаковка архива бэкапа..."
    local temp_restore_dir="$BACKUP_DIR/restore_temp_$$"
    mkdir -p "$temp_restore_dir"

    if ! tar -xzf "$SELECTED_BACKUP" -C "$temp_restore_dir"; then
        STATUS=$?
        echo -e "${RED}❌ Ошибка при распаковке архива ${BOLD}${SELECTED_BACKUP##*/}${RESET}. Код выхода: ${BOLD}$STATUS${RESET}.${RESET}"
        if [[ "$UPLOAD_METHOD" == "telegram" ]]; then
            send_telegram_message "❌ Ошибка при распаковке архива: ${BOLD}${SELECTED_BACKUP##*/}${RESET}. Код выхода: ${BOLD}${STATUS}${RESET}" "None"
        fi
        [[ -n "$temp_restore_dir" && -d "$temp_restore_dir" ]] && rm -rf "$temp_restore_dir"
            read -rp "Нажмите Enter для возврата в меню..."
            return 1
        fi
    print_message "SUCCESS" "Архив успешно распакован во временную директорию."
    echo ""

    if [ -f "$temp_restore_dir/$ENV_NODE_FILE" ]; then
        print_message "INFO" "Обнаружен файл ${BOLD}${ENV_NODE_FILE}${RESET}. Перемещаем его в ${BOLD}${ENV_NODE_RESTORE_PATH}${RESET}."
        mv "$temp_restore_dir/$ENV_NODE_FILE" "$ENV_NODE_RESTORE_PATH" || {
            echo -e "${RED}❌ Ошибка при перемещении ${BOLD}${ENV_NODE_FILE}${RESET}.${RESET}"
            if [[ "$UPLOAD_METHOD" == "telegram" ]]; then
                send_telegram_message "❌ Ошибка: Не удалось переместить ${BOLD}${ENV_NODE_FILE}${RESET} при восстановлении." "None"
            fi
            [[ -n "$temp_restore_dir" && -d "$temp_restore_dir" ]] && rm -rf "$temp_restore_dir"
            read -rp "Нажмите Enter для возврата в меню..."
            return 1
        }
        print_message "SUCCESS" "Файл ${BOLD}${ENV_NODE_FILE}${RESET} успешно перемещен."
    else
        print_message "WARN" "Внимание: Файл ${BOLD}${ENV_NODE_FILE}${RESET} не найден в архиве. Продолжаем без него."
    fi

    if [ -f "$temp_restore_dir/$ENV_FILE" ]; then
        print_message "INFO" "Обнаружен файл ${BOLD}${ENV_FILE}${RESET}. Перемещаем его в ${BOLD}${ENV_RESTORE_PATH}${RESET}."
        mv "$temp_restore_dir/$ENV_FILE" "$ENV_RESTORE_PATH" || {
            echo -e "${RED}❌ Ошибка при перемещении ${BOLD}${ENV_FILE}${RESET}.${RESET}"
            if [[ "$UPLOAD_METHOD" == "telegram" ]]; then
                send_telegram_message "❌ Ошибка: Не удалось переместить ${BOLD}${ENV_FILE}${RESET} при восстановлении." "None"
            fi
            [[ -n "$temp_restore_dir" && -d "$temp_restore_dir" ]] && rm -rf "$temp_restore_dir"
            read -rp "Нажмите Enter для возврата в меню..."
            return 1
        }
        print_message "SUCCESS" "Файл ${BOLD}${ENV_FILE}${RESET} успешно перемещен."
    else
        print_message "WARN" "Внимание: Файл ${BOLD}${ENV_FILE}${RESET} не найден в архиве. Продолжаем без него."
    fi
    echo ""

    print_message "INFO" "Запуск контейнера с базой данных, ожидайте..."
    docker compose rm -f remnawave-db > /dev/null 2>&1
    docker compose up -d remnawave-db
    print_message "INFO" "Ожидание готовности базы данных..."
    until [ "$(docker inspect --format='{{.State.Health.Status}}' remnawave-db)" == "healthy" ]; do
        sleep 2
        echo -n "."
    done
    echo ""
    print_message "SUCCESS" "База данных готова."
    echo ""
    print_message "INFO" "Восстановление базы данных из дампа..."
    local DUMP_FILE_GZ=$(find "$temp_restore_dir" -name "dump_*.sql.gz" | head -n 1)

    if [[ -z "$DUMP_FILE_GZ" ]]; then
        print_message "ERROR" "Файл дампа не найден в архиве. Восстановление невозможно."
        [[ -n "$temp_restore_dir" && -d "$temp_restore_dir" ]] && rm -rf "$temp_restore_dir"
        read -rp "Нажмите Enter для возврата в меню..."
        return 1
    fi

    local DUMP_FILE="${DUMP_FILE_GZ%.gz}"
    if ! gunzip "$DUMP_FILE_GZ"; then
        print_message "ERROR" "Не удалось распаковать дамп SQL: ${DUMP_FILE_GZ}"
        [[ -n "$temp_restore_dir" && -d "$temp_restore_dir" ]] && rm -rf "$temp_restore_dir"
        read -rp "Нажмите Enter для возврата в меню..."
        return 1
    fi

    if ! docker exec -i remnawave-db psql -q -U postgres -d postgres > /dev/null 2> "$temp_restore_dir/restore_errors.log" < "$DUMP_FILE"; then
        print_message "ERROR" "Ошибка при восстановлении дампа базы данных."

        echo ""
        print_message "WARN" "${YELLOW}Лог ошибок восстановления:${RESET}"
        cat "$temp_restore_dir/restore_errors.log"

        [[ -n "$temp_restore_dir" && -d "$temp_restore_dir" ]] && rm -rf "$temp_restore_dir"
        read -rp "Нажмите Enter для возврата в меню..."
        return 1
    fi

    print_message "SUCCESS" "База данных успешно восстановлена."
    echo ""

    print_message "INFO" "Удаление временных файлов восстановления..."
    [[ -n "$temp_restore_dir" && -d "$temp_restore_dir" ]] && rm -rf "$temp_restore_dir"
    echo ""

    print_message "INFO" "Запуск всех контейнеров..."
    docker compose up -d
    echo ""

    print_message "SUCCESS" "Восстановление завершено. Все контейнеры запущены."

    REMNAWAVE_VERSION=$(get_remnawave_version)
    local restore_msg=$'💾 #restore_success\n➖➖➖➖➖➖➖➖➖\n✅ *Восстановление БД завершено*\n🌊 *Remnawave:* '"${REMNAWAVE_VERSION}"
    send_telegram_message "$restore_msg" >/dev/null 2>&1
    
    read -rp "Нажмите Enter для продолжения..."
    return
}

update_script() {
    print_message "INFO" "Начинаю процесс проверки обновлений..."
    echo ""
    if [[ "$EUID" -ne 0 ]]; then
        echo -e "${RED}⛔ Для обновления скрипта требуются права root. Пожалуйста, запустите с '${BOLD}sudo'${RESET}.${RESET}"
        read -rp "Нажмите Enter для продолжения..."
        return
    fi

    print_message "INFO" "Получение информации о последней версии скрипта с GitHub..."
    local TEMP_REMOTE_VERSION_FILE
    TEMP_REMOTE_VERSION_FILE=$(mktemp)

    if ! curl -fsSL "$SCRIPT_REPO_URL" 2>/dev/null | head -n 100 > "$TEMP_REMOTE_VERSION_FILE"; then
        print_message "ERROR" "Не удалось загрузить информацию о новой версии с GitHub. Проверьте URL или сетевое соединение."
        rm -f "$TEMP_REMOTE_VERSION_FILE"
        read -rp "Нажмите Enter для продолжения..."
        return
    fi

    REMOTE_VERSION=$(grep -m 1 "^VERSION=" "$TEMP_REMOTE_VERSION_FILE" | cut -d'"' -f2)
    rm -f "$TEMP_REMOTE_VERSION_FILE"

    if [[ -z "$REMOTE_VERSION" ]]; then
        print_message "ERROR" "Не удалось извлечь информацию о версии из удаленного скрипта. Возможно, формат переменной VERSION изменился."
        read -rp "Нажмите Enter для продолжения..."
        return
    fi

    print_message "INFO" "Текущая версия: ${BOLD}${YELLOW}${VERSION}${RESET}"
    print_message "INFO" "Доступная версия: ${BOLD}${GREEN}${REMOTE_VERSION}${RESET}"
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
        print_message "ACTION" "Доступно обновление до версии ${BOLD}${REMOTE_VERSION}${RESET}."
        echo -e -n "Хотите обновить скрипт? Введите ${GREEN}${BOLD}Y${RESET}/${RED}${BOLD}N${RESET}: "
        read -r confirm_update
        echo ""

        if [[ "${confirm_update,,}" != "y" ]]; then
            print_message "WARN" "Обновление отменено пользователем. Возврат в главное меню."
            read -rp "Нажмите Enter для продолжения..."
            return
        fi
    else
        print_message "INFO" "У вас установлена актуальная версия скрипта. Обновление не требуется."
        read -rp "Нажмите Enter для продолжения..."
        return
    fi

    local TEMP_SCRIPT_PATH="${INSTALL_DIR}/backup-restore.sh.tmp"
    print_message "INFO" "Загрузка обновления..."
    if ! curl -fsSL "$SCRIPT_REPO_URL" -o "$TEMP_SCRIPT_PATH"; then
        print_message "ERROR" "Не удалось загрузить новую версию скрипта."
        read -rp "Нажмите Enter для продолжения..."
        return
    fi

    if [[ ! -s "$TEMP_SCRIPT_PATH" ]] || ! head -n 1 "$TEMP_SCRIPT_PATH" | grep -q -e '^#!.*bash'; then
        print_message "ERROR" "Загруженный файл пуст или не является исполняемым bash-скриптом. Обновление невозможно."
        rm -f "$TEMP_SCRIPT_PATH"
        read -rp "Нажмите Enter для продолжения..."
        return
    fi

    print_message "INFO" "Удаление старых резервных копий скрипта..."
    find "$(dirname "$SCRIPT_PATH")" -maxdepth 1 -name "${SCRIPT_NAME}.bak.*" -type f -delete
    echo ""

    local BACKUP_PATH_SCRIPT="${SCRIPT_PATH}.bak.$(date +%s)"
    print_message "INFO" "Создание резервной копии текущего скрипта..."
    cp "$SCRIPT_PATH" "$BACKUP_PATH_SCRIPT" || {
        echo -e "${RED}❌ Не удалось создать резервную копию ${BOLD}${SCRIPT_PATH}${RESET}. Обновление отменено.${RESET}"
        rm -f "$TEMP_SCRIPT_PATH"
        read -rp "Нажмите Enter для продолжения..."
        return
    }
    echo ""

    mv "$TEMP_SCRIPT_PATH" "$SCRIPT_PATH" || {
        echo -e "${RED}❌ Ошибка перемещения временного файла в ${BOLD}${SCRIPT_PATH}${RESET}. Пожалуйста, проверьте права доступа.${RESET}"
        echo -e "${YELLOW}⚠️ Восстановление из резервной копии ${BOLD}${BACKUP_PATH_SCRIPT}${RESET}...${RESET}"
        mv "$BACKUP_PATH_SCRIPT" "$SCRIPT_PATH"
        rm -f "$TEMP_SCRIPT_PATH"
        read -rp "Нажмите Enter для продолжения..."
        return
    }

    chmod +x "$SCRIPT_PATH"
    print_message "SUCCESS" "Скрипт успешно обновлен до версии ${BOLD}${GREEN}${REMOTE_VERSION}${RESET}."
    echo ""
    print_message "INFO" "Для применения изменений скрипт будет перезапущен..."
    read -rp "Нажмите Enter для перезапуска."
    exec "$SCRIPT_PATH" "$@"
    exit 0
}

remove_script() {
    print_message "WARN" "${YELLOW}ВНИМАНИЕ!${RESET} Будут удалены: "
    echo  " - Скрипт"
    echo  " - Каталог установки и все бэкапы"
    echo  " - Символическая ссылка (если существует)"
    echo  " - Задачи cron"
    echo ""
    echo -e -n "Вы уверены, что хотите продолжить? Введите ${GREEN}${BOLD}Y${RESET}/${RED}${BOLD}N${RESET}: "
    read -r confirm
    echo ""
    
    if [[ "${confirm,,}" != "y" ]]; then
    print_message "WARN" "Удаление отменено."
    read -rp "Нажмите Enter для продолжения..."
    return
    fi

    if [[ "$EUID" -ne 0 ]]; then
        print_message "WARN" "Для полного удаления требуются права root. Пожалуйста, запустите с ${BOLD}sudo${RESET}."
        read -rp "Нажмите Enter для продолжения..."
        return
    fi

    print_message "INFO" "Удаление cron-задач..."
    if crontab -l 2>/dev/null | grep -qF "$SCRIPT_PATH backup"; then
        (crontab -l 2>/dev/null | grep -vF "$SCRIPT_PATH backup") | crontab -
        print_message "SUCCESS" "Задачи cron для автоматического бэкапа удалены."
    else
        print_message "INFO" "Задачи cron для автоматического бэкапа не найдены."
    fi
    echo ""

    print_message "INFO" "Удаление символической ссылки..."
    if [[ -L "$SYMLINK_PATH" ]]; then
        rm -f "$SYMLINK_PATH" && print_message "SUCCESS" "Символическая ссылка ${BOLD}${SYMLINK_PATH}${RESET} удалена." || print_message "WARN" "Не удалось удалить символическую ссылку ${BOLD}${SYMLINK_PATH}${RESET}. Возможно, потребуется ручное удаление."
    elif [[ -e "$SYMLINK_PATH" ]]; then
        print_message "WARN" "${BOLD}${SYMLINK_PATH}${RESET} существует, но не является символической ссылкой. Рекомендуется проверить и удалить вручную."
    else
        print_message "INFO" "Символическая ссылка ${BOLD}${SYMLINK_PATH}${RESET} не найдена."
    fi
    echo ""

    print_message "INFO" "Удаление каталога установки и всех данных..."
    if [[ -d "$INSTALL_DIR" ]]; then
        rm -rf "$INSTALL_DIR" && print_message "SUCCESS" "Каталог установки ${BOLD}${INSTALL_DIR}${RESET} (включая скрипт, конфигурацию, бэкапы) удален." || echo -e "${RED}❌ Ошибка при удалении каталога ${BOLD}${INSTALL_DIR}${RESET}. Возможно, потребуются права 'root' или каталог занят.${RESET}"
    else
        print_message "INFO" "Каталог установки ${BOLD}${INSTALL_DIR}${RESET} не найден."
    fi
    exit 0
}

configure_upload_method() {
    while true; do
        clear
        echo -e "${GREEN}${BOLD}Настройка способа отправки бэкапов${RESET}"
        echo ""
        print_message "INFO" "Текущий способ: ${BOLD}${UPLOAD_METHOD^^}${RESET}"
        echo ""
        echo "   1. Установить способ отправки: Telegram"
        echo "   2. Установить способ отправки: Google Drive"
        echo ""
        echo "   0. Вернуться в главное меню"
        echo ""
        read -rp "${GREEN}[?]${RESET} Выберите пункт: " choice
        echo ""

        case $choice in
            1)
                UPLOAD_METHOD="telegram"
                save_config
                print_message "SUCCESS" "Способ отправки установлен на ${BOLD}Telegram${RESET}."
                if [[ -z "$BOT_TOKEN" || -z "$CHAT_ID" ]]; then
                    print_message "ACTION" "Пожалуйста, введите данные для Telegram:"
                    echo ""
                    print_message "INFO" "Создайте Telegram бота в ${CYAN}@BotFather${RESET} и получите API Token"
                    read -rp "   Введите API Token: " BOT_TOKEN
                    echo ""
                    print_message "INFO" "Свой ID можно узнать у этого бота в Telegram ${CYAN}@userinfobot${RESET}"
                    read -rp "   Введите свой Telegram ID: " CHAT_ID
                    save_config
                    print_message "SUCCESS" "Настройки Telegram сохранены."
                fi
                ;;
            2)
                UPLOAD_METHOD="google_drive"
                print_message "SUCCESS" "Способ отправки установлен на ${BOLD}Google Drive${RESET}."
                
                local gd_setup_successful=true

                if [[ -z "$GD_CLIENT_ID" || -z "$GD_CLIENT_SECRET" || -z "$GD_REFRESH_TOKEN" ]]; then
                    print_message "ACTION" "Пожалуйста, введите данные для Google Drive API."
                    echo ""
                    echo "Если у вас нет Client ID и Client Secret токенов"
                    local guide_url="https://telegra.ph/Nastrojka-Google-API-06-02"
                    print_message "LINK" "Изучите этот гайд: ${CYAN}${guide_url}${RESET}"
                    read -rp "   Введите Google Client ID: " GD_CLIENT_ID
                    read -rp "   Введите Google Client Secret: " GD_CLIENT_SECRET
                    
                    clear
                    
                    print_message "WARN" "Для получения Refresh Token необходимо пройти авторизацию в браузере."
                    print_message "INFO" "Откройте следующую ссылку в браузере, авторизуйтесь и скопируйте ${BOLD}код${RESET}:"
                    echo ""
                    local auth_url="https://accounts.google.com/o/oauth2/auth?client_id=${GD_CLIENT_ID}&redirect_uri=urn:ietf:wg:oauth:2.0:oob&scope=https://www.googleapis.com/auth/drive&response_type=code&access_type=offline"
                    print_message "INFO" "${CYAN}${auth_url}${RESET}"
                    echo ""
                    read -rp "Введите код из браузера: " AUTH_CODE
                    
                    print_message "INFO" "Получение Refresh Token..."
                    local token_response=$(curl -s -X POST https://oauth2.googleapis.com/token \
                        -d client_id="$GD_CLIENT_ID" \
                        -d client_secret="$GD_CLIENT_SECRET" \
                        -d code="$AUTH_CODE" \
                        -d redirect_uri="urn:ietf:wg:oauth:2.0:oob" \
                        -d grant_type="authorization_code")
                    
                    GD_REFRESH_TOKEN=$(echo "$token_response" | jq -r .refresh_token 2>/dev/null)
                    
                    if [[ -z "$GD_REFRESH_TOKEN" || "$GD_REFRESH_TOKEN" == "null" ]]; then
                        print_message "ERROR" "Не удалось получить Refresh Token. Проверьте введенные данные."
                        print_message "WARN" "Настройка не завершена, способ отправки будет изменён на ${BOLD}Telegram${RESET}."
                        UPLOAD_METHOD="telegram"
                        gd_setup_successful=false
                    else
                        print_message "SUCCESS" "Refresh Token успешно получен."
                    fi
                    echo
                    
                    if $gd_setup_successful; then
                        echo "   📁 Чтобы указать папку Google Drive:"
                        echo "   1. Создайте и откройте нужную папку в браузере."
                        echo "   2. Посмотрите на ссылку в адресной строке,она выглядит так:"
                        echo "      https://drive.google.com/drive/folders/1a2B3cD4eFmNOPqRstuVwxYz"
                        echo "   3. Скопируйте часть после /folders/ — это и есть Folder ID:"
                        echo "   4. Если оставить поле пустым — бекап будет отправлен в корневую папку Google Drive."
                        echo

                        read -rp "   Введите Google Drive Folder ID (оставьте пустым для корневой папки): " GD_FOLDER_ID
                    fi
                fi

                save_config

                if $gd_setup_successful; then
                    print_message "SUCCESS" "Настройки Google Drive сохранены."
                else
                    print_message "SUCCESS" "Способ отправки установлен на ${BOLD}Telegram${RESET}."
                fi
                ;;
            0) break ;;
            *) print_message "ERROR" "Неверный ввод. Пожалуйста, выберите один из предложенных пунктов." ;;
        esac
        echo ""
        read -rp "Нажмите Enter для продолжения..."
    done
    echo ""
}

configure_additional_backups() {
    while true; do
        clear
        echo -e "${GREEN}${BOLD}Дополнительные бэкапы${RESET}"
        echo ""
        if [[ "$ADDITIONAL_BACKUPS_ENABLED" == true ]]; then
            local status="включены"
        else
            local status="выключены"
        fi
        print_message "INFO" "Сейчас дополнительные бэкапы ${BOLD}${status}${RESET}"
        echo ""
        echo "   1. Переключить дополнительные бэкапы"
        echo "   2. Указать дополнительные пути"
        echo "   3. Настроить дополнительную БД"
        echo "   0. Назад"
        echo ""
        read -rp "   ${GREEN}[?]${RESET} Выберите пункт: " extra_choice
        echo ""
        case $extra_choice in
            1)
                if [[ "$ADDITIONAL_BACKUPS_ENABLED" == true ]]; then
                    ADDITIONAL_BACKUPS_ENABLED=false
                else
                    ADDITIONAL_BACKUPS_ENABLED=true
                fi
                save_config
                if [[ "$ADDITIONAL_BACKUPS_ENABLED" == true ]]; then
                    print_message "SUCCESS" "Дополнительные бэкапы включены."
                else
                    print_message "SUCCESS" "Дополнительные бэкапы выключены."
                fi
                ;;
            2)
                print_message "INFO" "Текущие пути: ${BOLD}${ADDITIONAL_PATHS:-отсутствуют}${RESET}"
                read -rp "   Введите пути через пробел: " new_paths
                ADDITIONAL_PATHS="$new_paths"
                save_config
                print_message "SUCCESS" "Пути сохранены."
                ;;
            3)
                print_message "INFO" "Текущие настройки БД: контейнер=${BOLD}${ADDITIONAL_DB_CONTAINER:--}${RESET}, пользователь=${BOLD}${ADDITIONAL_DB_USER:--}${RESET}, база=${BOLD}${ADDITIONAL_DB_NAME:--}${RESET}"
                read -rp "   Введите имя контейнера (оставьте пустым чтобы очистить): " new_container
                read -rp "   Введите имя пользователя БД: " new_user
                read -rp "   Введите имя базы данных: " new_db
                ADDITIONAL_DB_CONTAINER="$new_container"
                ADDITIONAL_DB_USER="$new_user"
                ADDITIONAL_DB_NAME="$new_db"
                save_config
                print_message "SUCCESS" "Настройки БД сохранены."
                ;;
            0) break ;;
            *) print_message "ERROR" "Неверный ввод. Пожалуйста, выберите один из предложенных пунктов." ;;
        esac
        echo ""
        read -rp "Нажмите Enter для продолжения..."
    done
    echo ""
}

configure_settings() {
    while true; do
        clear
        echo -e "${GREEN}${BOLD}Изменение конфигурации скрипта${RESET}"
        echo ""
        echo "   1. Настройки Telegram"
        echo "   2. Настройки Google Drive"
        echo "   3. Имя пользователя PostgreSQL"
        echo "   4. Путь Remnawave"
        echo ""
        echo "   0. Вернуться в главное меню"
        echo ""
        read -rp "${GREEN}[?]${RESET} Выберите пункт: " choice
        echo ""

        case $choice in
            1)
                while true; do
                    clear
                    echo -e "${GREEN}${BOLD}Настройки Telegram${RESET}"
                    echo ""
                    print_message "INFO" "Текущий API Token: ${BOLD}${BOT_TOKEN}${RESET}"
                    print_message "INFO" "Текущий ID: ${BOLD}${CHAT_ID}${RESET}"
                    print_message "INFO" "Текущий Message Thread ID: ${BOLD}${TG_MESSAGE_THREAD_ID:-Не установлен}${RESET}"
                    echo ""
                    echo "   1. Изменить API Token"
                    echo "   2. Изменить ID"
                    echo "   3. Изменить Message Thread ID (для топиков групп)"
                    echo ""
                    echo "   0. Назад"
                    echo ""
                    read -rp "${GREEN}[?]${RESET} Выберите пункт: " telegram_choice
                    echo ""

                    case $telegram_choice in
                        1)
                            print_message "INFO" "Создайте Telegram бота в ${CYAN}@BotFather${RESET} и получите API Token"
                            read -rp "   Введите новый API Token: " NEW_BOT_TOKEN
                            BOT_TOKEN="$NEW_BOT_TOKEN"
                            save_config
                            print_message "SUCCESS" "API Token успешно обновлен."
                            ;;
                        2)
                            print_message "INFO" "Введите Chat ID (для отправки в группу) или свой Telegram ID (для прямой отправки в бота)"
            echo -e "       Chat ID/Telegram ID можно узнать у этого бота ${CYAN}@username_to_id_bot${RESET}"
                            read -rp "   Введите новый ID: " NEW_CHAT_ID
                            CHAT_ID="$NEW_CHAT_ID"
                            save_config
                            print_message "SUCCESS" "ID успешно обновлен."
                            ;;
                        3)
                            print_message "INFO" "Опционально: для отправки в определенный топик группы, введите ID топика (Message Thread ID)"
            echo -e "       Оставьте пустым для общего потока или отправки напрямую в бота"
                            read -rp "   Введите Message Thread ID: " NEW_TG_MESSAGE_THREAD_ID
                            TG_MESSAGE_THREAD_ID="$NEW_TG_MESSAGE_THREAD_ID"
                            save_config
                            print_message "SUCCESS" "Message Thread ID успешно обновлен."
                            ;;
                        0) break ;;
                        *) print_message "ERROR" "Неверный ввод. Пожалуйста, выберите один из предложенных пунктов." ;;
                    esac
                    echo ""
                    read -rp "Нажмите Enter для продолжения..."
                done
                ;;

            2)
                while true; do
                    clear
                    echo -e "${GREEN}${BOLD}Настройки Google Drive${RESET}"
                    echo ""
                    print_message "INFO" "Текущий Client ID: ${BOLD}${GD_CLIENT_ID:0:8}...${RESET}"
                    print_message "INFO" "Текущий Client Secret: ${BOLD}${GD_CLIENT_SECRET:0:8}...${RESET}"
                    print_message "INFO" "Текущий Refresh Token: ${BOLD}${GD_REFRESH_TOKEN:0:8}...${RESET}"
                    print_message "INFO" "Текущий Drive Folder ID: ${BOLD}${GD_FOLDER_ID:-Корневая папка}${RESET}"
                    echo ""
                    echo "   1. Изменить Google Client ID"
                    echo "   2. Изменить Google Client Secret"
                    echo "   3. Изменить Google Refresh Token (потребуется повторная авторизация)"
                    echo "   4. Изменить Google Drive Folder ID"
                    echo ""
                    echo "   0. Назад"
                    echo ""
                    read -rp "${GREEN}[?]${RESET} Выберите пункт: " gd_choice
                    echo ""

                    case $gd_choice in
                        1)
                            echo "Если у вас нет Client ID и Client Secret токенов"
                            local guide_url="https://telegra.ph/Nastrojka-Google-API-06-02"
                            print_message "LINK" "Изучите этот гайд: ${CYAN}${guide_url}${RESET}"
                            read -rp "   Введите новый Google Client ID: " NEW_GD_CLIENT_ID
                            GD_CLIENT_ID="$NEW_GD_CLIENT_ID"
                            save_config
                            print_message "SUCCESS" "Google Client ID успешно обновлен."
                            ;;
                        2)
                            echo "Если у вас нет Client ID и Client Secret токенов"
                            local guide_url="https://telegra.ph/Nastrojka-Google-API-06-02"
                            print_message "LINK" "Изучите этот гайд: ${CYAN}${guide_url}${RESET}"
                            read -rp "   Введите новый Google Client Secret: " NEW_GD_CLIENT_SECRET
                            GD_CLIENT_SECRET="$NEW_GD_CLIENT_SECRET"
                            save_config
                            print_message "SUCCESS" "Google Client Secret успешно обновлен."
                            ;;
                        3)
                            clear
                            print_message "WARN" "Для получения нового Refresh Token необходимо пройти авторизацию в браузере."
                            print_message "INFO" "Откройте следующую ссылку в браузере, авторизуйтесь и скопируйте ${BOLD}код${RESET}:"
                            echo ""
                            local auth_url="https://accounts.google.com/o/oauth2/auth?client_id=${GD_CLIENT_ID}&redirect_uri=urn:ietf:wg:oauth:2.0:oob&scope=https://www.googleapis.com/auth/drive&response_type=code&access_type=offline"
                            print_message "LINK" "${CYAN}${auth_url}${RESET}"
                            echo ""
                            read -rp "Введите код из браузера: " AUTH_CODE
                            
                            print_message "INFO" "Получение Refresh Token..."
                            local token_response=$(curl -s -X POST https://oauth2.googleapis.com/token \
                                -d client_id="$GD_CLIENT_ID" \
                                -d client_secret="$GD_CLIENT_SECRET" \
                                -d code="$AUTH_CODE" \
                                -d redirect_uri="urn:ietf:wg:oauth:2.0:oob" \
                                -d grant_type="authorization_code")
                            
                            NEW_GD_REFRESH_TOKEN=$(echo "$token_response" | jq -r .refresh_token 2>/dev/null)
                            
                            if [[ -z "$NEW_GD_REFRESH_TOKEN" || "$NEW_GD_REFRESH_TOKEN" == "null" ]]; then
                                print_message "ERROR" "Не удалось получить Refresh Token. Проверьте введенные данные."
                                print_message "WARN" "Настройка не завершена."
                            else
                                GD_REFRESH_TOKEN="$NEW_GD_REFRESH_TOKEN"
                                save_config
                                print_message "SUCCESS" "Refresh Token успешно обновлен."
                            fi
                            ;;
                        4)
                            echo
                            echo "   📁 Чтобы указать папку Google Drive:"
                            echo "   1. Создайте и откройте нужную папку в браузере."
                            echo "   2. Посмотрите на ссылку в адресной строке,она выглядит так:"
                            echo "      https://drive.google.com/drive/folders/1a2B3cD4eFmNOPqRstuVwxYz"
                            echo "   3. Скопируйте часть после /folders/ — это и есть Folder ID:"
                            echo "   4. Если оставить поле пустым — бекап будет отправлен в корневую папку Google Drive."
                            echo
                            read -rp "   Введите новый Google Drive Folder ID (оставьте пустым для корневой папки): " NEW_GD_FOLDER_ID
                            GD_FOLDER_ID="$NEW_GD_FOLDER_ID"
                            save_config
                            print_message "SUCCESS" "Google Drive Folder ID успешно обновлен."
                            ;;
                        0) break ;;
                        *) print_message "ERROR" "Неверный ввод. Пожалуйста, выберите один из предложенных пунктов." ;;
                    esac
                    echo ""
                    read -rp "Нажмите Enter для продолжения..."
                done
                ;;
            3)
                clear
                echo -e "${GREEN}${BOLD}Имя пользователя PostgreSQL${RESET}"
                echo ""
                print_message "INFO" "Текущее имя пользователя PostgreSQL: ${BOLD}${DB_USER}${RESET}"
                echo ""
                read -rp "   Введите новое имя пользователя PostgreSQL (по умолчанию postgres): " NEW_DB_USER
                DB_USER="${NEW_DB_USER:-postgres}"
                save_config
                print_message "SUCCESS" "Имя пользователя PostgreSQL успешно обновлено на ${BOLD}${DB_USER}${RESET}."
                echo ""
                read -rp "Нажмите Enter для продолжения..."
                ;;
            4)
                clear
                echo -e "${GREEN}${BOLD}Путь Remnawave${RESET}"
                echo ""
                print_message "INFO" "Текущий путь Remnawave: ${BOLD}${REMNALABS_ROOT_DIR}${RESET}"
                echo ""
                print_message "ACTION" "Выберите новый путь для панели Remnawave:"
                echo "   1. /opt/remnawave"
                echo "   2. /root/remnawave"
                echo "   3. /opt/stacks/remnawave"
                echo ""
                local new_remnawave_path_choice
                while true; do
                    read -rp "   ${GREEN}[?]${RESET} Выберите вариант: " new_remnawave_path_choice
                    case "$new_remnawave_path_choice" in
                        1) REMNALABS_ROOT_DIR="/opt/remnawave"; break ;;
                        2) REMNALABS_ROOT_DIR="/root/remnawave"; break ;;
                        3) REMNALABS_ROOT_DIR="/opt/stacks/remnawave"; break ;;
                        *) print_message "ERROR" "Неверный ввод." ;;
                    esac
                done
                save_config
                print_message "SUCCESS" "Путь Remnawave успешно обновлен на ${BOLD}${REMNALABS_ROOT_DIR}${RESET}."
                echo ""
                read -rp "Нажмите Enter для продолжения..."
                ;;
            0) break ;;
            *) print_message "ERROR" "Неверный ввод. Пожалуйста, выберите один из предложенных пунктов." ;;
        esac
        echo ""
    done
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

main_menu() {
    while true; do
        check_update_status
        clear
        echo -e "${GREEN}${BOLD}REMNAWAVE BACKUP & RESTORE by distillium${RESET} "
        if [[ "$UPDATE_AVAILABLE" == true ]]; then
            echo -e "${BOLD}${LIGHT_GRAY}Версия: ${VERSION} ${YELLOW}(доступно обновление)${RESET}"
        else
            echo -e "${BOLD}${LIGHT_GRAY}Версия: ${VERSION}${RESET}"
        fi
        echo ""
        echo "   1. Создание бэкапа вручную"
        echo "   2. Восстановление из бэкапа"
        echo ""
        echo "   3. Настройка автоматической отправки и уведомлений"
        echo "   4. Настройка способа отправки"
        echo "   5. Дополнительные бэкапы"
        echo "   6. Изменение конфигурации скрипта"
        echo ""
        echo "   7. Обновление скрипта"
        echo "   8. Удаление скрипта"
        echo ""
        echo "   0. Выход"
        echo -e "   —  Быстрый запуск: ${BOLD}${GREEN}rw-backup${RESET} доступен из любой точки системы"
        echo ""

        read -rp "${GREEN}[?]${RESET} Выберите пункт: " choice
        echo ""
        case $choice in
            1) create_backup ; read -rp "Нажмите Enter для продолжения..." ;;
            2) restore_backup ;;
            3) setup_auto_send ;;
            4) configure_upload_method ;;
            5) configure_additional_backups ;;
            6) configure_settings ;;
            7) update_script ;;
            8) remove_script ;;
            0) echo "Выход..."; exit 0 ;;
            *) print_message "ERROR" "Неверный ввод. Пожалуйста, выберите один из предложенных пунктов." ; read -rp "Нажмите Enter для продолжения..." ;;
        esac
    done
}

if ! command -v jq &> /dev/null; then
    print_message "INFO" "Установка пакета 'jq' для парсинга JSON..."
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}❌ Ошибка: Для установки 'jq' требуются права root. Пожалуйста, установите 'jq' вручную (например, 'sudo apt-get install jq') или запустите скрипт с sudo.${RESET}"
        exit 1
    fi
    if command -v apt-get &> /dev/null; then
        apt-get update -qq > /dev/null 2>&1
        apt-get install -y jq > /dev/null 2>&1 || { echo -e "${RED}❌ Ошибка: Не удалось установить 'jq'.${RESET}"; exit 1; }
        print_message "SUCCESS" "'jq' успешно установлен."
    else
        print_message "ERROR" "Не удалось найти менеджер пакетов apt-get. Установите 'jq' вручную."
        exit 1
    fi
fi

if [[ -z "$1" ]]; then
    install_dependencies
    load_or_create_config
    setup_symlink
    main_menu
elif [[ "$1" == "backup" ]]; then
    load_or_create_config
    create_backup
elif [[ "$1" == "restore" ]]; then
    load_or_create_config
    restore_backup
elif [[ "$1" == "update" ]]; then
    update_script
elif [[ "$1" == "remove" ]]; then
    remove_script
else
    echo -e "${RED}❌ Неверное использование. Доступные команды: ${BOLD}${0} [backup|restore|update|remove]${RESET}${RESET}"
    exit 1
fi
