# Database Sync Tool

A simple and interactive bash script for syncing PostgreSQL databases from remote Docker containers to your local machine via SSH.

## Features

- 🎯 Interactive menu-driven interface with keyboard navigation
- 🔄 Stream-based database synchronization (no intermediate dump files)
- 🔐 Secure SSH key-based authentication
- 🐳 Docker container support
- 📦 Multi-server and multi-database configuration
- ⚡ Fast and efficient data transfer

## Prerequisites

- Bash shell (Linux/macOS)
- PostgreSQL client tools (`psql`, `pg_dump`, `dropdb`, `createdb`)
- SSH access to remote servers
- Docker running on remote servers with PostgreSQL containers

## Installation

1. Clone this repository:
```bash
git clone <repository-url>
cd <repository-name>
```

2. Make the script executable:
```bash
chmod +x sync_db.sh
```

3. Copy the example environment file and configure it:
```bash
cp .env.example .env
```

4. Edit `.env` with your server and database configurations

## Configuration

Edit the `.env` file with your server details. Each server configuration requires:

```bash
# Server identifier (e.g., PRODUCTION, STAGING)
SERVER_NAME_SSH_HOST="your.server.ip"
SERVER_NAME_SSH_PORT="22"
SERVER_NAME_SSH_USER="ssh_username"
SERVER_NAME_SSH_KEY="/path/to/ssh/key"

SERVER_NAME_DB_CONTAINER_NAME="postgresql_container"
SERVER_NAME_DB_USER="db_user"
SERVER_NAME_DB_PASS="db_password"

# Available databases
SERVER_NAME_DATABASES="remote_db1 remote_db2"
SERVER_NAME_LOCAL_DATABASES="local_db1 local_db2"
```

### Local Database Configuration

```bash
LOCAL_DB_HOST="localhost"
LOCAL_DB_PORT="5432"
LOCAL_DB_USER="your_local_user"
LOCAL_DB_PASS="your_local_password"
```

## Usage

Run the script:
```bash
./sync_db.sh
```

The script will guide you through:
1. Selecting a target server
2. Choosing a remote database to sync from
3. Selecting a local database destination

Use arrow keys (↑/↓) to navigate and Enter to select.

## How It Works

1. **Server Selection**: Automatically detects configured servers from `.env`
2. **Database Reset**: Terminates active connections and recreates the local database
3. **Data Sync**: Streams database dump from remote Docker container directly to local PostgreSQL
4. **Verification**: Reports success or failure of the sync operation

## Security Notes

- Never commit your `.env` file to version control
- Use SSH key-based authentication
- Store SSH keys securely with appropriate permissions (chmod 600)
- Keep database passwords secure

## Troubleshooting

### Connection Issues
- Verify SSH key permissions: `chmod 600 /path/to/key`
- Test SSH connection: `ssh -i /path/to/key user@host`
- Ensure Docker container is running on remote server

### Database Issues
- Check local PostgreSQL is running: `pg_isready`
- Verify database user has necessary permissions
- Ensure local database user can create/drop databases

### Script Errors
- Check `.env` file syntax (no spaces around `=`)
- Verify all required variables are set for selected server
- Review container name matches actual Docker container

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.
