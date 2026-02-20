#!/bin/bash

set -e

VERSION="2.2.1"
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
        print_message "WARN" "Managing the ${BOLD}${SYMLINK_PATH}${RESET} symbolic link requires root privileges. Skip the setting."
        return 1
    fi

    if [[ -L "$SYMLINK_PATH" && "$(readlink -f "$SYMLINK_PATH")" == "$SCRIPT_PATH" ]]; then
        print_message "SUCCESS" "The symbolic link ${BOLD}${SYMLINK_PATH}${RESET} is already configured and points to ${BOLD}${SCRIPT_PATH}${RESET}."
        return 0
    fi

    print_message "INFO" "Create or update a symbolic link ${BOLD}${SYMLINK_PATH}${RESET}..."
    rm -f "$SYMLINK_PATH"
    if [[ -d "$(dirname "$SYMLINK_PATH")" ]]; then
        if ln -s "$SCRIPT_PATH" "$SYMLINK_PATH"; then
            print_message "SUCCESS" "The symbolic link ${BOLD}${SYMLINK_PATH}${RESET} was successfully configured."
        else
            print_message "ERROR" "Failed to create symbolic link ${BOLD}${SYMLINK_PATH}${RESET}. Check your permissions."
            return 1
        fi
    else
        print_message "ERROR" "Directory ${BOLD}$(dirname"$SYMLINK_PATH")${RESET} not found. The symbolic link was not created."
        return 1
    fi
    echo ""
    return 0
}

configure_bot_backup() {
    while true; do
        clear
        echo -e "${GREEN}${BOLD}Setting up a Telegram bot backup${RESET}"
        echo ""
        
        if [[ "$BOT_BACKUP_ENABLED" == "true" ]]; then
            echo -e "Bot: ${BOLD}${GREEN}${BOT_BACKUP_SELECTED}${RESET}"
            echo -e "Path: ${BOLD}${WHITE}${BOT_BACKUP_PATH}${RESET}"
            
            if [[ "$SKIP_PANEL_BACKUP" == "true" ]]; then
                echo -e "Mode: ${BOLD}${RED}BOT ONLY${RESET}"
            else
                echo -e "Mode: ${BOLD}${GREEN}PANEL + BOT${RESET}"
            fi
        else
            print_message "INFO" "Bot backup: ${RED}${BOLD}OFF${RESET}"
            if [[ "$SKIP_PANEL_BACKUP" == "true" ]]; then
                print_message "WARN" "Attention: The panel backup is also skipped (nothing is backed up!)"
            else
                print_message "INFO" "Mode: Remnawave panel backup only"
            fi
        fi
        echo ""
        
        echo "1. Configure / Change bot parameters"
        
        if [[ "$BOT_BACKUP_ENABLED" == "true" ]]; then
            if [[ "$SKIP_PANEL_BACKUP" == "true" ]]; then
                if [[ "$REMNALABS_ROOT_DIR" != "none" && -n "$REMNALABS_ROOT_DIR" ]]; then
                    echo "2. Re-enable panel backup (Panel + Bot mode)"
                fi
            else
                echo "2. Exclude panel backup (Bot Only Mode)"
            fi
        fi

        echo "3. Completely disable bot backup"
        echo ""
        echo "0. Return to main menu"
        echo ""
        
        read -rp "${GREEN}[?]${RESET} Select an item:" choice
        
        case $choice in
            1)
                clear
                echo -e "${GREEN}${BOLD}Selecting a bot for backup${RESET}"
                echo ""
                echo "1. Bot from Jesus (remnawave-telegram-shop)"
                echo "2. Bot from Machka (remnawave-tg-shop)"
                echo "3. Bot from Snoups (remnashop)"
                echo "0. Back"
                echo ""
                
                local bot_choice
                read -rp "${GREEN}[?]${RESET} Your choice:" bot_choice
                case "$bot_choice" in
                    1) BOT_BACKUP_SELECTED="Bot from Jesus"; bot_folder="remnawave-telegram-shop" ;;
                    2) BOT_BACKUP_SELECTED="Bot from Machka"; bot_folder="remnawave-tg-shop" ;;
                    3) BOT_BACKUP_SELECTED="Bot from Snoups"; bot_folder="remnashop" ;;
                    0) continue ;;
                    *) print_message "ERROR" "Invalid input"; sleep 1; continue ;;
                esac
                
                echo ""
                print_message "ACTION" "Select the path to the bot directory:"
                echo " 1. /opt/$bot_folder"
                echo " 2. /root/$bot_folder"
                echo " 3. /opt/stacks/$bot_folder"
                echo "4. Show your path"
                echo ""
                
                local path_choice
                read -rp "${GREEN}[?]${RESET} Select an item:" path_choice
                case "$path_choice" in
                    1) BOT_BACKUP_PATH="/opt/$bot_folder" ;;
                    2) BOT_BACKUP_PATH="/root/$bot_folder" ;;
                    3) BOT_BACKUP_PATH="/opt/stacks/$bot_folder" ;;
                    4) 
                        echo ""
                        read -rp "Enter full path:" custom_bot_path
                        if [[ -z "$custom_bot_path" || ! "$custom_bot_path" = /* ]]; then
                            print_message "ERROR" "The path must be absolute!"
                            sleep 2; continue
                        fi
                        BOT_BACKUP_PATH="${custom_bot_path%/}" 
                        ;;
                    *) print_message "ERROR" "Invalid input"; sleep 1; continue ;;
                esac

                echo ""
                read -rp " $(echo -e "${GREEN}[?]${RESET} Database username for the bot (postgres by default):")" bot_db_user
                BOT_BACKUP_DB_USER="${bot_db_user:-postgres}"

                if [[ "$SKIP_PANEL_BACKUP" == "false" ]]; then
                    echo ""
                    print_message "ACTION" "Disable panel backup and leave ONLY the bot?"
                    read -rp " $(echo -e "${GREEN}[?]${RESET} Enter (${GREEN}y${RESET}/${RED}n${RESET}):")" only_bot_confirm
                    if [[ "$only_bot_confirm" =~ ^[yY]$ ]]; then
                        SKIP_PANEL_BACKUP="true"
                    fi
                fi

                BOT_BACKUP_ENABLED="true"
                save_config
                print_message "SUCCESS" "The bot settings are saved and activated."
                read -rp "Press Enter..."
                ;;

            2)
                if [[ "$SKIP_PANEL_BACKUP" == "true" ]]; then
                    SKIP_PANEL_BACKUP="false"
                    print_message "SUCCESS" "Mode changed: Panel + Bot"
                else
                    SKIP_PANEL_BACKUP="true"
                    print_message "SUCCESS" "Mode changed: Bot only"
                fi
                save_config
                read -rp "Press Enter..."
                ;;

            3)
                BOT_BACKUP_ENABLED="false"
                BOT_BACKUP_PATH=""
                BOT_BACKUP_SELECTED=""
                
                echo ""
                print_message "SUCCESS" "Bot backup is disabled."

                if [[ "$SKIP_PANEL_BACKUP" == "true" && "$REMNALABS_ROOT_DIR" != "none" && -n "$REMNALABS_ROOT_DIR" ]]; then
                    print_message "WARN" "Currently, panel backups are also disabled in this mode."
                    read -rp " $(echo -e "${GREEN}[?]${RESET} Re-enable panel backup? (y/n):")" restore_p
                    if [[ "$restore_p" =~ ^[yY]$ ]]; then
                        SKIP_PANEL_BACKUP="false"
                        print_message "SUCCESS" "The panel backup has been restored."
                    fi
                fi
                
                save_config
                read -rp "Press Enter to continue..."
                ;;

            0) break ;;
            *) print_message "ERROR" "Invalid input" ; sleep 1 ;;
        esac
    done
}

get_bot_params() {
    local bot_name="$1"
    
    case "$bot_name" in
        "Bot from Jesus")
            echo "remnawave-telegram-shop-db|remnawave-telegram-shop-db-data|remnawave-telegram-shop|db"
            ;;
        "Bot from Machka")
            echo "remnawave-tg-shop-db|remnawave-tg-shop-db-data|remnawave-tg-shop|remnawave-tg-shop-db"
            ;;
        "Bot from Snoups")
            echo "remnashop-db|remnashop-db-data|remnashop|remnashop-db"
            ;;
        *)
            echo "|||"
            ;;
    esac
}

check_docker_installed() {
    if ! command -v docker &> /dev/null; then
        print_message "ERROR" "Docker is not installed on this server. It is required for recovery."
        read -rp "${GREEN}[?]${RESET} Want to install Docker now? (${GREEN}y${RESET}/${RED}n${RESET}):" install_choice
        
        if [[ "$install_choice" =~ ^[Yy]$ ]]; then
            print_message "INFO" "Installing Docker in silent mode..."
            if curl -fsSL https://get.docker.com | sh > /dev/null 2>&1; then
                print_message "SUCCESS" "Docker installed successfully."
            else
                print_message "ERROR" "An error occurred while installing Docker."
                return 1
            fi
        else
            print_message "INFO" "The operation was canceled by the user."
            return 1
        fi
    fi
    return 0
}

create_bot_backup() {
    if [[ "$BOT_BACKUP_ENABLED" != "true" ]]; then
        return 0
    fi
    
    print_message "INFO" "Creating a Telegram bot backup: ${BOLD}${BOT_BACKUP_SELECTED}${RESET}..."
    
    local bot_params=$(get_bot_params "$BOT_BACKUP_SELECTED")
    IFS='|' read -r BOT_CONTAINER_NAME BOT_VOLUME_NAME BOT_DIR_NAME BOT_SERVICE_NAME <<< "$bot_params"
    
    if [[ -z "$BOT_CONTAINER_NAME" ]]; then
        print_message "ERROR" "Unknown bot: $BOT_BACKUP_SELECTED"
        print_message "INFO" "Continuing backup creation without Telegram Shop..."
        return 0
    fi

    local BOT_BACKUP_FILE_DB="bot_dump_${TIMESTAMP}.sql.gz"
    local BOT_DIR_ARCHIVE="bot_dir_${TIMESTAMP}.tar.gz"
    
    if ! docker inspect "$BOT_CONTAINER_NAME" > /dev/null 2>&1 || ! docker container inspect -f '{{.State.Running}}' "$BOT_CONTAINER_NAME" 2>/dev/null | grep -q "true"; then
        print_message "WARN" "Bot container '$BOT_CONTAINER_NAME' not found or not running. Skipping bot backup."
        return 0
    fi
    
    print_message "INFO" "Creating a PostgreSQL bot dump..."
    if ! docker exec -t "$BOT_CONTAINER_NAME" pg_dumpall -c -U "$BOT_BACKUP_DB_USER" | gzip -9 > "$BACKUP_DIR/$BOT_BACKUP_FILE_DB"; then
        print_message "ERROR" "Failed to create Telegram Shop PostgreSQL dump. Continuing without Telegram Shop backup..."
        return 0
    fi
    
    if [ -d "$BOT_BACKUP_PATH" ]; then
        print_message "INFO" "Archiving the bot directory ${BOLD}${BOT_BACKUP_PATH}${RESET}..."
        local exclude_args=""
        for pattern in $BACKUP_EXCLUDE_PATTERNS; do
            exclude_args+="--exclude=$pattern "
        done
        
        if eval "tar -czf '$BACKUP_DIR/$BOT_DIR_ARCHIVE' $exclude_args -C '$(dirname "$BOT_BACKUP_PATH")' '$(basename "$BOT_BACKUP_PATH")'"; then
            print_message "SUCCESS" "The bot directory has been successfully archived."
        else
            print_message "ERROR" "Error when archiving the bot directory."
            return 1
        fi
    else
        print_message "WARN" "Bot directory ${BOLD}${BOT_BACKUP_PATH}${RESET} not found! We continue without the bot directory archive..."
        return 0
    fi
    
    BACKUP_ITEMS+=("$BOT_BACKUP_FILE_DB" "$BOT_DIR_ARCHIVE")
    
    print_message "SUCCESS" "The bot backup has been successfully created."
    echo ""
    return 0
}

restore_bot_backup() {
    local temp_restore_dir="$1"
    
    local BOT_DUMP_FILE=$(find "$temp_restore_dir" -name "bot_dump_*.sql.gz" | head -n 1)
    local BOT_DIR_ARCHIVE=$(find "$temp_restore_dir" -name "bot_dir_*.tar.gz" | head -n 1)
    
    if [[ -z "$BOT_DUMP_FILE" && -z "$BOT_DIR_ARCHIVE" ]]; then
        return 2
    fi

    check_docker_installed || return 1

    clear
    print_message "INFO" "Telegram Shop backup data detected in the archive."
    echo ""
    read -rp "$(echo -e "${GREEN}[?]${RESET} Restore Telegram bot? ${GREEN}${BOLD}Y${RESET}/${RED}${BOLD}N${RESET}:")" restore_bot_confirm
    
    if [[ "$restore_bot_confirm" != "y" ]]; then
        print_message "INFO" "Bot restoration cancelled."
        return 1
    fi
    
    echo ""
    print_message "ACTION" "Which Telegram Shop variant is included in this backup?"
    echo "1. Bot from Jesus (remnawave-telegram-shop)"
    echo "2. Bot from Machka (remnawave-tg-shop)"
    echo "3. Bot from Snoups (remnashop)"
    echo ""
    
    local bot_choice
    local selected_bot_name
    while true; do
        read -rp "${GREEN}[?]${RESET} Select a bot:" bot_choice
        case "$bot_choice" in
            1) selected_bot_name="Bot from Jesus"; break ;;
            2) selected_bot_name="Bot from Machka"; break ;;
            3) selected_bot_name="Bot from Snoups"; break ;;
            *) print_message "ERROR" "Invalid input." ;;
        esac
    done
    
    echo ""
    print_message "ACTION" "Select the path to restore the bot:"
    if [[ "$selected_bot_name" == "Bot from Jesus" ]]; then
        echo " 1. /opt/remnawave-telegram-shop"
        echo " 2. /root/remnawave-telegram-shop"
        echo " 3. /opt/stacks/remnawave-telegram-shop"
    elif [[ "$selected_bot_name" == "Bot from Machka" ]]; then
        echo " 1. /opt/remnawave-tg-shop"
        echo " 2. /root/remnawave-tg-shop"
        echo " 3. /opt/stacks/remnawave-tg-shop"
    else
        echo " 1. /opt/remnashop"
        echo " 2. /root/remnashop"
        echo " 3. /opt/stacks/remnashop"
    fi
    echo "4. Show your path"
    echo ""
    echo "0. Back"
    echo ""

    local restore_path
    local path_choice
    while true; do
        read -rp "${GREEN}[?]${RESET} Select path:" path_choice
        case "$path_choice" in
        1)
            if [[ "$selected_bot_name" == "Bot from Jesus" ]]; then
                restore_path="/opt/remnawave-telegram-shop"
            elif [[ "$selected_bot_name" == "Bot from Machka" ]]; then
                restore_path="/opt/remnawave-tg-shop"
            else
                restore_path="/opt/remnashop"
            fi
            break
            ;;
        2)
            if [[ "$selected_bot_name" == "Bot from Jesus" ]]; then
                restore_path="/root/remnawave-telegram-shop"
            elif [[ "$selected_bot_name" == "Bot from Machka" ]]; then
                restore_path="/root/remnawave-tg-shop"
            else
                restore_path="/root/remnashop"
            fi
            break
            ;;
        3)
            if [[ "$selected_bot_name" == "Bot from Jesus" ]]; then
                restore_path="/opt/stacks/remnawave-telegram-shop"
            elif [[ "$selected_bot_name" == "Bot from Machka" ]]; then
                restore_path="/opt/stacks/remnawave-tg-shop"
            else
                restore_path="/opt/stacks/remnashop"
            fi
            break
            ;;
        4)
            echo ""
            print_message "INFO" "Enter the full path to restore the bot:"
            read -rp "Path:" custom_restore_path
        
            if [[ -z "$custom_restore_path" ]]; then
                print_message "ERROR" "The path cannot be empty."
                echo ""
                read -rp "Press Enter to continue..."
                continue
            fi
        
            if [[ ! "$custom_restore_path" = /* ]]; then
                print_message "ERROR" "The path must be absolute (starting with /)."
                echo ""
                read -rp "Press Enter to continue..."
                continue
            fi
        
            custom_restore_path="${custom_restore_path%/}"
            restore_path="$custom_restore_path"
            print_message "SUCCESS" "Custom recovery path set: ${BOLD}${restore_path}${RESET}"
            break
            ;;
        0)
            print_message "INFO" "Bot restoration cancelled."
            return 0
            ;;
        *)
            print_message "ERROR" "Invalid input."
            ;;
        esac
    done

    local bot_params=$(get_bot_params "$selected_bot_name")
    IFS='|' read -r BOT_CONTAINER_NAME BOT_VOLUME_NAME BOT_DIR_NAME BOT_SERVICE_NAME <<< "$bot_params"
    
    echo ""
    read -rp "$(echo -e "${GREEN}[?]${RESET} Enter the bot database username (postgres by default):")" restore_bot_db_user
    restore_bot_db_user="${restore_bot_db_user:-postgres}"
    echo ""
    read -rp "$(echo -e "${GREEN}[?]${RESET} Enter the bot database name (postgres by default):")" restore_bot_db_name
    restore_bot_db_name="${restore_bot_db_name:-postgres}"
    echo ""
    print_message "INFO" "Start of Telegram bot recovery..."
    
    if [[ -d "$restore_path" ]]; then
        print_message "INFO" "The directory ${BOLD}${restore_path}${RESET} exists. We stop the containers and clean..."
    
        if cd "$restore_path" 2>/dev/null && ([[ -f "docker-compose.yml" ]] || [[ -f "docker-compose.yaml" ]]); then
            print_message "INFO" "Stopping existing bot containers..."
            docker compose down 2>/dev/null || print_message "WARN" "The containers could not be stopped (they may have already been stopped)."
        else
            print_message "INFO" "Docker Compose file (.yml or .yaml) not found, skip stopping containers."
        fi
    fi
        
    cd /
        
    print_message "INFO" "Deleting old directory..."
    if [[ -d "$restore_path" ]]; then
        if ! rm -rf "$restore_path"; then
            print_message "ERROR" "Failed to delete directory ${BOLD}${restore_path}${RESET}."
            return 1
        fi
        print_message "SUCCESS" "The old directory has been deleted."
    else
        print_message "INFO" "The directory ${BOLD}${restore_path}${RESET} does not exist. This is a clean install."
    fi
    
    print_message "INFO" "Creating a new directory..."
    if ! mkdir -p "$restore_path"; then
        print_message "ERROR" "Failed to create directory ${BOLD}${restore_path}${RESET}."
        return 1
    fi
    print_message "SUCCESS" "A new directory has been created."
    echo ""
    
    if [[ -n "$BOT_DIR_ARCHIVE" ]]; then
        print_message "INFO" "Restoring the bot directory from the archive..."
        local temp_extract_dir="$BACKUP_DIR/bot_extract_temp_$$"
        mkdir -p "$temp_extract_dir"
        
        if tar -xzf "$BOT_DIR_ARCHIVE" -C "$temp_extract_dir"; then
            local extracted_dir=$(find "$temp_extract_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1)

            if [[ -n "$extracted_dir" && -d "$extracted_dir" ]]; then
                if cp -rf "$extracted_dir"/. "$restore_path/" 2>/dev/null; then
                    print_message "SUCCESS" "The bot directory files have been restored (folder: $(basename"$extracted_dir"))."
                else
                    print_message "ERROR" "Error when copying bot files."
                    rm -rf "$temp_extract_dir"
                    return 1
                fi
            else
                print_message "ERROR" "Could not find the directory with the bot files in the archive."
                rm -rf "$temp_extract_dir"
                return 1
            fi
        else
            print_message "ERROR" "Error when unpacking the bot directory archive."
            rm -rf "$temp_extract_dir"
            return 1
        fi
        rm -rf "$temp_extract_dir"
    else
        print_message "WARN" "The bot directory archive was not found in the backup."
        return 1
    fi
    
    print_message "INFO" "Checking and deleting old database volumes..."
    if docker volume ls -q | grep -Fxq "$BOT_VOLUME_NAME"; then
        local containers_using_volume
        containers_using_volume=$(docker ps -aq --filter volume="$BOT_VOLUME_NAME")
    
        if [[ -n "$containers_using_volume" ]]; then
            print_message "INFO" "Found containers using volume $BOT_VOLUME_NAME. Let's delete..."
            docker rm -f $containers_using_volume >/dev/null 2>&1
        fi
    
        if docker volume rm "$BOT_VOLUME_NAME" >/dev/null 2>&1; then
            print_message "SUCCESS" "The old database volume $BOT_VOLUME_NAME has been deleted."
        else
            print_message "WARN" "Failed to delete volume $BOT_VOLUME_NAME."
        fi
    else
        print_message "INFO" "No old database volumes were found."
    fi
    echo ""
    
    if ! cd "$restore_path"; then
        print_message "ERROR" "Failed to navigate to restored directory ${BOLD}${restore_path}${RESET}."
        return 1
    fi
    
    if [[ ! -f "docker-compose.yml" && ! -f "docker-compose.yaml" ]]; then
    print_message "ERROR" "The file docker-compose.yml or docker-compose.yaml was not found in the restored directory."
    return 1
    fi
    
    print_message "INFO" "Launching the bot database container..."
    if ! docker compose up -d "$BOT_SERVICE_NAME"; then
        print_message "ERROR" "The bot database container failed to start."
        return 1
    fi
    
    echo ""
    print_message "INFO" "Waiting for the bot database to be ready..."
    local wait_count=0
    local max_wait=60
    
    until [ "$(docker inspect --format='{{.State.Health.Status}}' "$BOT_CONTAINER_NAME" 2>/dev/null)" == "healthy" ]; do
        sleep 2
        echo -n "."
        wait_count=$((wait_count + 1))
        if [ $wait_count -gt $max_wait ]; then
            echo ""
            print_message "ERROR" "The wait time for the bot database to be ready has been exceeded."
            return 1
        fi
    done
    echo ""
    print_message "SUCCESS" "The bot's database is ready for use."
    
    if [[ -n "$BOT_DUMP_FILE" ]]; then
        print_message "INFO" "Restoring a bot's database from a dump..."
        local BOT_DUMP_UNCOMPRESSED="${BOT_DUMP_FILE%.gz}"
        
        if ! gunzip "$BOT_DUMP_FILE"; then
            print_message "ERROR" "Failed to unpack the bot database dump."
            return 1
        fi
        
        mkdir -p "$temp_restore_dir"

        if ! docker exec -i "$BOT_CONTAINER_NAME" psql -q -U "$restore_bot_db_user" -d "$restore_bot_db_name" > /dev/null 2> "$temp_restore_dir/restore_errors.log" < "$BOT_DUMP_UNCOMPRESSED"; then
            print_message "ERROR" "Error when restoring the bot database."
            echo ""
            if [[ -f "$temp_restore_dir/restore_errors.log" ]]; then
                print_message "WARN" "${YELLOW}Restore error log:${RESET}"
                cat "$temp_restore_dir/restore_errors.log"
            fi
            [[ -d "$temp_restore_dir" ]] && rm -rf "$temp_restore_dir"
            echo ""
            read -rp "Press Enter to return to the menu..."
            return 1
        fi

        print_message "SUCCESS" "The bot database has been successfully restored."
    else
        print_message "WARN" "The bot database dump was not found in the archive."
    fi
    
    echo ""
    print_message "INFO" "Launching the remaining bot containers..."
    if ! docker compose up -d; then
        print_message "ERROR" "Failed to start all bot containers."
        return 1
    fi
    
    sleep 3
    return 0
}

save_config() {
    print_message "INFO" "Saving configuration to ${BOLD}${CONFIG_FILE}${RESET}..."
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
SKIP_PANEL_BACKUP="$SKIP_PANEL_BACKUP"
EOF
    chmod 600 "$CONFIG_FILE" || { print_message "ERROR" "Failed to set permissions (600) for ${BOLD}${CONFIG_FILE}${RESET}. Check permissions."; exit 1; }
    print_message "SUCCESS" "The configuration has been saved."
}

load_or_create_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        print_message "INFO" "Loading configuration..."
        source "$CONFIG_FILE"
        echo ""

        UPLOAD_METHOD=${UPLOAD_METHOD:-telegram}
        DB_USER=${DB_USER:-postgres}
        CRON_TIMES=${CRON_TIMES:-}
        REMNALABS_ROOT_DIR=${REMNALABS_ROOT_DIR:-}
        TG_MESSAGE_THREAD_ID=${TG_MESSAGE_THREAD_ID:-}
        SKIP_PANEL_BACKUP=${SKIP_PANEL_BACKUP:-false}
        
        local config_updated=false

        if [[ -z "$BOT_TOKEN" || -z "$CHAT_ID" ]]; then
            print_message "WARN" "The configuration file is missing necessary variables for Telegram."
            print_message "ACTION" "Please enter the missing data for Telegram (required):"
            echo ""
            print_message "INFO" "Create a Telegram bot in ${CYAN}@BotFather${RESET} and get an API Token"
            [[ -z "$BOT_TOKEN" ]] && read -rp "Enter API Token:" BOT_TOKEN
            echo ""
            print_message "INFO" "Enter Chat ID (to send to the group) or your Telegram ID (to send directly to the bot)"
            echo -e "Chat ID/Telegram ID can be found from this bot ${CYAN}@username_to_id_bot${RESET}"
            [[ -z "$CHAT_ID" ]] && read -rp "Enter ID:" CHAT_ID
            echo ""
            print_message "INFO" "Optional: to send to a specific group topic, enter the topic ID (Message Thread ID)"
            echo -e "Leave blank for general thread or sending directly to bot"
            read -rp "Enter Message Thread ID:" TG_MESSAGE_THREAD_ID
            echo ""
            config_updated=true
        fi

        if [[ "$SKIP_PANEL_BACKUP" != "true" && -z "$DB_USER" ]]; then
            print_message "INFO" "Enter the panel database username (postgres by default):"
            read -rp "Input:" input_db_user
            DB_USER=${input_db_user:-postgres}
            config_updated=true
            echo ""
        fi
        
        if [[ "$SKIP_PANEL_BACKUP" != "true" && -z "$REMNALABS_ROOT_DIR" ]]; then
            print_message "ACTION" "Where is/is your Remnawave panel installed?"
            echo " 1. /opt/remnawave"
            echo " 2. /root/remnawave"
            echo " 3. /opt/stacks/remnawave"
            echo "4. Show your path"
            echo ""

            local remnawave_path_choice
            while true; do
                read -rp "${GREEN}[?]${RESET} Select an option:" remnawave_path_choice
                case "$remnawave_path_choice" in
                1) REMNALABS_ROOT_DIR="/opt/remnawave"; break ;;
                2) REMNALABS_ROOT_DIR="/root/remnawave"; break ;;
                3) REMNALABS_ROOT_DIR="/opt/stacks/remnawave"; break ;;
                4) 
                    echo ""
                    print_message "INFO" "Enter the full path to the Remnawave panel directory:"
                    read -rp "Path:" custom_remnawave_path
    
                    if [[ -z "$custom_remnawave_path" ]]; then
                        print_message "ERROR" "The path cannot be empty."
                        echo ""
                        read -rp "Press Enter to continue..."
                        continue
                    fi
    
                    if [[ ! "$custom_remnawave_path" = /* ]]; then
                        print_message "ERROR" "The path must be absolute (starting with /)."
                        echo ""
                        read -rp "Press Enter to continue..."
                        continue
                    fi
    
                    custom_remnawave_path="${custom_remnawave_path%/}"
    
                    if [[ ! -d "$custom_remnawave_path" ]]; then
                        print_message "WARN" "The directory ${BOLD}${custom_remnawave_path}${RESET} does not exist."
                        read -rp "$(echo -e "${GREEN}[?]${RESET} Continue with this path? ${GREEN}${BOLD}Y${RESET}/${RED}${BOLD}N${RESET}:")" confirm_custom_path
                        if [[ "$confirm_custom_path" != "y" ]]; then
                            echo ""
                            read -rp "Press Enter to continue..."
                            continue
                        fi
                    fi
    
                    REMNALABS_ROOT_DIR="$custom_remnawave_path"
                    print_message "SUCCESS" "Custom path set: ${BOLD}${REMNALABS_ROOT_DIR}${RESET}"
                    break 
                    ;;
                *) print_message "ERROR" "Invalid input." ;;
                esac
            done
            config_updated=true
            echo ""
        fi

        if [[ "$UPLOAD_METHOD" == "google_drive" ]]; then
            if [[ -z "$GD_CLIENT_ID" || -z "$GD_CLIENT_SECRET" || -z "$GD_REFRESH_TOKEN" ]]; then
                print_message "WARN" "Incomplete data for Google Drive was found in the configuration file."
                print_message "WARN" "The sending method will be changed to ${BOLD}Telegram${RESET}."
                UPLOAD_METHOD="telegram"
                config_updated=true
            fi
        fi

        if [[ "$UPLOAD_METHOD" == "google_drive" && ( -z "$GD_CLIENT_ID" || -z "$GD_CLIENT_SECRET" || -z "$GD_REFRESH_TOKEN" ) ]]; then
            print_message "WARN" "The configuration file is missing required variables for Google Drive."
            print_message "ACTION" "Please enter the missing data for Google Drive:"
            echo ""
            echo "If you do not have Client ID and Client Secret tokens"
            local guide_url="https://telegra.ph/Nastrojka-Google-API-06-02"
            print_message "LINK" "Check out this guide: ${CYAN}${guide_url}${RESET}"
            echo ""
            [[ -z "$GD_CLIENT_ID" ]] && read -rp "Enter Google Client ID:" GD_CLIENT_ID
            [[ -z "$GD_CLIENT_SECRET" ]] && read -rp "Enter Google Client Secret:" GD_CLIENT_SECRET
            clear
            
            if [[ -z "$GD_REFRESH_TOKEN" ]]; then
                print_message "WARN" "To receive a Refresh Token, you must log in to your browser."
                print_message "INFO" "Open the following link in your browser, log in and copy the code:"
                echo ""
                local auth_url="https://accounts.google.com/o/oauth2/auth?client_id=${GD_CLIENT_ID}&redirect_uri=urn:ietf:wg:oauth:2.0:oob&scope=https://www.googleapis.com/auth/drive&response_type=code&access_type=offline"
                print_message "INFO" "${CYAN}${auth_url}${RESET}"
                echo ""
                read -rp "Enter the code from the browser:" AUTH_CODE
                
                print_message "INFO" "Receiving Refresh Token..."
                local token_response=$(curl -s -X POST https://oauth2.googleapis.com/token \
                    -d client_id="$GD_CLIENT_ID" \
                    -d client_secret="$GD_CLIENT_SECRET" \
                    -d code="$AUTH_CODE" \
                    -d redirect_uri="urn:ietf:wg:oauth:2.0:oob" \
                    -d grant_type="authorization_code")
                
                GD_REFRESH_TOKEN=$(echo "$token_response" | jq -r .refresh_token 2>/dev/null)
                
                if [[ -z "$GD_REFRESH_TOKEN" || "$GD_REFRESH_TOKEN" == "null" ]]; then
                    print_message "ERROR" "Failed to obtain Refresh Token. Check Client ID, Client Secret, and the entered authorization code."
                    print_message "WARN" "Since the Google Drive setup is not completed, the sending method will be changed to ${BOLD}Telegram${RESET}."
                    UPLOAD_METHOD="telegram"
                    config_updated=true
                fi
            fi
            echo ""
            echo "📁 To specify the Google Drive folder:"
            echo "1. Create and open the desired folder in the browser."
            echo "2. Look at the link in the address bar, it looks like this:"
            echo "      https://drive.google.com/drive/folders/1a2B3cD4eFmNOPqRstuVwxYz"
            echo "3. Copy the part after /folders/ - this is the Folder ID:"
            echo "4. If you leave the field empty, the backup will be sent to the root folder of Google Drive."
            echo ""
            read -rp "Enter Google Drive Folder ID (leave blank for root folder):" GD_FOLDER_ID
            config_updated=true
        fi

        if $config_updated; then
            save_config
        else
            print_message "SUCCESS" "The configuration was successfully loaded from ${BOLD}${CONFIG_FILE}${RESET}."
        fi

    else
        if [[ "$SCRIPT_RUN_PATH" != "$SCRIPT_PATH" ]]; then
            print_message "INFO" "Configuration not found. The script was launched from a temporary location."
            print_message "INFO" "Move the script to the main installation directory: ${BOLD}${SCRIPT_PATH}${RESET}..."
            mkdir -p "$INSTALL_DIR" || { print_message "ERROR" "Failed to create installation directory ${BOLD}${INSTALL_DIR}${RESET}."; exit 1; }
            mkdir -p "$BACKUP_DIR" || { print_message "ERROR" "Failed to create backup directory ${BOLD}${BACKUP_DIR}${RESET}."; exit 1; }

            if mv "$SCRIPT_RUN_PATH" "$SCRIPT_PATH"; then
                chmod +x "$SCRIPT_PATH"
                clear
                print_message "SUCCESS" "The script was successfully moved to ${BOLD}${SCRIPT_PATH}${RESET}."
                print_message "ACTION" "Restart the script from the new location to complete the setup."
                exec "$SCRIPT_PATH" "$@"
                exit 0
            else
                print_message "ERROR" "Failed to move script to ${BOLD}${SCRIPT_PATH}${RESET}."
                exit 1
            fi
        else
            print_message "INFO" "Configuration not found, create a new one..."
            echo ""

            print_message "ACTION" "Select the script mode:"
            echo "1. Full (Remnawave Panel + Bot optional)"
            echo "2. Bot only (if the panel is installed on another server)"
            echo ""
            read -rp "${GREEN}[?]${RESET} Your choice:" main_mode_choice
            
            if [[ "$main_mode_choice" == "2" ]]; then
                SKIP_PANEL_BACKUP="true"
                REMNALABS_ROOT_DIR="none"
            else
                SKIP_PANEL_BACKUP="false"
            fi
            echo ""

            print_message "INFO" "Setting up Telegram notifications:"
            print_message "INFO" "Create a Telegram bot in ${CYAN}@BotFather${RESET} and get an API Token"
            read -rp "Enter API Token:" BOT_TOKEN
            echo ""
            print_message "INFO" "Enter Chat ID (to send to the group) or your Telegram ID (to send directly to the bot)"
            echo -e "Chat ID/Telegram ID can be found from this bot ${CYAN}@username_to_id_bot${RESET}"
            read -rp "Enter ID:" CHAT_ID
            echo ""
            print_message "INFO" "Optional: to send to a specific group topic, enter the topic ID (Message Thread ID)"
            echo -e "Leave blank for general thread or sending directly to bot"
            read -rp "Enter Message Thread ID:" TG_MESSAGE_THREAD_ID
            echo ""

            if [[ "$SKIP_PANEL_BACKUP" == "false" ]]; then
                print_message "INFO" "Enter your database username (postgres by default):"
                read -rp "Input:" input_db_user
                DB_USER=${input_db_user:-postgres}
                echo ""

                print_message "ACTION" "Where is/is your Remnawave panel installed?"
                echo " 1. /opt/remnawave"
                echo " 2. /root/remnawave"
                echo " 3. /opt/stacks/remnawave"
                echo "4. Show your path"
                echo ""

                local remnawave_path_choice
                while true; do
                    read -rp "${GREEN}[?]${RESET} Select an option:" remnawave_path_choice
                    case "$remnawave_path_choice" in
                    1) REMNALABS_ROOT_DIR="/opt/remnawave"; break ;;
                    2) REMNALABS_ROOT_DIR="/root/remnawave"; break ;;
                    3) REMNALABS_ROOT_DIR="/opt/stacks/remnawave"; break ;;
                    4) 
                        echo ""
                        print_message "INFO" "Enter the full path to the Remnawave panel directory:"
                        read -rp "Path:" custom_remnawave_path
                        if [[ -n "$custom_remnawave_path" ]]; then
                            REMNALABS_ROOT_DIR="${custom_remnawave_path%/}"
                            break
                        fi
                        ;;
                    *) print_message "ERROR" "Invalid input." ;;
                    esac
                done
            fi

            mkdir -p "$INSTALL_DIR"
            mkdir -p "$BACKUP_DIR"
            save_config
            print_message "SUCCESS" "The new configuration is saved in ${BOLD}${CONFIG_FILE}${RESET}"
        fi
    fi

    if [[ "$SKIP_PANEL_BACKUP" != "true" && ! -d "$REMNALABS_ROOT_DIR" ]]; then
        print_message "ERROR" "The Remnawave directory was not found at $REMNALABS_ROOT_DIR. Check the settings in $CONFIG_FILE"
        exit 1
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
        echo "not defined"
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
        print_message "ERROR" "Telegram BOT_TOKEN or CHAT_ID is not configured. Message not sent."
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
        echo -e "${RED}❌ Error sending message to Telegram. Code: ${BOLD}$http_code${RESET}"
        echo -e "Reply from Telegram: ${body}"
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
        print_message "ERROR" "Telegram BOT_TOKEN or CHAT_ID is not configured. The document has not been sent."
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
        echo -e "${RED}❌ ${BOLD}CURL${RESET} error when sending a document to Telegram. Exit code: ${BOLD}$curl_status${RESET}. Check your network connection.${RESET}"
        return 1
    fi

    local http_code="${api_response: -3}"

    if [[ "$http_code" == "200" ]]; then
        return 0
    else
        echo -e "${RED}❌ Telegram API returned HTTP error. Code: ${BOLD}$http_code${RESET}. Response: ${BOLD}$api_response${RESET}. The file may be too large or ${BOLD}BOT_TOKEN${RESET}/${BOLD}CHAT_ID${RESET} are incorrect.${RESET}"
        return 1
    fi
}

get_google_access_token() {
    if [[ -z "$GD_CLIENT_ID" || -z "$GD_CLIENT_SECRET" || -z "$GD_REFRESH_TOKEN" ]]; then
        print_message "ERROR" "Google Drive Client ID, Client Secret, or Refresh Token are not configured."
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
        print_message "ERROR" "Failed to obtain Access Token for Google Drive. The Refresh Token may be outdated or invalid. Error: ${error_msg:-Unknown error}."
        print_message "ACTION" "Please reconfigure Google Drive in the 'Set up sending method' menu."
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
        print_message "ERROR" "Failed to send backup to Google Drive: Access Token not received."
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
        print_message "ERROR" "Error uploading to Google Drive. Code: ${error_code:-Unknown}. Message: ${error_message:-Unknown error}. Full API response: ${response}"
        return 1
    fi
}

create_backup() {
    print_message "INFO" "Starting backup creation..."
    echo ""
    
    REMNAWAVE_VERSION=$(get_remnawave_version)
    TIMESTAMP=$(date +%Y-%m-%d"_"%H_%M_%S)
    BACKUP_FILE_DB="dump_${TIMESTAMP}.sql.gz"
    BACKUP_FILE_FINAL="remnawave_backup_${TIMESTAMP}.tar.gz"
    
    mkdir -p "$BACKUP_DIR" || { 
        echo -e "${RED}❌ Error: Failed to create backup directory. Check permissions.${RESET}"
        send_telegram_message "❌ Error: Failed to create backup directory ${BOLD}$BACKUP_DIR${RESET}." "None"
        exit 1
    }
    
    BACKUP_ITEMS=()
    
    if [[ "$SKIP_PANEL_BACKUP" == "true" ]]; then
        print_message "INFO" "Skipping Remnawave panel backup."
    else
        if ! docker inspect remnawave-db > /dev/null 2>&1 || ! docker container inspect -f '{{.State.Running}}' remnawave-db 2>/dev/null | grep -q "true"; then
            echo -e "${RED}❌ Error: Container ${BOLD}'remnawave-db'${RESET} not found or not running. Cannot create a database backup.${RESET}"
            local error_msg="❌ Error: Container ${BOLD}'remnawave-db'${RESET} not found or not running. Failed to create backup."
            if [[ "$UPLOAD_METHOD" == "telegram" ]]; then
                send_telegram_message "$error_msg" "None"
            elif [[ "$UPLOAD_METHOD" == "google_drive" ]]; then
                print_message "ERROR" "Uploading to Google Drive is not possible due to an error with the DB container."
            fi
            exit 1
        fi
        
        print_message "INFO" "Creating a PostgreSQL dump and compressing it into a file..."
        if ! docker exec -t "remnawave-db" pg_dumpall -c -U "$DB_USER" | gzip -9 > "$BACKUP_DIR/$BACKUP_FILE_DB"; then
            STATUS=$?
            echo -e "${RED}❌ Error creating PostgreSQL dump. Exit code: ${BOLD}$STATUS${RESET}. Check your database username and container access.${RESET}"
            local error_msg="❌ Error creating PostgreSQL dump. Exit code: ${BOLD}${STATUS}${RESET}"
            if [[ "$UPLOAD_METHOD" == "telegram" ]]; then
                send_telegram_message "$error_msg" "None"
            elif [[ "$UPLOAD_METHOD" == "google_drive" ]]; then
                print_message "ERROR" "Uploading to Google Drive is not possible due to an error with the DB dump."
            fi
            exit $STATUS
        fi
        
        print_message "SUCCESS" "The PostgreSQL dump has been created successfully."
        echo ""
        
        print_message "INFO" "Archiving the Remnawave directory..."
        REMNAWAVE_DIR_ARCHIVE="remnawave_dir_${TIMESTAMP}.tar.gz"
        
        if [ -d "$REMNALABS_ROOT_DIR" ]; then
            print_message "INFO" "Archiving the directory ${BOLD}${REMNALABS_ROOT_DIR}${RESET}..."
            
            local exclude_args=""
            for pattern in $BACKUP_EXCLUDE_PATTERNS; do
                exclude_args+="--exclude=$pattern "
            done
            
            if eval "tar -czf '$BACKUP_DIR/$REMNAWAVE_DIR_ARCHIVE' $exclude_args -C '$(dirname "$REMNALABS_ROOT_DIR")' '$(basename "$REMNALABS_ROOT_DIR")'"; then
                print_message "SUCCESS" "The Remnawave directory has been successfully archived."
                BACKUP_ITEMS=("$BACKUP_FILE_DB" "$REMNAWAVE_DIR_ARCHIVE")
            else
                STATUS=$?
                echo -e "${RED}❌ Error when archiving the Remnawave directory. Exit code: ${BOLD}$STATUS${RESET}.${RESET}"
                local error_msg="❌ Error when archiving the Remnawave directory. Exit code: ${BOLD}${STATUS}${RESET}"
                if [[ "$UPLOAD_METHOD" == "telegram" ]]; then
                    send_telegram_message "$error_msg" "None"
                fi
                exit $STATUS
            fi
        else
            print_message "ERROR" "Directory ${BOLD}${REMNALABS_ROOT_DIR}${RESET} not found!"
            exit 1
        fi
    fi
    
    echo ""
    
    create_bot_backup
    
    if [[ ${#BACKUP_ITEMS[@]} -eq 0 ]]; then
        print_message "ERROR" "No data for backup! Enable backup of the panel or bot."
        exit 1
    fi
    
    if ! tar -czf "$BACKUP_DIR/$BACKUP_FILE_FINAL" -C "$BACKUP_DIR" "${BACKUP_ITEMS[@]}"; then
        STATUS=$?
        echo -e "${RED}❌ Error when creating the final backup archive. Exit code: ${BOLD}$STATUS${RESET}.${RESET}"
        local error_msg="❌ Error when creating the final backup archive. Exit code: ${BOLD}${STATUS}${RESET}"
        if [[ "$UPLOAD_METHOD" == "telegram" ]]; then
            send_telegram_message "$error_msg" "None"
        fi
        exit $STATUS
    fi
    
    print_message "SUCCESS" "The final backup archive was successfully created: ${BOLD}${BACKUP_DIR}/${BACKUP_FILE_FINAL}${RESET}"
    echo ""
    
    print_message "INFO" "Cleaning intermediate backup files..."
    for item in "${BACKUP_ITEMS[@]}"; do
        rm -f "$BACKUP_DIR/$item"
    done
    print_message "SUCCESS" "Intermediate files have been deleted."
    echo ""
    
    print_message "INFO" "Sending backup (${UPLOAD_METHOD})..."
    
    local DATE=$(date +'%Y-%m-%d %H:%M:%S')
    local backup_size=$(du -h "$BACKUP_DIR/$BACKUP_FILE_FINAL" | awk '{print $1}')
    
    local backup_info=""
    if [[ "$SKIP_PANEL_BACKUP" == "true" ]]; then
        backup_info=$'\n🤖 *Telegram bot only*'
    elif [[ "$BOT_BACKUP_ENABLED" == "true" ]]; then
        backup_info=$'\n🌊 *Remnawave:* '"${REMNAWAVE_VERSION}"$'\n🤖 *+ Telegram bot*'
    else
        backup_info=$'\n🌊 *Remnawave:* '"${REMNAWAVE_VERSION}"$'\n🖥️ *Panel only*'
    fi

    local caption_text=$'💾 #backup_success\n➖➖➖➖➖➖➖➖➖\n✅ *Backup successfully created*'"${backup_info}"$'\n📁 *DB + directory*\n📏 *Size:*'"${backup_size}"$'\n📅 *Date:*'"${DATE}"
    local backup_size=$(du -h "$BACKUP_DIR/$BACKUP_FILE_FINAL" | awk '{print $1}')

    if [[ -f "$BACKUP_DIR/$BACKUP_FILE_FINAL" ]]; then
        if [[ "$UPLOAD_METHOD" == "telegram" ]]; then
            if send_telegram_document "$BACKUP_DIR/$BACKUP_FILE_FINAL" "$caption_text"; then
                print_message "SUCCESS" "The backup was successfully sent to Telegram."
            else
                echo -e "${RED}❌ Error sending backup to Telegram. Check your Telegram API settings (token, chat ID).${RESET}"
            fi
        elif [[ "$UPLOAD_METHOD" == "google_drive" ]]; then
            if send_google_drive_document "$BACKUP_DIR/$BACKUP_FILE_FINAL"; then
                print_message "SUCCESS" "The backup was successfully sent to Google Drive."
                local tg_success_message="${caption_text//Backup successfully created/Backup successfully created and sent to Google Drive}"
                
                if send_telegram_message "$tg_success_message"; then
                    print_message "SUCCESS" "A notification of successful sending to Google Drive has been sent to Telegram."
                else
                    print_message "ERROR" "Failed to send notification to Telegram after uploading to Google Drive."
                fi
            else
                echo -e "${RED}❌ Error sending backup to Google Drive. Check your Google Drive API settings.${RESET}"
                send_telegram_message "❌ Error: Failed to send backup to Google Drive. Details in the server logs." "None"
            fi
        else
            print_message "WARN" "Unknown upload method: ${BOLD}${UPLOAD_METHOD}${RESET}. Backup not sent."
            send_telegram_message "❌ Error: Unknown backup sending method: ${BOLD}${UPLOAD_METHOD}${RESET}. File: ${BOLD}${BACKUP_FILE_FINAL}${RESET} not sent." "None"
        fi
    else
        echo -e "${RED}❌ Error: The final backup file was not found after creation: ${BOLD}${BACKUP_DIR}/${BACKUP_FILE_FINAL}${RESET}. Unable to send.${RESET}"
        local error_msg="❌ Error: The backup file was not found after creation: ${BOLD}${BACKUP_FILE_FINAL}${RESET}"
        if [[ "$UPLOAD_METHOD" == "telegram" ]]; then
            send_telegram_message "$error_msg" "None"
        elif [[ "$UPLOAD_METHOD" == "google_drive" ]]; then
            print_message "ERROR" "Sending to Google Drive is impossible: the backup file was not found."
        fi
        exit 1
    fi
    
    echo ""
    
    print_message "INFO" "Applying backup retention policy (keeping the last ${BOLD}${RETAIN_BACKUPS_DAYS}${RESET} days)..."
    find "$BACKUP_DIR" -maxdepth 1 -name "remnawave_backup_*.tar.gz" -mtime +$RETAIN_BACKUPS_DAYS -delete
    print_message "SUCCESS" "The retention policy has been applied. Old backups have been deleted."
    
    echo ""
    
    {
        check_update_status >/dev/null 2>&1
        
        if [[ "$UPDATE_AVAILABLE" == true ]]; then
            local CURRENT_VERSION="$VERSION"
            local REMOTE_VERSION_LATEST
            REMOTE_VERSION_LATEST=$(curl -fsSL "$SCRIPT_REPO_URL" 2>/dev/null | grep -m 1 "^VERSION=" | cut -d'"' -f2)
            
            if [[ -n "$REMOTE_VERSION_LATEST" ]]; then
                local update_msg=$'⚠️ *Script update available*\n🔄 *Current version:*'"${CURRENT_VERSION}"$'\n🆕 *Current version:*'"${REMOTE_VERSION_LATEST}"$'\n\n📥 Update via the *“Script update” item* in the main menu'
                send_telegram_message "$update_msg" >/dev/null 2>&1
            fi
        fi
    } &
}

setup_auto_send() {
    echo ""
    if [[ $EUID -ne 0 ]]; then
        print_message "WARN" "Root privileges are required to configure cron. Please run the script with ${BOLD}sudo${RESET}."
        read -rp "Press Enter to continue..."
        return
    fi
    while true; do
        clear
        echo -e "${GREEN}${BOLD}Setting automatic sending${RESET}"
        echo ""
        if [[ -n "$CRON_TIMES" ]]; then
            print_message "INFO" "Automatic sending is set to: ${BOLD}${CRON_TIMES}${RESET} by UTC+0."
        else
            print_message "INFO" "Auto-send ${BOLD}disabled${RESET}."
        fi
        echo ""
        echo "1. Enable or overwrite automatic backup schedule"
        echo "2. Disable automatic backup schedule"
        echo "0. Return to main menu"
        echo ""
        read -rp "${GREEN}[?]${RESET} Select an item:" choice
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

                echo "Select automatic sending option:"
                echo "1) Enter the time (for example: 08:00 12:00 18:00)"
                echo "2) Hourly"
                echo "3) Daily"
                read -rp "Your choice:" send_choice
                echo ""

                cron_times_to_write=()
                user_friendly_times_local=""
                invalid_format=false

                if [[ "$send_choice" == "1" ]]; then
                    echo "Enter the desired sending time in UTC+0 (for example, 08:00 12:00):"
                    read -rp "Time separated by space:" times
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
                                print_message "ERROR" "Invalid time value: ${BOLD}$t${RESET} (hours 0-23, minutes 0-59)."
                                invalid_format=true
                                break
                            fi
                        else
                            print_message "ERROR" "Invalid time format: ${BOLD}$t${RESET} (expected HH:MM)."
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
                    print_message "ERROR" "Wrong choice."
                    continue
                fi

                echo ""

                if [ "$invalid_format" = true ] || [ ${#cron_times_to_write[@]} -eq 0 ]; then
                    print_message "ERROR" "Automatic sending is not configured due to time entry errors. Please try again."
                    continue
                fi

                print_message "INFO" "Setting up a cron task to automatically send..."

                local temp_crontab_file=$(mktemp)

                if ! crontab -l > "$temp_crontab_file" 2>/dev/null; then
                    touch "$temp_crontab_file"
                fi

                if ! grep -q "^SHELL=" "$temp_crontab_file"; then
                    echo "SHELL=/bin/bash" | cat - "$temp_crontab_file" > "$temp_crontab_file.tmp"
                    mv "$temp_crontab_file.tmp" "$temp_crontab_file"
                    print_message "INFO" "SHELL=/bin/bash added to crontab."
                fi

                if ! grep -q "^PATH=" "$temp_crontab_file"; then
                    echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin" | cat - "$temp_crontab_file" > "$temp_crontab_file.tmp"
                    mv "$temp_crontab_file.tmp" "$temp_crontab_file"
                    print_message "INFO" "PATH variable added to crontab."
                else
                    print_message "INFO" "PATH variable already exists in crontab."
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
                    print_message "SUCCESS" "The CRON task for automatic sending has been successfully installed."
                else
                    print_message "ERROR" "Failed to install CRON task. Check access rights and the presence of crontab."
                fi

                rm -f "$temp_crontab_file"

                CRON_TIMES="${user_friendly_times_local% }"
                save_config
                print_message "SUCCESS" "Automatic sending is set to: ${BOLD}${CRON_TIMES}${RESET} by UTC+0."
                ;;
            2)
                print_message "INFO" "Disabling automatic sending..."
                (crontab -l 2>/dev/null | grep -vF "$SCRIPT_PATH backup") | crontab -

                CRON_TIMES=""
                save_config
                print_message "SUCCESS" "Automatic sending has been successfully disabled."
                ;;
            0) break ;;
            *) print_message "ERROR" "Invalid input. Please select one of the suggested items." ;;
        esac
        echo ""
        read -rp "Press Enter to continue..."
    done
    echo ""
}
    
restore_backup() {
    clear
    echo "${GREEN}${BOLD}Restoring from backup${RESET}"
    echo ""

    print_message "INFO" "Place the backup file in the folder: ${BOLD}${BACKUP_DIR}${RESET}"
    echo ""

    if ! compgen -G "$BACKUP_DIR/remnawave_backup_*.tar.gz" > /dev/null; then
        print_message "ERROR" "Error: No backup files found in ${BOLD}${BACKUP_DIR}${RESET}."
        read -rp "Press Enter to return to the menu..."
        return
    fi

    readarray -t SORTED_BACKUP_FILES < <(
        find "$BACKUP_DIR" -maxdepth 1 -name "remnawave_backup_*.tar.gz" -printf "%T@ %p\n" | sort -nr | cut -d' ' -f2-
    )

    echo ""
    echo "Select the file to restore:"
    local i=1
    for file in "${SORTED_BACKUP_FILES[@]}"; do
        echo " $i) ${file##*/}"
        i=$((i+1))
    done
    echo ""
    echo "0) Return to main menu"
    echo ""

    local user_choice selected_index
    while true; do
        read -rp "${GREEN}[?]${RESET} Enter file number (0 to exit):" user_choice
        [[ "$user_choice" == "0" ]] && return
        [[ "$user_choice" =~ ^[0-9]+$ ]] || { print_message "ERROR" "Invalid input."; continue; }
        selected_index=$((user_choice - 1))
        (( selected_index >= 0 && selected_index < ${#SORTED_BACKUP_FILES[@]} )) && break
        print_message "ERROR" "Invalid number."
    done

    SELECTED_BACKUP="${SORTED_BACKUP_FILES[$selected_index]}"

    clear
    print_message "INFO" "Unpacking the backup archive..."
    local temp_restore_dir="$BACKUP_DIR/restore_temp_$$"
    mkdir -p "$temp_restore_dir"

    if ! tar -xzf "$SELECTED_BACKUP" -C "$temp_restore_dir"; then
        print_message "ERROR" "Error unpacking archive."
        rm -rf "$temp_restore_dir"
        read -rp "Press Enter to return to the menu..."
        return
    fi

    print_message "SUCCESS" "The archive has been unpacked."
    echo ""

    local PANEL_DUMP
    PANEL_DUMP=$(find "$temp_restore_dir" -name "dump_*.sql.gz" | head -n 1)
    local PANEL_DIR_ARCHIVE
    PANEL_DIR_ARCHIVE=$(find "$temp_restore_dir" -name "remnawave_dir_*.tar.gz" | head -n 1)

    local PANEL_STATUS=2 
    local BOT_STATUS=2

    if [[ -z "$PANEL_DUMP" || -z "$PANEL_DIR_ARCHIVE" ]]; then
        print_message "WARN" "The panel files were not found in the backup."
        PANEL_STATUS=2
    else
        print_message "WARN" "Panel backup found. The restore will overwrite the current database."
        read -rp "$(echo -e "${GREEN}[?]${RESET} Restore the panel? (${GREEN}Y${RESET} - Yes / ${RED}N${RESET} - skip):")" confirm_panel
        echo ""
        if [[ "$confirm_panel" =~ ^[Yy]$ ]]; then
            check_docker_installed || { rm -rf "$temp_restore_dir"; return 1; }
            print_message "INFO" "Enter the database name (postgres by default):"
            read -rp "Input:" restore_db_name
            restore_db_name="${restore_db_name:-postgres}"

            if [[ -d "$REMNALABS_ROOT_DIR" ]]; then
                cd "$REMNALABS_ROOT_DIR" 2>/dev/null && docker compose down 2>/dev/null
                cd ~
                rm -rf "$REMNALABS_ROOT_DIR"
            fi

            mkdir -p "$REMNALABS_ROOT_DIR"
            local extract_dir="$BACKUP_DIR/extract_temp_$$"
            mkdir -p "$extract_dir"
            tar -xzf "$PANEL_DIR_ARCHIVE" -C "$extract_dir"
            local extracted_dir
            extracted_dir=$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1)
            cp -rf "$extracted_dir"/. "$REMNALABS_ROOT_DIR/"
            rm -rf "$extract_dir"

            docker volume rm remnawave-db-data 2>/dev/null || true
            cd "$REMNALABS_ROOT_DIR" || { print_message "ERROR" "Directory not found"; return; }
            docker compose up -d remnawave-db

            print_message "INFO" "Waiting for the database to be ready..."
            until [[ "$(docker inspect --format='{{.State.Health.Status}}' remnawave-db)" == "healthy" ]]; do
                sleep 2
                echo -n "."
            done
            echo ""

            print_message "INFO" "Database recovery..."
            gunzip "$PANEL_DUMP"
            local sql_file="${PANEL_DUMP%.gz}"
            local restore_log="$temp_restore_dir/restore_errors.log"

            if ! docker exec -i remnawave-db psql -q -U "$DB_USER" -d "$restore_db_name" > /dev/null 2> "$restore_log" < "$sql_file"; then
                echo ""
                print_message "ERROR" "Database recovery error."
                [[ -f "$restore_log" ]] && cat "$restore_log"
                rm -rf "$temp_restore_dir"
                read -rp "Press Enter to return to the menu..."
                return 1
            fi

            print_message "SUCCESS" "The database was successfully restored."
            echo ""
            print_message "INFO" "Launching the remaining containers..."
            
            if docker compose up -d; then
                print_message "SUCCESS" "The panel has been launched successfully."
                PANEL_STATUS=0
            else
                print_message "ERROR" "Panel containers failed to start."
                rm -rf "$temp_restore_dir"
                read -rp "Press Enter to return to the menu..."
                return 1
            fi
        else
            print_message "INFO" "Panel restoration was skipped by the user."
            PANEL_STATUS=2
        fi
    fi

    echo ""

    if [[ "$PANEL_STATUS" == "0" ]]; then
        print_message "WARN" "The panel is ready. Press Enter to continue..."
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
    telegram_msg=$'💾 #restore_success\n➖➖➖➖➖➖➖➖➖\n✅ *Restore completed*\n🌊 *Remnawave:*'"${REMNAWAVE_VERSION}"

    if [[ "$PANEL_STATUS" == "0" && "$BOT_STATUS" == "0" ]]; then
        telegram_msg+=$'\n✨ *Panel and Telegram bot*'
    elif [[ "$PANEL_STATUS" == "0" ]]; then
        telegram_msg+=$'\n📦 *Panel only*'
    elif [[ "$BOT_STATUS" == "0" ]]; then
        telegram_msg+=$'\n🤖 *Telegram bot only*'
    else
        telegram_msg+=$'\n⚠️ *Nothing restored*'
    fi

    print_message "SUCCESS" "The recovery process is complete."
    send_telegram_message "$telegram_msg" >/dev/null 2>&1
    read -rp "Press Enter to return to the menu..."
}

update_script() {
    print_message "INFO" "I'm starting the process of checking for updates..."
    echo ""
    if [[ "$EUID" -ne 0 ]]; then
        echo -e "${RED}⛔ Root privileges are required to update the script. Please run it with ${BOLD}sudo${RESET}.${RESET}"
        read -rp "Press Enter to continue..."
        return
    fi

    print_message "INFO" "Getting information about the latest version of a script from GitHub..."
    local TEMP_REMOTE_VERSION_FILE
    TEMP_REMOTE_VERSION_FILE=$(mktemp)

    if ! curl -fsSL "$SCRIPT_REPO_URL" 2>/dev/null | head -n 100 > "$TEMP_REMOTE_VERSION_FILE"; then
        print_message "ERROR" "Failed to download new version information from GitHub. Check the URL or network connection."
        rm -f "$TEMP_REMOTE_VERSION_FILE"
        read -rp "Press Enter to continue..."
        return
    fi

    REMOTE_VERSION=$(grep -m 1 "^VERSION=" "$TEMP_REMOTE_VERSION_FILE" | cut -d'"' -f2)
    rm -f "$TEMP_REMOTE_VERSION_FILE"

    if [[ -z "$REMOTE_VERSION" ]]; then
        print_message "ERROR" "Failed to retrieve version information from remote script. The format of the VERSION variable may have changed."
        read -rp "Press Enter to continue..."
        return
    fi

    print_message "INFO" "Current version: ${BOLD}${YELLOW}${VERSION}${RESET}"
    print_message "INFO" "Available version: ${BOLD}${GREEN}${REMOTE_VERSION}${RESET}"
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
        print_message "ACTION" "An update to version ${BOLD}${REMOTE_VERSION}${RESET} is available."
        echo -e -n "Do you want to update the script? Enter ${GREEN}${BOLD}Y${RESET}/${RED}${BOLD}N${RESET}:"
        read -r confirm_update
        echo ""

        if [[ "${confirm_update,,}" != "y" ]]; then
            print_message "WARN" "The update was canceled by the user. Return to main menu."
            read -rp "Press Enter to continue..."
            return
        fi
    else
        print_message "INFO" "You have the latest version of the script installed. No update required."
        read -rp "Press Enter to continue..."
        return
    fi

    local TEMP_SCRIPT_PATH="${INSTALL_DIR}/backup-restore.sh.tmp"
    print_message "INFO" "Loading update..."
    if ! curl -fsSL "$SCRIPT_REPO_URL" -o "$TEMP_SCRIPT_PATH"; then
        print_message "ERROR" "Failed to load new version of script."
        read -rp "Press Enter to continue..."
        return
    fi

    if [[ ! -s "$TEMP_SCRIPT_PATH" ]] || ! head -n 1 "$TEMP_SCRIPT_PATH" | grep -q -e '^#!.*bash'; then
        print_message "ERROR" "The downloaded file is empty or is not an executable bash script. Updating is not possible."
        rm -f "$TEMP_SCRIPT_PATH"
        read -rp "Press Enter to continue..."
        return
    fi

    print_message "INFO" "Deleting old script backups..."
    find "$(dirname "$SCRIPT_PATH")" -maxdepth 1 -name "${SCRIPT_NAME}.bak.*" -type f -delete
    echo ""

    local BACKUP_PATH_SCRIPT="${SCRIPT_PATH}.bak.$(date +%s)"
    print_message "INFO" "Creating a backup copy of the current script..."
    cp "$SCRIPT_PATH" "$BACKUP_PATH_SCRIPT" || {
        echo -e "${RED}❌ Failed to back up ${BOLD}${SCRIPT_PATH}${RESET}. Update cancelled.${RESET}"
        rm -f "$TEMP_SCRIPT_PATH"
        read -rp "Press Enter to continue..."
        return
    }
    echo ""

    mv "$TEMP_SCRIPT_PATH" "$SCRIPT_PATH" || {
        echo -e "${RED}❌ Error moving temporary file to ${BOLD}${SCRIPT_PATH}${RESET}. Please check your permissions.${RESET}"
        echo -e "${YELLOW}⚠️ Restoring from a backup ${BOLD}${BACKUP_PATH_SCRIPT}${RESET}...${RESET}"
        mv "$BACKUP_PATH_SCRIPT" "$SCRIPT_PATH"
        rm -f "$TEMP_SCRIPT_PATH"
        read -rp "Press Enter to continue..."
        return
    }

    chmod +x "$SCRIPT_PATH"
    print_message "SUCCESS" "The script was successfully updated to version ${BOLD}${GREEN}${REMOTE_VERSION}${RESET}."
    echo ""
    print_message "INFO" "The script will be restarted to apply the changes..."
    read -rp "Press Enter to restart."
    exec "$SCRIPT_PATH" "$@"
    exit 0
}

remove_script() {
    print_message "WARN" "${YELLOW}ATTENTION!${RESET} The following will be deleted:"
    echo  "- Script"
    echo  "- Installation directory and all backups"
    echo  "- Symbolic link (if exists)"
    echo  "- cron tasks"
    echo ""
    echo -e -n "Are you sure you want to continue? Enter ${GREEN}${BOLD}Y${RESET}/${RED}${BOLD}N${RESET}:"
    read -r confirm
    echo ""
    
    if [[ "${confirm,,}" != "y" ]]; then
    print_message "WARN" "Deletion cancelled."
    read -rp "Press Enter to continue..."
    return
    fi

    if [[ "$EUID" -ne 0 ]]; then
        print_message "WARN" "Complete removal requires root rights. Please run with ${BOLD}sudo${RESET}."
        read -rp "Press Enter to continue..."
        return
    fi

    print_message "INFO" "Deleting cron tasks..."
    if crontab -l 2>/dev/null | grep -qF "$SCRIPT_PATH backup"; then
        (crontab -l 2>/dev/null | grep -vF "$SCRIPT_PATH backup") | crontab -
        print_message "SUCCESS" "Cron tasks for automatic backup have been removed."
    else
        print_message "INFO" "No cron jobs were found for automatic backup."
    fi
    echo ""

    print_message "INFO" "Removing a symbolic link..."
    if [[ -L "$SYMLINK_PATH" ]]; then
        rm -f "$SYMLINK_PATH" && print_message "SUCCESS" "The symbolic link ${BOLD}${SYMLINK_PATH}${RESET} has been removed." || print_message "WARN" "Failed to remove symbolic link ${BOLD}${SYMLINK_PATH}${RESET}. Manual removal may be required."
    elif [[ -e "$SYMLINK_PATH" ]]; then
        print_message "WARN" "${BOLD}${SYMLINK_PATH}${RESET} exists but is not a symbolic link. It is recommended to check and remove manually."
    else
        print_message "INFO" "Symbolic link ${BOLD}${SYMLINK_PATH}${RESET} not found."
    fi
    echo ""

    print_message "INFO" "Deleting the installation directory and all data..."
    if [[ -d "$INSTALL_DIR" ]]; then
        rm -rf "$INSTALL_DIR" && print_message "SUCCESS" "The installation directory ${BOLD}${INSTALL_DIR}${RESET} (including script, configuration, and backups) has been deleted." || echo -e "${RED}❌ Error deleting directory ${BOLD}${INSTALL_DIR}${RESET}. You may need root permissions or the directory may be in use.${RESET}"
    else
        print_message "INFO" "The installation directory ${BOLD}${INSTALL_DIR}${RESET} was not found."
    fi
    exit 0
}

configure_upload_method() {
    while true; do
        clear
        echo -e "${GREEN}${BOLD}Configuring backup delivery method${RESET}"
        echo ""
        print_message "INFO" "Current method: ${BOLD}${UPLOAD_METHOD^^}${RESET}"
        echo ""
        echo "1. Set the sending method: Telegram"
        echo "2. Set the sending method: Google Drive"
        echo ""
        echo "0. Return to main menu"
        echo ""
        read -rp "${GREEN}[?]${RESET} Select an item:" choice
        echo ""

        case $choice in
            1)
                UPLOAD_METHOD="telegram"
                save_config
                print_message "SUCCESS" "The sending method is set to ${BOLD}Telegram${RESET}."
                if [[ -z "$BOT_TOKEN" || -z "$CHAT_ID" ]]; then
                    print_message "ACTION" "Please enter your Telegram details:"
                    echo ""
                    print_message "INFO" "Create a Telegram bot in ${CYAN}@BotFather${RESET} and get an API Token"
                    read -rp "Enter API Token:" BOT_TOKEN
                    echo ""
                    print_message "INFO" "You can find out your ID from this bot in Telegram ${CYAN}@userinfobot${RESET}"
                    read -rp "Enter your Telegram ID:" CHAT_ID
                    save_config
                    print_message "SUCCESS" "Telegram settings are saved."
                fi
                ;;
            2)
                UPLOAD_METHOD="google_drive"
                print_message "SUCCESS" "The sending method is set to ${BOLD}Google Drive${RESET}."
                
                local gd_setup_successful=true

                if [[ -z "$GD_CLIENT_ID" || -z "$GD_CLIENT_SECRET" || -z "$GD_REFRESH_TOKEN" ]]; then
                    print_message "ACTION" "Please enter your Google Drive API details."
                    echo ""
                    echo "If you do not have Client ID and Client Secret tokens"
                    local guide_url="https://telegra.ph/Nastrojka-Google-API-06-02"
                    print_message "LINK" "Check out this guide: ${CYAN}${guide_url}${RESET}"
                    read -rp "Enter Google Client ID:" GD_CLIENT_ID
                    read -rp "Enter Google Client Secret:" GD_CLIENT_SECRET
                    
                    clear
                    
                    print_message "WARN" "To receive a Refresh Token, you must log in to your browser."
                    print_message "INFO" "Open the following link in your browser, log in and copy the ${BOLD}code${RESET}:"
                    echo ""
                    local auth_url="https://accounts.google.com/o/oauth2/auth?client_id=${GD_CLIENT_ID}&redirect_uri=urn:ietf:wg:oauth:2.0:oob&scope=https://www.googleapis.com/auth/drive&response_type=code&access_type=offline"
                    print_message "INFO" "${CYAN}${auth_url}${RESET}"
                    echo ""
                    read -rp "Enter the code from the browser:" AUTH_CODE
                    
                    print_message "INFO" "Receiving Refresh Token..."
                    local token_response=$(curl -s -X POST https://oauth2.googleapis.com/token \
                        -d client_id="$GD_CLIENT_ID" \
                        -d client_secret="$GD_CLIENT_SECRET" \
                        -d code="$AUTH_CODE" \
                        -d redirect_uri="urn:ietf:wg:oauth:2.0:oob" \
                        -d grant_type="authorization_code")
                    
                    GD_REFRESH_TOKEN=$(echo "$token_response" | jq -r .refresh_token 2>/dev/null)
                    
                    if [[ -z "$GD_REFRESH_TOKEN" || "$GD_REFRESH_TOKEN" == "null" ]]; then
                        print_message "ERROR" "Failed to obtain Refresh Token. Check the entered data."
                        print_message "WARN" "The setup is not completed, the sending method will be changed to ${BOLD}Telegram${RESET}."
                        UPLOAD_METHOD="telegram"
                        gd_setup_successful=false
                    else
                        print_message "SUCCESS" "Refresh Token successfully received."
                    fi
                    echo
                    
                    if $gd_setup_successful; then
                        echo "📁 To specify the Google Drive folder:"
                        echo "1. Create and open the desired folder in the browser."
                        echo "2. Look at the link in the address bar, it looks like this:"
                        echo "      https://drive.google.com/drive/folders/1a2B3cD4eFmNOPqRstuVwxYz"
                        echo "3. Copy the part after /folders/ - this is the Folder ID:"
                        echo "4. If you leave the field empty, the backup will be sent to the root folder of Google Drive."
                        echo

                        read -rp "Enter Google Drive Folder ID (leave blank for root folder):" GD_FOLDER_ID
                    fi
                fi

                save_config

                if $gd_setup_successful; then
                    print_message "SUCCESS" "Google Drive settings are saved."
                else
                    print_message "SUCCESS" "The sending method is set to ${BOLD}Telegram${RESET}."
                fi
                ;;
            0) break ;;
            *) print_message "ERROR" "Invalid input. Please select one of the suggested items." ;;
        esac
        echo ""
        read -rp "Press Enter to continue..."
    done
    echo ""
}

configure_settings() {
    while true; do
        clear
        echo -e "${GREEN}${BOLD}Script configuration settings${RESET}"
        echo ""
        echo "1. Telegram settings"
        echo "2. Google Drive Settings"
        echo "3. Database username Remnawave"
        echo "4. Remnawave Path"
        echo ""
        echo "0. Return to main menu"
        echo ""
        read -rp "${GREEN}[?]${RESET} Select an item:" choice
        echo ""

        case $choice in
            1)
                while true; do
                    clear
                    echo -e "${GREEN}${BOLD}Telegram Settings${RESET}"
                    echo ""
                    print_message "INFO" "Current API Token: ${BOLD}${BOT_TOKEN}${RESET}"
                    print_message "INFO" "Current ID: ${BOLD}${CHAT_ID}${RESET}"
                    print_message "INFO" "Current Message Thread ID: ${BOLD}${TG_MESSAGE_THREAD_ID:-Not set}${RESET}"
                    echo ""
                    echo "1. Change API Token"
                    echo "2. Change ID"
                    echo "3. Change Message Thread ID (for group topics)"
                    echo ""
                    echo "0. Back"
                    echo ""
                    read -rp "${GREEN}[?]${RESET} Select an item:" telegram_choice
                    echo ""

                    case $telegram_choice in
                        1)
                            print_message "INFO" "Create a Telegram bot in ${CYAN}@BotFather${RESET} and get an API Token"
                            read -rp "Enter the new API Token:" NEW_BOT_TOKEN
                            BOT_TOKEN="$NEW_BOT_TOKEN"
                            save_config
                            print_message "SUCCESS" "API Token has been successfully updated."
                            ;;
                        2)
                            print_message "INFO" "Enter Chat ID (to send to the group) or your Telegram ID (to send directly to the bot)"
                            echo -e "Chat ID/Telegram ID can be found from this bot ${CYAN}@username_to_id_bot${RESET}"
                            read -rp "Enter new ID:" NEW_CHAT_ID
                            CHAT_ID="$NEW_CHAT_ID"
                            save_config
                            print_message "SUCCESS" "ID updated successfully."
                            ;;
                        3)
                            print_message "INFO" "Optional: to send to a specific group topic, enter the topic ID (Message Thread ID)"
                            echo -e "Leave blank for general thread or sending directly to bot"
                            read -rp "Enter Message Thread ID:" NEW_TG_MESSAGE_THREAD_ID
                            TG_MESSAGE_THREAD_ID="$NEW_TG_MESSAGE_THREAD_ID"
                            save_config
                            print_message "SUCCESS" "Message Thread ID updated successfully."
                            ;;
                        0) break ;;
                        *) print_message "ERROR" "Invalid input. Please select one of the suggested items." ;;
                    esac
                    echo ""
                    read -rp "Press Enter to continue..."
                done
                ;;

            2)
                while true; do
                    clear
                    echo -e "${GREEN}${BOLD}Google Drive Settings${RESET}"
                    echo ""
                    print_message "INFO" "Current Client ID: ${BOLD}${GD_CLIENT_ID:0:8}...${RESET}"
                    print_message "INFO" "Current Client Secret: ${BOLD}${GD_CLIENT_SECRET:0:8}...${RESET}"
                    print_message "INFO" "Current Refresh Token: ${BOLD}${GD_REFRESH_TOKEN:0:8}...${RESET}"
                    print_message "INFO" "Current Drive Folder ID: ${BOLD}${GD_FOLDER_ID:-Root folder}${RESET}"
                    echo ""
                    echo "1. Change Google Client ID"
                    echo "2. Change Google Client Secret"
                    echo "3. Change Google Refresh Token (re-authorization required)"
                    echo "4. Change Google Drive Folder ID"
                    echo ""
                    echo "0. Back"
                    echo ""
                    read -rp "${GREEN}[?]${RESET} Select an item:" gd_choice
                    echo ""

                    case $gd_choice in
                        1)
                            echo "If you do not have Client ID and Client Secret tokens"
                            local guide_url="https://telegra.ph/Nastrojka-Google-API-06-02"
                            print_message "LINK" "Check out this guide: ${CYAN}${guide_url}${RESET}"
                            read -rp "Enter your new Google Client ID:" NEW_GD_CLIENT_ID
                            GD_CLIENT_ID="$NEW_GD_CLIENT_ID"
                            save_config
                            print_message "SUCCESS" "Google Client ID has been successfully updated."
                            ;;
                        2)
                            echo "If you do not have Client ID and Client Secret tokens"
                            local guide_url="https://telegra.ph/Nastrojka-Google-API-06-02"
                            print_message "LINK" "Check out this guide: ${CYAN}${guide_url}${RESET}"
                            read -rp "Enter your new Google Client Secret:" NEW_GD_CLIENT_SECRET
                            GD_CLIENT_SECRET="$NEW_GD_CLIENT_SECRET"
                            save_config
                            print_message "SUCCESS" "Google Client Secret has been successfully updated."
                            ;;
                        3)
                            clear
                            print_message "WARN" "To receive a new Refresh Token, you must log in to your browser."
                            print_message "INFO" "Open the following link in your browser, log in and copy the ${BOLD}code${RESET}:"
                            echo ""
                            local auth_url="https://accounts.google.com/o/oauth2/auth?client_id=${GD_CLIENT_ID}&redirect_uri=urn:ietf:wg:oauth:2.0:oob&scope=https://www.googleapis.com/auth/drive&response_type=code&access_type=offline"
                            print_message "LINK" "${CYAN}${auth_url}${RESET}"
                            echo ""
                            read -rp "Enter the code from the browser:" AUTH_CODE
                            
                            print_message "INFO" "Receiving Refresh Token..."
                            local token_response=$(curl -s -X POST https://oauth2.googleapis.com/token \
                                -d client_id="$GD_CLIENT_ID" \
                                -d client_secret="$GD_CLIENT_SECRET" \
                                -d code="$AUTH_CODE" \
                                -d redirect_uri="urn:ietf:wg:oauth:2.0:oob" \
                                -d grant_type="authorization_code")
                            
                            NEW_GD_REFRESH_TOKEN=$(echo "$token_response" | jq -r .refresh_token 2>/dev/null)
                            
                            if [[ -z "$NEW_GD_REFRESH_TOKEN" || "$NEW_GD_REFRESH_TOKEN" == "null" ]]; then
                                print_message "ERROR" "Failed to obtain Refresh Token. Check the entered data."
                                print_message "WARN" "Setup is not complete."
                            else
                                GD_REFRESH_TOKEN="$NEW_GD_REFRESH_TOKEN"
                                save_config
                                print_message "SUCCESS" "Refresh Token has been successfully updated."
                            fi
                            ;;
                        4)
                            echo
                            echo "📁 To specify the Google Drive folder:"
                            echo "1. Create and open the desired folder in the browser."
                            echo "2. Look at the link in the address bar, it looks like this:"
                            echo "      https://drive.google.com/drive/folders/1a2B3cD4eFmNOPqRstuVwxYz"
                            echo "3. Copy the part after /folders/ - this is the Folder ID:"
                            echo "4. If you leave the field empty, the backup will be sent to the root folder of Google Drive."
                            echo
                            read -rp "Enter your new Google Drive Folder ID (leave blank for root folder):" NEW_GD_FOLDER_ID
                            GD_FOLDER_ID="$NEW_GD_FOLDER_ID"
                            save_config
                            print_message "SUCCESS" "Google Drive Folder ID has been successfully updated."
                            ;;
                        0) break ;;
                        *) print_message "ERROR" "Invalid input. Please select one of the suggested items." ;;
                    esac
                    echo ""
                    read -rp "Press Enter to continue..."
                done
                ;;
            3)
                clear
                echo -e "${GREEN}${BOLD}PostgreSQL username${RESET}"
                echo ""
                print_message "INFO" "Current PostgreSQL username: ${BOLD}${DB_USER}${RESET}"
                echo ""
                read -rp "Enter a new PostgreSQL username (postgres by default):" NEW_DB_USER
                DB_USER="${NEW_DB_USER:-postgres}"
                save_config
                print_message "SUCCESS" "The PostgreSQL username was successfully updated to ${BOLD}${DB_USER}${RESET}."
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            4)
                clear
                echo -e "${GREEN}${BOLD}Remnawave Path${RESET}"
                echo ""
                print_message "INFO" "Current Remnawave path: ${BOLD}${REMNALABS_ROOT_DIR}${RESET}"
                echo ""
                print_message "ACTION" "Select a new path for the Remnawave panel:"
                echo " 1. /opt/remnawave"
                echo " 2. /root/remnawave"
                echo " 3. /opt/stacks/remnawave"
                echo "4. Show your path"
                echo ""
                echo "0. Back"
                echo ""

                local new_remnawave_path_choice
                while true; do
                    read -rp "${GREEN}[?]${RESET} Select an option:" new_remnawave_path_choice
                    case "$new_remnawave_path_choice" in
                    1) REMNALABS_ROOT_DIR="/opt/remnawave"; break ;;
                    2) REMNALABS_ROOT_DIR="/root/remnawave"; break ;;
                    3) REMNALABS_ROOT_DIR="/opt/stacks/remnawave"; break ;;
                    4) 
                        echo ""
                        print_message "INFO" "Enter the full path to the Remnawave panel directory:"
                        read -rp "Path:" new_custom_remnawave_path
        
                        if [[ -z "$new_custom_remnawave_path" ]]; then
                            print_message "ERROR" "The path cannot be empty."
                            echo ""
                            read -rp "Press Enter to continue..."
                            continue
                        fi
        
                        if [[ ! "$new_custom_remnawave_path" = /* ]]; then
                            print_message "ERROR" "The path must be absolute (starting with /)."
                            echo ""
                            read -rp "Press Enter to continue..."
                            continue
                        fi
        
                        new_custom_remnawave_path="${new_custom_remnawave_path%/}"
        
                        if [[ ! -d "$new_custom_remnawave_path" ]]; then
                            print_message "WARN" "The directory ${BOLD}${new_custom_remnawave_path}${RESET} does not exist."
                            read -rp "$(echo -e "${GREEN}[?]${RESET} Continue with this path? ${GREEN}${BOLD}Y${RESET}/${RED}${BOLD}N${RESET}:")" confirm_new_custom_path
                            if [[ "$confirm_new_custom_path" != "y" ]]; then
                                echo ""
                                read -rp "Press Enter to continue..."
                                continue
                            fi
                        fi
        
                        REMNALABS_ROOT_DIR="$new_custom_remnawave_path"
                        print_message "SUCCESS" "New custom path set: ${BOLD}${REMNALABS_ROOT_DIR}${RESET}"
                        break 
                        ;;
                    0) 
                        return
                        ;;
                    *) print_message "ERROR" "Invalid input." ;;
                    esac
                done
                save_config
                print_message "SUCCESS" "Remnawave path successfully updated to ${BOLD}${REMNALABS_ROOT_DIR}${RESET}."
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            0) break ;;
            *) print_message "ERROR" "Invalid input. Please select one of the suggested items." ;;
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
            echo -e "${BOLD}${LIGHT_GRAY}Version: ${VERSION} ${RED}update available${RESET}"
        else
            echo -e "${BOLD}${LIGHT_GRAY}Version: ${VERSION}${RESET}"
        fi
        echo ""
        echo "1. Create a backup manually"
        echo "2. Restore from backup"
        echo ""
        echo "3. Configure Telegram Shop backup"
        echo "4. Setting up automatic sending and notifications"
        echo "5. Setting up the sending method"
        echo "6. Setting up the script configuration"
        echo ""
        echo "7. Script update"
        echo "8. Deleting the script"
        echo ""
        echo "0. Exit"
        echo -e "— Quick start: ${BOLD}${GREEN}rw-backup${RESET} is available from anywhere in the system"
        echo ""

        read -rp "${GREEN}[?]${RESET} Select an item:" choice
        echo ""
        case $choice in
            1) create_backup ; read -rp "Press Enter to continue..." ;;
            2) restore_backup ;;
            3) configure_bot_backup ;;
            4) setup_auto_send ;;
            5) configure_upload_method ;;
            6) configure_settings ;;
            7) update_script ;;
            8) remove_script ;;
            0) echo "Exit..."; exit 0 ;;
            *) print_message "ERROR" "Invalid input. Please select one of the suggested items." ; read -rp "Press Enter to continue..." ;;
        esac
    done
}

if ! command -v jq &> /dev/null; then
    print_message "INFO" "Installing package "jq" for JSON parsing..."
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}❌ Error: Installing "jq" requires root privileges. Please install "jq" manually (for example: "sudo apt-get install jq") or run the script with sudo.${RESET}"
        exit 1
    fi
    if command -v apt-get &> /dev/null; then
        apt-get update -qq > /dev/null 2>&1
        apt-get install -y jq > /dev/null 2>&1 || { echo -e "${RED}❌ Error: Failed to install "jq".${RESET}"; exit 1; }
        print_message "SUCCESS" ""jq" installed successfully."
    else
        print_message "ERROR" "apt-get package manager not found. Please install "jq" manually."
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
    echo -e "${RED}❌ Incorrect usage. Available commands: ${BOLD}${0} [backup|restore|update|remove]${RESET}${RESET}"
    exit 1
fi
