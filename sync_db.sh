#!/bin/bash

# Exit immediately if any command in a pipeline fails
# This ensures errors from SSH/Docker commands are properly caught
set -o pipefail

# Load environment configuration from .env file
if [ -f .env ]; then
    # Parse .env file and export variables
    # Handles quoted values and ignores comments
    while IFS='=' read -r key value; do
        if [[ ! -z "$key" && ! "$key" =~ ^# ]]; then
            # Strip surrounding quotes from values
            value="${value%\"}"
            value="${value#\"}"
            value="${value%\'}"
            value="${value#\'}"
            export "$key=$value"
        fi
    done < .env
else
    echo "Error: .env file not found!"
    exit 1
fi

# Configure local database connection with fallback defaults
LOCAL_DB_HOST=${LOCAL_DB_HOST:-localhost}
LOCAL_DB_PORT=${LOCAL_DB_PORT:-5432}
LOCAL_DB_USER=${LOCAL_DB_USER:-postgres}

# Set PostgreSQL password environment variable if provided
if [ -n "$LOCAL_DB_PASS" ]; then
    export PGPASSWORD="$LOCAL_DB_PASS"
fi

# Interactive menu function with keyboard navigation (Up/Down/Enter)
# Displays a list of options and allows arrow key selection
function select_option() {
    local prompt="$1"
    local outvar="$2"
    shift 2
    local options=("$@")
    local cur=0
    local count=${#options[@]}
    local index=0
    local esc=$(echo -en "\e")
    
    printf "%s\n" "$prompt"
    
    # Hide cursor during selection
    tput civis
    
    while true; do
        index=0
        for o in "${options[@]}"; do
            if [ "$index" -eq "$cur" ]; then
                printf " \e[32m> %s\e[0m\n" "$o"
            else
                printf "   %s\n" "$o"
            fi
            ((index++))
        done
        
        # Read keyboard input
        read -s -n 1 key
        if [[ $key == "" ]]; then # Enter key
            break
        elif [[ $key == $'\x1b' ]]; then
            read -s -n 2 key
            if [[ $key == "[A" ]]; then # Up arrow
                ((cur--))
                [ "$cur" -lt 0 ] && cur=$((count-1))
            elif [[ $key == "[B" ]]; then # Down arrow
                ((cur++))
                [ "$cur" -ge "$count" ] && cur=0
            fi
        fi
        
        # Clear menu lines for redraw
        printf "\e[${count}A"
    done
    
    # Restore cursor visibility
    tput cnorm
    
    eval "$outvar=\"${options[$cur]}\""
}

echo "==============================================="
echo "            Database Sync Tool"
echo "==============================================="

# Extract list of configured servers from environment variables
# Looks for variables ending with _SSH_HOST
servers=()
for key in $(env | grep "_SSH_HOST" | cut -d'_' -f1); do
    servers+=("$key")
done

if [ ${#servers[@]} -eq 0 ]; then
    echo "Error: No servers found in .env (Looking for *_SSH_HOST)"
    exit 1
fi

# Prompt user to select target server
select_option "Select Target Server:" PREFIX "${servers[@]}"
echo "Selected Server: ${PREFIX}"
echo "-----------------------------------------------"

# Build variable names based on selected server prefix
SSH_HOST="${PREFIX}_SSH_HOST"
SSH_PORT="${PREFIX}_SSH_PORT"
SSH_USER="${PREFIX}_SSH_USER"
SSH_KEY="${PREFIX}_SSH_KEY"
DB_CONTAINER="${PREFIX}_DB_CONTAINER_NAME"
DB_USER="${PREFIX}_DB_USER"
DB_PASS="${PREFIX}_DB_PASS"

# Validate that required configuration exists
if [ -z "${!DB_CONTAINER}" ]; then
    echo "Error: Container name not found for prefix $PREFIX in .env"
    exit 1
fi

# Select remote database to sync from
REMOTE_DB_VAR="${PREFIX}_DATABASES"
# Convert space-separated string to array using word splitting
remote_dbs=( ${!REMOTE_DB_VAR} )

if [ ${#remote_dbs[@]} -gt 0 ]; then
    select_option "Select Remote Database:" REMOTE_DB "${remote_dbs[@]}"
    echo "Selected Remote DB: ${REMOTE_DB}"
else
    read -p "Enter Remote Database Name manually (Not found in .env): " REMOTE_DB
fi
echo "-----------------------------------------------"

# Select local database destination
# Priority: server-specific config, then global fallback
LOCAL_DB_VAR="${PREFIX}_LOCAL_DATABASES"
if [ -n "${!LOCAL_DB_VAR}" ]; then
    local_dbs=( ${!LOCAL_DB_VAR} )
else
    local_dbs=( ${LOCAL_DATABASES} )
fi

if [ ${#local_dbs[@]} -gt 0 ]; then
    select_option "Select Local Database destination:" LOCAL_DB "${local_dbs[@]}"
    echo "Selected Local DB: ${LOCAL_DB}"
else
    read -p "Enter Local Database Name (e.g. ${REMOTE_DB}): " LOCAL_DB
    LOCAL_DB=${LOCAL_DB:-$REMOTE_DB} # Use remote name as default
fi

echo "==============================================="
echo "Target Server: ${!SSH_HOST}"
echo "Container: ${!DB_CONTAINER}"
echo "Syncing: ${REMOTE_DB} -> Local: ${LOCAL_DB}"
echo "==============================================="

# Step 1: Reset local database
# Terminate all active connections and recreate the database
echo "Step 1: Forcefully resetting local database..."

# Connect to default 'postgres' database to terminate all sessions on target database
# This prevents "database is being accessed by other users" errors
psql -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -U "$LOCAL_DB_USER" -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$LOCAL_DB' AND pid <> pg_backend_pid();" > /dev/null 2>&1

# Drop and recreate the database with a clean slate
dropdb --if-exists -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -U "$LOCAL_DB_USER" "$LOCAL_DB"
createdb -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -U "$LOCAL_DB_USER" "$LOCAL_DB"

# Step 2: Stream database dump from remote server to local database
echo "Step 2: Syncing data (Streaming)..."

# SSH into remote server, execute pg_dump inside Docker container, and pipe directly to local psql
# -T flag prevents SSH from allocating a pseudo-terminal, avoiding MOTD and other text interference
ssh -T -i "${!SSH_KEY}" -p "${!SSH_PORT}" "${!SSH_USER}@${!SSH_HOST}" \
    "docker exec -e PGPASSWORD='${!DB_PASS}' ${!DB_CONTAINER} pg_dump -U ${!DB_USER} -d ${REMOTE_DB} --clean --no-owner" \
    | psql -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -U "$LOCAL_DB_USER" -d "$LOCAL_DB"

# Check exit status of the entire pipeline
if [ $? -eq 0 ]; then
    echo "✅ Successfully synced ${REMOTE_DB} to ${LOCAL_DB}!"
else
    echo "❌ Error occurred during sync. Please check container name or connectivity."
fi