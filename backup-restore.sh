#!/bin/bash

set -e

VERSION="2.1.0"
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
BACKUP_EXCLUDE_PATTERNS="*.log *.tmp .git"

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

configure_bot_backup() {
    while true; do
        clear
        echo -e "${GREEN}${BOLD}Настройка бэкапа Telegram бота${RESET}"
        echo ""
        
        if [[ "$BOT_BACKUP_ENABLED" == "true" ]]; then
            print_message "INFO" "Бэкап бота: ${BOLD}${GREEN}ВКЛЮЧЕН${RESET}"
            print_message "INFO" "Выбранный бот: ${BOLD}${BOT_BACKUP_SELECTED}${RESET}"
            print_message "INFO" "Путь к боту: ${BOLD}${BOT_BACKUP_PATH}${RESET}"
        else
            print_message "INFO" "Бэкап бота: ${BOLD}${RED}ВЫКЛЮЧЕН${RESET}"
        fi
        
        echo ""
        echo " 1. Включить и настроить бэкап бота"
        echo " 2. Выключить бэкап бота"
        echo ""
        echo " 0. Вернуться в главное меню"
        echo ""
        
        read -rp "${GREEN}[?]${RESET} Выберите пункт: " choice
        echo ""
        
        case $choice in
            1)
                clear
                echo -e "${GREEN}${BOLD}Настройка бэкапа Telegram бота${RESET}"
                echo ""
                print_message "ACTION" "Выберите бота для бэкапа:"
                echo " 1. Бот от Иисуса (remnawave-telegram-shop)"
                echo " 2. Бот от Мачки (remnawave-tg-shop)"
                echo ""
                echo " 0. Назад"
                echo ""
                
                local bot_choice
                local selected_bot=""
                
                while true; do
                    read -rp " ${GREEN}[?]${RESET} Выберите бота: " bot_choice
                    case "$bot_choice" in
                        1)
                            selected_bot="Бот от Иисуса"
                            break
                            ;;
                        2)
                            selected_bot="Бот от Мачки"
                            break
                            ;;
                        0) 
                            selected_bot=""
                            break 
                            ;;
                        *)
                            print_message "ERROR" "Неверный ввод."
                            ;;
                    esac
                done
                
                if [[ -z "$selected_bot" ]]; then
                    continue
                fi
                
                BOT_BACKUP_SELECTED="$selected_bot"
                
                echo ""
                print_message "ACTION" "Выберите путь к директории бота:"
                if [[ "$BOT_BACKUP_SELECTED" == "Бот от Иисуса" ]]; then
                    echo " 1. /opt/remnawave-telegram-shop"
                    echo " 2. /root/remnawave-telegram-shop"
                    echo " 3. /opt/stacks/remnawave-telegram-shop"
                else
                    echo " 1. /opt/remnawave-tg-shop"
                    echo " 2. /root/remnawave-tg-shop"
                    echo " 3. /opt/stacks/remnawave-tg-shop"
                fi
                echo " 4. Указать свой путь"
                echo ""
                echo " 0. Назад"
                echo ""

                local path_choice
                while true; do
                    read -rp " ${GREEN}[?]${RESET} Выберите путь: " path_choice
                    case "$path_choice" in
                    1)
                        if [[ "$BOT_BACKUP_SELECTED" == "Бот от Иисуса" ]]; then
                            BOT_BACKUP_PATH="/opt/remnawave-telegram-shop"
                        else
                            BOT_BACKUP_PATH="/opt/remnawave-tg-shop"
                        fi
                        break
                        ;;
                    2)
                        if [[ "$BOT_BACKUP_SELECTED" == "Бот от Иисуса" ]]; then
                            BOT_BACKUP_PATH="/root/remnawave-telegram-shop"
                        else
                            BOT_BACKUP_PATH="/root/remnawave-tg-shop"
                        fi
                        break
                        ;;
                    3)
                        if [[ "$BOT_BACKUP_SELECTED" == "Бот от Иисуса" ]]; then
                            BOT_BACKUP_PATH="/opt/stacks/remnawave-telegram-shop"
                        else
                            BOT_BACKUP_PATH="/opt/stacks/remnawave-tg-shop"
                        fi
                        break
                        ;;
                    4)
                        echo ""
                        print_message "INFO" "Введите полный путь к директории бота:"
                        read -rp " Путь: " custom_bot_path
        
                        if [[ -z "$custom_bot_path" ]]; then
                            print_message "ERROR" "Путь не может быть пустым."
                            echo ""
                            read -rp "Нажмите Enter, чтобы продолжить..."
                            continue
                        fi
        
                        if [[ ! "$custom_bot_path" = /* ]]; then
                            print_message "ERROR" "Путь должен быть абсолютным (начинаться с /)."
                            echo ""
                            read -rp "Нажмите Enter, чтобы продолжить..."
                            continue
                        fi
        
                        custom_bot_path="${custom_bot_path%/}"
        
                        if [[ ! -d "$custom_bot_path" ]]; then
                            print_message "WARN" "Директория ${BOLD}${custom_bot_path}${RESET} не существует."
                            read -rp "$(echo -e "${GREEN}[?]${RESET} Продолжить с этим путем? ${GREEN}${BOLD}Y${RESET}/${RED}${BOLD}N${RESET}: ")" confirm_custom_bot_path
                            if [[ ! "$confirm_custom_bot_path" =~ ^[yY]$ ]]; then
                                echo ""
                                read -rp "Нажмите Enter, чтобы продолжить..."
                                continue
                            fi
                        fi
        
                        BOT_BACKUP_PATH="$custom_bot_path"
                        print_message "SUCCESS" "Установлен кастомный путь бота: ${BOLD}${BOT_BACKUP_PATH}${RESET}"
                        break
                        ;;
                    0)
                        continue 2
                        ;;
                    *)
                        print_message "ERROR" "Неверный ввод."
                        ;;
                    esac
                done
                
                echo ""
                read -rp " Введите имя пользователя PostgreSQL для бота (по умолчанию postgres): " bot_db_user
                BOT_BACKUP_DB_USER="${bot_db_user:-postgres}"
                BOT_BACKUP_ENABLED="true"
                save_config
                print_message "SUCCESS" "Бэкап бота успешно настроен и включен."
                ;;
            2)
                BOT_BACKUP_ENABLED="false"
                BOT_BACKUP_PATH=""
                BOT_BACKUP_SELECTED=""
                save_config
                print_message "SUCCESS" "Бэкап бота выключен."
                ;;
            0) 
                break 
                ;;
            *) 
                print_message "ERROR" "Неверный ввод. Пожалуйста, выберите один из предложенных пунктов." 
                ;;
        esac
        
        echo ""
        read -rp "Нажмите Enter для продолжения..."
    done
}

get_bot_params() {
    local bot_name="$1"
    
    case "$bot_name" in
        "Бот от Иисуса")
            echo "remnawave-telegram-shop-db|remnawave-telegram-shop-db-data|remnawave-telegram-shop|db"
            ;;
        "Бот от Мачки")
            echo "remnawave-tg-shop-db|remnawave-tg-shop-db-data|remnawave-tg-shop|remnawave-tg-shop-db"
            ;;
        *)
            echo "|||"
            ;;
    esac
}

create_bot_backup() {
    if [[ "$BOT_BACKUP_ENABLED" != "true" ]]; then
        return 0
    fi
    
    print_message "INFO" "Создание бэкапа Telegram бота: ${BOLD}${BOT_BACKUP_SELECTED}${RESET}..."
    
    local bot_params=$(get_bot_params "$BOT_BACKUP_SELECTED")
    IFS='|' read -r BOT_CONTAINER_NAME BOT_VOLUME_NAME BOT_DIR_NAME BOT_SERVICE_NAME <<< "$bot_params"
    
    if [[ -z "$BOT_CONTAINER_NAME" ]]; then
        print_message "ERROR" "Неизвестный бот: $BOT_BACKUP_SELECTED"
        print_message "INFO" "Продолжаем создание бэкапа без бота..."
        return 0
    fi

    local BOT_BACKUP_FILE_DB="bot_dump_${TIMESTAMP}.sql.gz"
    local BOT_DIR_ARCHIVE="bot_dir_${TIMESTAMP}.tar.gz"
    
    if ! docker inspect "$BOT_CONTAINER_NAME" > /dev/null 2>&1 || ! docker container inspect -f '{{.State.Running}}' "$BOT_CONTAINER_NAME" 2>/dev/null | grep -q "true"; then
        print_message "WARN" "Контейнер бота '$BOT_CONTAINER_NAME' не найден или не запущен. Пропускаем бэкап бота."
        return 0
    fi
    
    print_message "INFO" "Создание PostgreSQL дампа бота..."
    if ! docker exec -t "$BOT_CONTAINER_NAME" pg_dumpall -c -U "$BOT_BACKUP_DB_USER" | gzip -9 > "$BACKUP_DIR/$BOT_BACKUP_FILE_DB"; then
        print_message "ERROR" "Ошибка при создании дампа PostgreSQL бота. Продолжаем без бэкапа бота..."
        return 0
    fi
    
    if [ -d "$BOT_BACKUP_PATH" ]; then
        print_message "INFO" "Архивирование директории бота ${BOLD}${BOT_BACKUP_PATH}${RESET}..."
        local exclude_args=""
        for pattern in $BACKUP_EXCLUDE_PATTERNS; do
            exclude_args+="--exclude=$pattern "
        done
        
        if eval "tar -czf '$BACKUP_DIR/$BOT_DIR_ARCHIVE' $exclude_args -C '$(dirname "$BOT_BACKUP_PATH")' '$(basename "$BOT_BACKUP_PATH")'"; then
            print_message "SUCCESS" "Директория бота успешно заархивирована."
        else
            print_message "ERROR" "Ошибка при архивировании директории бота."
            return 1
        fi
    else
        print_message "WARN" "Директория бота ${BOLD}${BOT_BACKUP_PATH}${RESET} не найдена! Продолжаем без архива директории бота..."
        return 0
    fi
    
    BACKUP_ITEMS+=("$BOT_BACKUP_FILE_DB" "$BOT_DIR_ARCHIVE")
    
    print_message "SUCCESS" "Бэкап бота успешно создан."
    echo ""
    return 0
}

restore_bot_backup() {
    local temp_restore_dir="$1"
    
    local BOT_DUMP_FILE=$(find "$temp_restore_dir" -name "bot_dump_*.sql.gz" | head -n 1)
    local BOT_DIR_ARCHIVE=$(find "$temp_restore_dir" -name "bot_dir_*.tar.gz" | head -n 1)
    
    if [[ -z "$BOT_DUMP_FILE" && -z "$BOT_DIR_ARCHIVE" ]]; then
        return 0
    fi

    clear
    print_message "INFO" "Обнаружен бэкап Telegram бота в архиве."
    echo ""
    read -rp "$(echo -e "${GREEN}[?]${RESET} Восстановить Telegram бота? ${GREEN}${BOLD}Y${RESET}/${RED}${BOLD}N${RESET}: ")" restore_bot_confirm
    
    if [[ "$restore_bot_confirm" != "y" ]]; then
        print_message "INFO" "Восстановление бота пропущено."
        return 0
    fi
    
    echo ""
    print_message "ACTION" "Какой бот был в бэкапе?"
    echo " 1. Бот от Иисуса (remnawave-telegram-shop)"
    echo " 2. Бот от Мачки (remnawave-tg-shop)"
    echo ""
    
    local bot_choice
    local selected_bot_name
    while true; do
        read -rp " ${GREEN}[?]${RESET} Выберите бота: " bot_choice
        case "$bot_choice" in
            1) selected_bot_name="Бот от Иисуса"; break ;;
            2) selected_bot_name="Бот от Мачки"; break ;;
            *) print_message "ERROR" "Неверный ввод." ;;
        esac
    done
    
    echo ""
    print_message "ACTION" "Выберите путь для восстановления бота:"
    if [[ "$selected_bot_name" == "Бот от Иисуса" ]]; then
        echo " 1. /opt/remnawave-telegram-shop"
        echo " 2. /root/remnawave-telegram-shop"
        echo " 3. /opt/stacks/remnawave-telegram-shop"
    else
        echo " 1. /opt/remnawave-tg-shop"
        echo " 2. /root/remnawave-tg-shop"
        echo " 3. /opt/stacks/remnawave-tg-shop"
    fi
    echo " 4. Указать свой путь"
    echo ""
    echo " 0. Назад"
    echo ""

    local restore_path
    local path_choice
    while true; do
        read -rp " ${GREEN}[?]${RESET} Выберите путь: " path_choice
        case "$path_choice" in
        1)
            if [[ "$selected_bot_name" == "Бот от Иисуса" ]]; then
                restore_path="/opt/remnawave-telegram-shop"
            else
                restore_path="/opt/remnawave-tg-shop"
            fi
            break
            ;;
        2)
            if [[ "$selected_bot_name" == "Бот от Иисуса" ]]; then
                restore_path="/root/remnawave-telegram-shop"
            else
                restore_path="/root/remnawave-tg-shop"
            fi
            break
            ;;
        3)
            if [[ "$selected_bot_name" == "Бот от Иисуса" ]]; then
                restore_path="/opt/stacks/remnawave-telegram-shop"
            else
                restore_path="/opt/stacks/remnawave-tg-shop"
            fi
            break
            ;;
        4)
            echo ""
            print_message "INFO" "Введите полный путь для восстановления бота:"
            read -rp " Путь: " custom_restore_path
        
            if [[ -z "$custom_restore_path" ]]; then
                print_message "ERROR" "Путь не может быть пустым."
                echo ""
                read -rp "Нажмите Enter, чтобы продолжить..."
                continue
            fi
        
            if [[ ! "$custom_restore_path" = /* ]]; then
                print_message "ERROR" "Путь должен быть абсолютным (начинаться с /)."
                echo ""
                read -rp "Нажмите Enter, чтобы продолжить..."
                continue
            fi
        
            custom_restore_path="${custom_restore_path%/}"
            restore_path="$custom_restore_path"
            print_message "SUCCESS" "Установлен кастомный путь для восстановления: ${BOLD}${restore_path}${RESET}"
            break
            ;;
        0)
            print_message "INFO" "Восстановление бота отменено."
            return 0
            ;;
        *)
            print_message "ERROR" "Неверный ввод."
            ;;
        esac
    done

    local bot_params=$(get_bot_params "$selected_bot_name")
    IFS='|' read -r BOT_CONTAINER_NAME BOT_VOLUME_NAME BOT_DIR_NAME BOT_SERVICE_NAME <<< "$bot_params"
    
    echo ""
    read -rp " Введите имя пользователя базы данных бота (по умолчанию postgres): " restore_bot_db_user
    restore_bot_db_user="${restore_bot_db_user:-postgres}"
    echo ""
    read -rp "$(echo -e "${GREEN}[?]${RESET} Введите имя базы данных бота (по умолчанию postgres): ")" restore_bot_db_name
    restore_bot_db_name="${restore_bot_db_name:-postgres}"
    echo ""
    print_message "INFO" "Начало восстановления Telegram бота..."
    
    if [[ -d "$restore_path" ]]; then
        print_message "INFO" "Директория ${BOLD}${restore_path}${RESET} существует. Останавливаем контейнеры и очищаем..."
    
        if cd "$restore_path" 2>/dev/null && ([[ -f "docker-compose.yml" ]] || [[ -f "docker-compose.yaml" ]]); then
            print_message "INFO" "Остановка существующих контейнеров бота..."
            docker compose down 2>/dev/null || print_message "WARN" "Не удалось остановить контейнеры (возможно, они уже остановлены)."
        else
            print_message "INFO" "Docker Compose файл (.yml или .yaml) не найден, пропускаем остановку контейнеров."
        fi
    fi
        
    cd /
        
    print_message "INFO" "Удаление старой директории..."
    if [[ -d "$restore_path" ]]; then
        if ! rm -rf "$restore_path"; then
            print_message "ERROR" "Не удалось удалить директорию ${BOLD}${restore_path}${RESET}."
            return 1
        fi
        print_message "SUCCESS" "Старая директория удалена."
    else
        print_message "INFO" "Директория ${BOLD}${restore_path}${RESET} не существует. Это чистая установка."
    fi
    
    print_message "INFO" "Создание новой директории..."
    if ! mkdir -p "$restore_path"; then
        print_message "ERROR" "Не удалось создать директорию ${BOLD}${restore_path}${RESET}."
        return 1
    fi
    print_message "SUCCESS" "Новая директория создана."
    echo ""
    
    if [[ -n "$BOT_DIR_ARCHIVE" ]]; then
        print_message "INFO" "Восстановление директории бота из архива..."
        local temp_extract_dir="$BACKUP_DIR/bot_extract_temp_$$"
        mkdir -p "$temp_extract_dir"
        
        if tar -xzf "$BOT_DIR_ARCHIVE" -C "$temp_extract_dir"; then
            local extracted_dir=$(find "$temp_extract_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1)

            if [[ -n "$extracted_dir" && -d "$extracted_dir" ]]; then
                if cp -rf "$extracted_dir"/. "$restore_path/" 2>/dev/null; then
                    print_message "SUCCESS" "Файлы директории бота восстановлены (папка: $(basename "$extracted_dir"))."
                else
                    print_message "ERROR" "Ошибка при копировании файлов бота."
                    rm -rf "$temp_extract_dir"
                    return 1
                fi
            else
                print_message "ERROR" "Не удалось найти директорию с файлами бота в архиве."
                rm -rf "$temp_extract_dir"
                return 1
            fi
        else
            print_message "ERROR" "Ошибка при распаковке архива директории бота."
            rm -rf "$temp_extract_dir"
            return 1
        fi
        rm -rf "$temp_extract_dir"
    else
        print_message "WARN" "Архив директории бота не найден в бэкапе."
        return 1
    fi
    
    print_message "INFO" "Проверка и удаление старых томов БД..."
    if docker volume ls -q | grep -Fxq "$BOT_VOLUME_NAME"; then
        local containers_using_volume
        containers_using_volume=$(docker ps -aq --filter volume="$BOT_VOLUME_NAME")
    
        if [[ -n "$containers_using_volume" ]]; then
            print_message "INFO" "Найдены контейнеры, использующие том $BOT_VOLUME_NAME. Удаляем..."
            docker rm -f $containers_using_volume >/dev/null 2>&1
        fi
    
        if docker volume rm "$BOT_VOLUME_NAME" >/dev/null 2>&1; then
            print_message "SUCCESS" "Старый том БД $BOT_VOLUME_NAME удален."
        else
            print_message "WARN" "Не удалось удалить том $BOT_VOLUME_NAME."
        fi
    else
        print_message "INFO" "Старых томов БД не найдено."
    fi
    echo ""
    
    if ! cd "$restore_path"; then
        print_message "ERROR" "Не удалось перейти в восстановленную директорию ${BOLD}${restore_path}${RESET}."
        return 1
    fi
    
    if [[ ! -f "docker-compose.yml" && ! -f "docker-compose.yaml" ]]; then
    print_message "ERROR" "Файл docker-compose.yml или docker-compose.yaml не найден в восстановленной директории."
    return 1
    fi
    
    print_message "INFO" "Запуск контейнера БД бота..."
    if ! docker compose up -d "$BOT_SERVICE_NAME"; then
        print_message "ERROR" "Не удалось запустить контейнер БД бота."
        return 1
    fi
    
    echo ""
    print_message "INFO" "Ожидание готовности БД бота..."
    local wait_count=0
    local max_wait=60
    
    until [ "$(docker inspect --format='{{.State.Health.Status}}' "$BOT_CONTAINER_NAME" 2>/dev/null)" == "healthy" ]; do
        sleep 2
        echo -n "."
        wait_count=$((wait_count + 1))
        if [ $wait_count -gt $max_wait ]; then
            echo ""
            print_message "ERROR" "Превышено время ожидания готовности БД бота."
            return 1
        fi
    done
    echo ""
    print_message "SUCCESS" "БД бота готова к работе."
    
    if [[ -n "$BOT_DUMP_FILE" ]]; then
        print_message "INFO" "Восстановление БД бота из дампа..."
        local BOT_DUMP_UNCOMPRESSED="${BOT_DUMP_FILE%.gz}"
        
        if ! gunzip "$BOT_DUMP_FILE"; then
            print_message "ERROR" "Не удалось распаковать дамп БД бота."
            return 1
        fi
        
        mkdir -p "$temp_restore_dir"

        if ! docker exec -i "$BOT_CONTAINER_NAME" psql -q -U "$restore_bot_db_user" -d "$restore_bot_db_name" 2> "$temp_restore_dir/restore_errors.log" < "$BOT_DUMP_UNCOMPRESSED"; then
            print_message "ERROR" "Ошибка при восстановлении БД бота."
            echo ""
            print_message "WARN" "${YELLOW}Лог ошибок восстановления:${RESET}"
            cat "$temp_restore_dir/restore_errors.log"
            [[ -d "$temp_restore_dir" ]] && rm -rf "$temp_restore_dir"
            read -rp "Нажмите Enter для возврата в меню..."
            return 1
        fi

        print_message "SUCCESS" "БД бота успешно восстановлена."
    else
        print_message "WARN" "Дамп БД бота не найден в архиве."
    fi
    
    echo ""
    print_message "INFO" "Запуск всех контейнеров бота..."
    if ! docker compose up -d; then
        print_message "ERROR" "Не удалось запустить все контейнеры бота."
        return 1
    fi
    
    sleep 3
    echo ""
    print_message "SUCCESS" "Telegram бот успешно восстановлен и запущен!"
    return 0
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
BOT_BACKUP_ENABLED="$BOT_BACKUP_ENABLED"
BOT_BACKUP_PATH="$BOT_BACKUP_PATH"
BOT_BACKUP_SELECTED="$BOT_BACKUP_SELECTED"
BOT_BACKUP_DB_USER="$BOT_BACKUP_DB_USER"
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
        
        local config_updated=false

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
            echo " 1. /opt/remnawave"
            echo " 2. /root/remnawave"
            echo " 3. /opt/stacks/remnawave"
            echo " 4. Указать свой путь"
            echo ""

            local remnawave_path_choice
            while true; do
                read -rp " ${GREEN}[?]${RESET} Выберите вариант: " remnawave_path_choice
                case "$remnawave_path_choice" in
                1) REMNALABS_ROOT_DIR="/opt/remnawave"; break ;;
                2) REMNALABS_ROOT_DIR="/root/remnawave"; break ;;
                3) REMNALABS_ROOT_DIR="/opt/stacks/remnawave"; break ;;
                4) 
                    echo ""
                    print_message "INFO" "Введите полный путь к директории панели Remnawave:"
                    read -rp " Путь: " custom_remnawave_path
    
                    if [[ -z "$custom_remnawave_path" ]]; then
                        print_message "ERROR" "Путь не может быть пустым."
                        echo ""
                        read -rp "Нажмите Enter, чтобы продолжить..."
                        continue
                    fi
    
                    if [[ ! "$custom_remnawave_path" = /* ]]; then
                        print_message "ERROR" "Путь должен быть абсолютным (начинаться с /)."
                        echo ""
                        read -rp "Нажмите Enter, чтобы продолжить..."
                        continue
                    fi
    
                    custom_remnawave_path="${custom_remnawave_path%/}"
    
                    if [[ ! -d "$custom_remnawave_path" ]]; then
                        print_message "WARN" "Директория ${BOLD}${custom_remnawave_path}${RESET} не существует."
                        read -rp "$(echo -e "${GREEN}[?]${RESET} Продолжить с этим путем? ${GREEN}${BOLD}Y${RESET}/${RED}${BOLD}N${RESET}: ")" confirm_custom_path
                        if [[ "$confirm_custom_path" != "y" ]]; then
                            echo ""
                            read -rp "Нажмите Enter, чтобы продолжить..."
                            continue
                        fi
                    fi
    
                    REMNALABS_ROOT_DIR="$custom_remnawave_path"
                    print_message "SUCCESS" "Установлен кастомный путь: ${BOLD}${REMNALABS_ROOT_DIR}${RESET}"
                    break 
                    ;;
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
        fi

        if $config_updated; then
            save_config
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
            echo " 1. /opt/remnawave"
            echo " 2. /root/remnawave"
            echo " 3. /opt/stacks/remnawave"
            echo " 4. Указать свой путь"
            echo ""

            local remnawave_path_choice
            while true; do
                read -rp " ${GREEN}[?]${RESET} Выберите вариант: " remnawave_path_choice
                case "$remnawave_path_choice" in
                1) REMNALABS_ROOT_DIR="/opt/remnawave"; break ;;
                2) REMNALABS_ROOT_DIR="/root/remnawave"; break ;;
                3) REMNALABS_ROOT_DIR="/opt/stacks/remnawave"; break ;;
                4) 
                    echo ""
                    print_message "INFO" "Введите полный путь к директории панели Remnawave:"
                    read -rp " Путь: " custom_remnawave_path
    
                    if [[ -z "$custom_remnawave_path" ]]; then
                        print_message "ERROR" "Путь не может быть пустым."
                        echo ""
                        read -rp "Нажмите Enter, чтобы продолжить..."
                        continue
                    fi
    
                    if [[ ! "$custom_remnawave_path" = /* ]]; then
                        print_message "ERROR" "Путь должен быть абсолютным (начинаться с /)."
                        echo ""
                        read -rp "Нажмите Enter, чтобы продолжить..."
                        continue
                    fi
    
                    custom_remnawave_path="${custom_remnawave_path%/}"
    
                    if [[ ! -d "$custom_remnawave_path" ]]; then
                        print_message "WARN" "Директория ${BOLD}${custom_remnawave_path}${RESET} не существует."
                        read -rp "$(echo -e "${GREEN}[?]${RESET} Продолжить с этим путем? ${GREEN}${BOLD}Y${RESET}/${RED}${BOLD}N${RESET}: ")" confirm_custom_path
                        if [[ "$confirm_custom_path" != "y" ]]; then
                            echo ""
                            read -rp "Нажмите Enter, чтобы продолжить..."
                            continue
                        fi
                    fi
    
                    REMNALABS_ROOT_DIR="$custom_remnawave_path"
                    print_message "SUCCESS" "Установлен кастомный путь: ${BOLD}${REMNALABS_ROOT_DIR}${RESET}"
                    break 
                    ;;
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

    local url="https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
    local data_params=(
        -d chat_id="$CHAT_ID"
        -d text="$escaped_message"
    )

    [[ -n "$parse_mode" ]] && data_params+=(-d parse_mode="$parse_mode")
    [[ -n "$TG_MESSAGE_THREAD_ID" ]] && data_params+=(-d message_thread_id="$TG_MESSAGE_THREAD_ID")

    local response
    response=$(curl -s -X POST "$url" "${data_params[@]}" -w "\n%{http_code}")
    local body=$(echo "$response" | head -n -1)
    local http_code=$(echo "$response" | tail -n1)

    if [[ "$http_code" -eq 200 ]]; then
        return 0
    else
        echo -e "${RED}❌ Ошибка отправки сообщения в Telegram. Код: ${BOLD}$http_code${RESET}"
        echo -e "Ответ от Telegram: ${body}"
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
    
    mkdir -p "$BACKUP_DIR" || { 
        echo -e "${RED}❌ Ошибка: Не удалось создать каталог для бэкапов. Проверьте права доступа.${RESET}"
        send_telegram_message "❌ Ошибка: Не удалось создать каталог бэкапов ${BOLD}$BACKUP_DIR${RESET}." "None"
        exit 1
    }
    
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
    print_message "INFO" "Архивирование директории Remnawave и создание итогового бэкапа..."
    BACKUP_ITEMS=("$BACKUP_FILE_DB")
    
    REMNAWAVE_DIR_ARCHIVE="remnawave_dir_${TIMESTAMP}.tar.gz"
    
    if [ -d "$REMNALABS_ROOT_DIR" ]; then
        print_message "INFO" "Архивирование директории ${BOLD}${REMNALABS_ROOT_DIR}${RESET}..."
        
        local exclude_args=""
        for pattern in $BACKUP_EXCLUDE_PATTERNS; do
            exclude_args+="--exclude=$pattern "
        done
        
        if eval "tar -czf '$BACKUP_DIR/$REMNAWAVE_DIR_ARCHIVE' $exclude_args -C '$(dirname "$REMNALABS_ROOT_DIR")' '$(basename "$REMNALABS_ROOT_DIR")'"; then
            print_message "SUCCESS" "Директория Remnawave успешно заархивирована."
            BACKUP_ITEMS+=("$REMNAWAVE_DIR_ARCHIVE")
        else
            STATUS=$?
            echo -e "${RED}❌ Ошибка при архивировании директории Remnawave. Код выхода: ${BOLD}$STATUS${RESET}.${RESET}"
            local error_msg="❌ Ошибка при архивировании директории Remnawave. Код выхода: ${BOLD}${STATUS}${RESET}"
            if [[ "$UPLOAD_METHOD" == "telegram" ]]; then
                send_telegram_message "$error_msg" "None"
            fi
            exit $STATUS
        fi
    else
        print_message "ERROR" "Директория ${BOLD}${REMNALABS_ROOT_DIR}${RESET} не найдена!"
        exit 1
    fi
    
    echo ""

    create_bot_backup

    if ! tar -czf "$BACKUP_DIR/$BACKUP_FILE_FINAL" -C "$BACKUP_DIR" "${BACKUP_ITEMS[@]}"; then
        STATUS=$?
        echo -e "${RED}❌ Ошибка при создании итогового архива бэкапа. Код выхода: ${BOLD}$STATUS${RESET}.${RESET}"
        local error_msg="❌ Ошибка при создании итогового архива бэкапа. Код выхода: ${BOLD}${STATUS}${RESET}"
        if [[ "$UPLOAD_METHOD" == "telegram" ]]; then
            send_telegram_message "$error_msg" "None"
        fi
        exit $STATUS
    fi
    
    print_message "SUCCESS" "Итоговый архив бэкапа успешно создан: ${BOLD}${BACKUP_DIR}/${BACKUP_FILE_FINAL}${RESET}"
    echo ""
    
    print_message "INFO" "Очистка промежуточных файлов бэкапа..."
    for item in "${BACKUP_ITEMS[@]}"; do
        rm -f "$BACKUP_DIR/$item"
    done
    print_message "SUCCESS" "Промежуточные файлы удалены."
    echo ""
    
    print_message "INFO" "Отправка бэкапа (${UPLOAD_METHOD})..."
    local DATE=$(date +'%Y-%m-%d %H:%M:%S')
    local bot_status=""
    if [[ "$BOT_BACKUP_ENABLED" == "true" ]]; then
        bot_status=$'\n🤖 *Telegram бот:* включен в бэкап'
    fi

    local caption_text=$'💾 #backup_success\n➖➖➖➖➖➖➖➖➖\n✅ *Бэкап успешно создан*\n🌊 *Remnawave:* '"${REMNAWAVE_VERSION}${bot_status}"$'\n📁 *БД + директория*\n📅 *Дата:* '"${DATE}"
    local backup_size=$(du -h "$BACKUP_DIR/$BACKUP_FILE_FINAL" | awk '{print $1}')

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
                local tg_success_message=$'💾 #backup_success\n➖➖➖➖➖➖➖➖➖\n✅ *Бэкап успешно создан и отправлен в Google Drive*\n🌊 *Remnawave:* '"${REMNAWAVE_VERSION}${bot_status}"$'\n📁 *БД и директория*\n📏 *Размер:* '"${backup_size}"$'\n📅 *Дата:* '"${DATE}"
                
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

                echo "Выберите вариант автоматической отправки:"
                echo "  1) Ввести время (например: 08:00 12:00 18:00)"
                echo "  2) Ежечасно"
                echo "  3) Ежедневно"
                read -rp "Ваш выбор: " send_choice
                echo ""

                cron_times_to_write=()
                user_friendly_times_local=""
                invalid_format=false

                if [[ "$send_choice" == "1" ]]; then
                    echo "Введите желаемое время отправки по UTC+0 (например, 08:00 12:00):"
                    read -rp "Время через пробел: " times
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
                elif [[ "$send_choice" == "2" ]]; then
                    cron_times_to_write=("@hourly")
                    user_friendly_times_local="@hourly"
                elif [[ "$send_choice" == "3" ]]; then
                    cron_times_to_write=("@daily")
                    user_friendly_times_local="@daily"
                else
                    print_message "ERROR" "Неверный выбор."
                    continue
                fi

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
                    if [[ "$time_entry_local" == "@hourly" ]] || [[ "$time_entry_local" == "@daily" ]]; then
                        echo "$time_entry_local $SCRIPT_PATH backup >> /var/log/rw_backup_cron.log 2>&1" >> "$temp_crontab_file"
                    else
                        echo "$time_entry_local * * * $SCRIPT_PATH backup >> /var/log/rw_backup_cron.log 2>&1" >> "$temp_crontab_file"
                    fi
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
    echo ""
    
    if ! compgen -G "$BACKUP_DIR/remnawave_backup_*.tar.gz" > /dev/null; then
        print_message "ERROR" "Ошибка: Не найдено файлов бэкапов в ${BOLD}${BACKUP_DIR}${RESET}. Пожалуйста, поместите файл бэкапа в этот каталог."
        echo ""
        read -rp "Нажмите Enter для возврата в меню..."
        return
    fi
    
    readarray -t SORTED_BACKUP_FILES < <(find "$BACKUP_DIR" -maxdepth 1 -name "remnawave_backup_*.tar.gz" -printf "%T@ %p\n" | sort -nr | cut -d' ' -f2-)
    
    if [ ${#SORTED_BACKUP_FILES[@]} -eq 0 ]; then
        print_message "ERROR" "Ошибка: Не найдено файлов бэкапов в ${BOLD}${BACKUP_DIR}${RESET}."
        read -rp "Нажмите Enter для возврата в меню..."
        return
    fi
    
    echo ""
    echo "Выберите файл для восстановления:"
    local i=1
    for file in "${SORTED_BACKUP_FILES[@]}"; do
        echo " $i) ${file##*/}"
        i=$((i+1))
    done
    echo ""
    echo " 0) Вернуться в главное меню"
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
    echo "       и директорию Remnawave"
    echo ""
    print_message "INFO" "В конфигурации скрипта вы указали имя пользователя БД: ${BOLD}${GREEN}${DB_USER}${RESET}"
    read -rp "$(echo -e "${GREEN}[?]${RESET} Введите ${GREEN}${BOLD}Y${RESET}/${RED}${BOLD}N${RESET} для продолжения: ")" db_user_confirm
    
    if [[ ! "$db_user_confirm" =~ ^[Yy]$ ]]; then
        print_message "INFO" "Операция восстановления отменена пользователем."
        read -rp "Нажмите Enter для возврата в меню..."
        return
    fi

    echo ""
    read -rp "$(echo -e "${GREEN}[?]${RESET} Теперь введите имя базы данных панели (по умолчанию postgres): ")" restore_db_name
    restore_db_name="${restore_db_name:-postgres}"
    
    clear
    
    print_message "INFO" "Начало процесса полного сброса и восстановления Remnawave..."
    echo ""
    
    if [[ -d "$REMNALABS_ROOT_DIR" ]]; then
        print_message "INFO" "Директория ${BOLD}${REMNALABS_ROOT_DIR}${RESET} существует. Останавливаем контейнеры и очищаем..."
        
        if cd "$REMNALABS_ROOT_DIR" 2>/dev/null && [[ -f "docker-compose.yml" ]]; then
            print_message "INFO" "Остановка существующих контейнеров Remnawave, ожидайте..."
            docker compose down 2>/dev/null || print_message "WARN" "Не удалось остановить контейнеры (возможно, они уже остановлены)."
        else
            print_message "INFO" "Docker Compose файл не найден, пропускаем остановку контейнеров."
        fi
        
        cd /
        
        print_message "INFO" "Удаление старой директории Remnawave..."
        if ! rm -rf "$REMNALABS_ROOT_DIR"; then
            print_message "ERROR" "Не удалось удалить директорию ${BOLD}${REMNALABS_ROOT_DIR}${RESET}."
            read -rp "Нажмите Enter для возврата в меню..."
            return 1
        fi
        print_message "SUCCESS" "Старая директория удалена."
    else
        print_message "INFO" "Директория ${BOLD}${REMNALABS_ROOT_DIR}${RESET} не существует. Это чистая установка."
    fi
    
    print_message "INFO" "Создание новой директории Remnawave..."
    if ! mkdir -p "$REMNALABS_ROOT_DIR"; then
        print_message "ERROR" "Не удалось создать директорию ${BOLD}${REMNALABS_ROOT_DIR}${RESET}."
        read -rp "Нажмите Enter для возврата в меню..."
        return 1
    fi
    print_message "SUCCESS" "Новая директория создана."
    
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
    
    print_message "INFO" "Поиск архива директории Remnawave в бэкапе..."
    local REMNAWAVE_DIR_ARCHIVE=$(find "$temp_restore_dir" -name "remnawave_dir_*.tar.gz" | head -n 1)
    
    if [[ -n "$REMNAWAVE_DIR_ARCHIVE" ]]; then
        print_message "INFO" "Найден архив директории Remnawave. Начинаю восстановление..."
        
        local temp_extract_dir="$BACKUP_DIR/extract_temp_$$"
        mkdir -p "$temp_extract_dir"
        
        if tar -xzf "$REMNAWAVE_DIR_ARCHIVE" -C "$temp_extract_dir"; then
            print_message "SUCCESS" "Архив директории успешно распакован."
            
            local extracted_dir=$(find "$temp_extract_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1)

            if [[ -n "$extracted_dir" && -d "$extracted_dir" ]]; then
                print_message "INFO" "Копирование файлов из архива в директорию Remnawave (папка в архиве: $(basename "$extracted_dir"))..."

                if cp -rf "$extracted_dir"/. "$REMNALABS_ROOT_DIR/" 2>/dev/null; then
                    print_message "SUCCESS" "Файлы директории Remnawave успешно восстановлены."
                else
                    print_message "ERROR" "Ошибка при копировании файлов Remnawave."
                    rm -rf "$temp_extract_dir"
                    [[ -n "$temp_restore_dir" && -d "$temp_restore_dir" ]] && rm -rf "$temp_restore_dir"
                    read -rp "Нажмите Enter для возврата в меню..."
                    return 1
                fi
            else
                print_message "ERROR" "Не удалось найти директорию с файлами Remnawave в архиве."
                rm -rf "$temp_extract_dir"
                [[ -n "$temp_restore_dir" && -d "$temp_restore_dir" ]] && rm -rf "$temp_restore_dir"
                read -rp "Нажмите Enter для возврата в меню..."
                return 1
            fi
            
            rm -rf "$temp_extract_dir"
        else
            print_message "ERROR" "Ошибка при распаковке архива директории."
            rm -rf "$temp_extract_dir"
            [[ -n "$temp_restore_dir" && -d "$temp_restore_dir" ]] && rm -rf "$temp_restore_dir"
            read -rp "Нажмите Enter для возврата в меню..."
            return 1
        fi
    else
        print_message "WARN" "Архив директории Remnawave не найден в бэкапе."
        print_message "INFO" "Возможно, это старый формат бэкапа с отдельными файлами .env"
        
        ENV_NODE_RESTORE_PATH="$REMNALABS_ROOT_DIR/$ENV_NODE_FILE"
        ENV_RESTORE_PATH="$REMNALABS_ROOT_DIR/$ENV_FILE"
        
        if [ -f "$temp_restore_dir/$ENV_NODE_FILE" ]; then
            print_message "INFO" "Найден файл ${BOLD}${ENV_NODE_FILE}${RESET} (старый формат). Восстанавливаем..."
            mv "$temp_restore_dir/$ENV_NODE_FILE" "$ENV_NODE_RESTORE_PATH" || {
                print_message "ERROR" "Ошибка при восстановлении ${BOLD}${ENV_NODE_FILE}${RESET}."
                [[ -n "$temp_restore_dir" && -d "$temp_restore_dir" ]] && rm -rf "$temp_restore_dir"
                read -rp "Нажмите Enter для возврата в меню..."
                return 1
            }
            print_message "SUCCESS" "Файл ${BOLD}${ENV_NODE_FILE}${RESET} восстановлен."
        fi
        
        if [ -f "$temp_restore_dir/$ENV_FILE" ]; then
            print_message "INFO" "Найден файл ${BOLD}${ENV_FILE}${RESET} (старый формат). Восстанавливаем..."
            mv "$temp_restore_dir/$ENV_FILE" "$ENV_RESTORE_PATH" || {
                print_message "ERROR" "Ошибка при восстановлении ${BOLD}${ENV_FILE}${RESET}."
                [[ -n "$temp_restore_dir" && -d "$temp_restore_dir" ]] && rm -rf "$temp_restore_dir"
                read -rp "Нажмите Enter для возврата в меню..."
                return 1
            }
            print_message "SUCCESS" "Файл ${BOLD}${ENV_FILE}${RESET} восстановлен."
        fi
    fi
    
    print_message "INFO" "Проверка и удаление старых томов БД Remnawave..."
    if docker volume ls -q | grep -q "remnawave-db-data"; then
        if docker volume rm remnawave-db-data 2>/dev/null; then
            print_message "SUCCESS" "Старый том БД remnawave-db-data удален."
        else
            print_message "WARN" "Не удалось удалить том remnawave-db-data (возможно, используется контейнером)."
        fi
    else
        print_message "INFO" "Старых томов БД не найдено."
    fi
    
    if ! cd "$REMNALABS_ROOT_DIR"; then
        print_message "ERROR" "Не удалось перейти в восстановленную директорию ${BOLD}${REMNALABS_ROOT_DIR}${RESET}."
        [[ -n "$temp_restore_dir" && -d "$temp_restore_dir" ]] && rm -rf "$temp_restore_dir"
        read -rp "Нажмите Enter для возврата в меню..."
        return 1
    fi
    
    if [[ ! -f "docker-compose.yml" ]]; then
        print_message "ERROR" "Файл docker-compose.yml не найден в восстановленной директории."
        [[ -n "$temp_restore_dir" && -d "$temp_restore_dir" ]] && rm -rf "$temp_restore_dir"
        read -rp "Нажмите Enter для возврата в меню..."
        return 1
    fi
    
    echo ""
    print_message "INFO" "Запуск контейнера с базой данных Remnawave..."
    docker compose rm -f remnawave-db > /dev/null 2>&1
    
    if ! docker compose up -d remnawave-db; then
        print_message "ERROR" "Не удалось запустить контейнер БД Remnawave."
        [[ -n "$temp_restore_dir" && -d "$temp_restore_dir" ]] && rm -rf "$temp_restore_dir"
        read -rp "Нажмите Enter для возврата в меню..."
        return 1
    fi

    echo ""
    print_message "INFO" "Ожидание готовности базы данных..."
    local wait_count=0
    local max_wait=60
    
    until [ "$(docker inspect --format='{{.State.Health.Status}}' remnawave-db)" == "healthy" ]; do
        sleep 2
        echo -n "."
        wait_count=$((wait_count + 1))
        if [ $wait_count -gt $max_wait ]; then
            echo ""
            print_message "ERROR" "Превышено время ожидания готовности БД Remnawave."
            [[ -n "$temp_restore_dir" && -d "$temp_restore_dir" ]] && rm -rf "$temp_restore_dir"
            read -rp "Нажмите Enter для возврата в меню..."
            return 1
        fi
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
    
    if ! docker exec -i remnawave-db psql -q -U "${DB_USER}" -d "$restore_db_name" > /dev/null 2> "$temp_restore_dir/restore_errors.log" < "$DUMP_FILE"; then
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
    print_message "INFO" "Запуск всех контейнеров Remnawave..."
    if ! docker compose up -d; then
        print_message "ERROR" "Не удалось запустить все контейнеры Remnawave."
        read -rp "Нажмите Enter для возврата в меню..."
        return 1
    fi
    
    echo ""
    restore_bot_backup "$temp_restore_dir"
    
    print_message "INFO" "Удаление временных файлов восстановления..."
    [[ -n "$temp_restore_dir" && -d "$temp_restore_dir" ]] && rm -rf "$temp_restore_dir"
    
    sleep 3
    
    echo ""
    print_message "SUCCESS" "Восстановление завершено. Все контейнеры запущены."
    
    REMNAWAVE_VERSION=$(get_remnawave_version)
    local restore_msg=$'💾 #restore_success\n➖➖➖➖➖➖➖➖➖\n✅ *Восстановление успешно завершено*\n🌊 *Remnawave:* '"${REMNAWAVE_VERSION}"
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

configure_settings() {
    while true; do
        clear
        echo -e "${GREEN}${BOLD}Настройка конфигурации скрипта${RESET}"
        echo ""
        echo "   1. Настройки Telegram"
        echo "   2. Настройки Google Drive"
        echo "   3. Имя пользователя БД Remnawave"
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
                echo " 1. /opt/remnawave"
                echo " 2. /root/remnawave"
                echo " 3. /opt/stacks/remnawave"
                echo " 4. Указать свой путь"
                echo ""
                echo " 0. Назад"
                echo ""

                local new_remnawave_path_choice
                while true; do
                    read -rp " ${GREEN}[?]${RESET} Выберите вариант: " new_remnawave_path_choice
                    case "$new_remnawave_path_choice" in
                    1) REMNALABS_ROOT_DIR="/opt/remnawave"; break ;;
                    2) REMNALABS_ROOT_DIR="/root/remnawave"; break ;;
                    3) REMNALABS_ROOT_DIR="/opt/stacks/remnawave"; break ;;
                    4) 
                        echo ""
                        print_message "INFO" "Введите полный путь к директории панели Remnawave:"
                        read -rp " Путь: " new_custom_remnawave_path
        
                        if [[ -z "$new_custom_remnawave_path" ]]; then
                            print_message "ERROR" "Путь не может быть пустым."
                            echo ""
                            read -rp "Нажмите Enter, чтобы продолжить..."
                            continue
                        fi
        
                        if [[ ! "$new_custom_remnawave_path" = /* ]]; then
                            print_message "ERROR" "Путь должен быть абсолютным (начинаться с /)."
                            echo ""
                            read -rp "Нажмите Enter, чтобы продолжить..."
                            continue
                        fi
        
                        new_custom_remnawave_path="${new_custom_remnawave_path%/}"
        
                        if [[ ! -d "$new_custom_remnawave_path" ]]; then
                            print_message "WARN" "Директория ${BOLD}${new_custom_remnawave_path}${RESET} не существует."
                            read -rp "$(echo -e "${GREEN}[?]${RESET} Продолжить с этим путем? ${GREEN}${BOLD}Y${RESET}/${RED}${BOLD}N${RESET}: ")" confirm_new_custom_path
                            if [[ "$confirm_new_custom_path" != "y" ]]; then
                                echo ""
                                read -rp "Нажмите Enter, чтобы продолжить..."
                                continue
                            fi
                        fi
        
                        REMNALABS_ROOT_DIR="$new_custom_remnawave_path"
                        print_message "SUCCESS" "Установлен новый кастомный путь: ${BOLD}${REMNALABS_ROOT_DIR}${RESET}"
                        break 
                        ;;
                    0) 
                        return
                        ;;
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
            echo -e "${BOLD}${LIGHT_GRAY}Версия: ${VERSION} ${RED}доступно обновление${RESET}"
        else
            echo -e "${BOLD}${LIGHT_GRAY}Версия: ${VERSION}${RESET}"
        fi
        echo ""
        echo "   1. Создание бэкапа вручную"
        echo "   2. Восстановление из бэкапа"
        echo ""
        echo "   3. Настройка бэкапа Telegram бота"
        echo "   4. Настройка автоматической отправки и уведомлений"
        echo "   5. Настройка способа отправки"
        echo "   6. Настройка конфигурации скрипта"
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
            3) configure_bot_backup ;;
            4) setup_auto_send ;;
            5) configure_upload_method ;;
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
