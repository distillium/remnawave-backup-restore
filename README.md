<p align="center">
  <a href="https://github.com/distillium/remnawave-backup-restore">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="./media/logo.png" />
      <source media="(prefers-color-scheme: light)" srcset="./media/logo-black.png" />
      <img alt="Remnawave Backup & Restore" src="./media/logo-black.png" width="520" />
    </picture>
  </a>
</p>

> [!CAUTION]
> This script creates and restores backups for the **Remnawave directory and PostgreSQL database**, and can optionally include a supported **Telegram Shop** installation.
> Backing up or restoring any additional services is **your responsibility**.

<details>
<summary>🌌 Main menu preview</summary>

![screenshot](./media/preview.png)

</details>

## Features

- Interactive TUI menu
- One-off backup creation
- Backup restore workflow
- Scheduled automatic backups (cron)
- Delivery to Telegram (chat or topic)
- Optional delivery to Google Drive
- Optional Telegram Shop backup/restore
- Script self-update flow
- Backup retention policy (default: 7 days)

## Supported migration scenarios

### 1) Panel only → new server

1. Point panel DNS (and related service subdomains, if needed) to the new IP.
2. Restore directory and database.
3. Re-issue TLS certificates, if required.
4. Access URL/password remain from the original panel.
5. Update node firewall rule for service port (default `2222`) on every node:

```bash
ufw delete allow from OLD_IP to any port 2222 && ufw allow from NEW_IP to any port 2222
```

### 2) Panel + root node → new server

1. Update DNS for both panel and the root node.
2. Restore directory and database.
3. Re-issue TLS certificates, if required.
4. Temporarily enable panel access via `8443` (if your setup requires it).
5. In panel node settings, replace old root-node address with the new one.
6. Disable temporary `8443` access.
7. Update port `2222` firewall allow rules on external nodes (same command as above).

### 3) Panel + root node → panel only (same server)

1. Restore directory and database.
2. Remove old root node and linked inbound/host entries in panel.
3. Remove root-node env file:

```bash
rm /opt/remnawave/.env-node
```

### 4) Panel + root node → panel only (new server)

1. Update panel DNS to the new IP.
2. Restore directory and database.
3. Re-issue TLS certificates, if required.
4. Remove old root node and linked inbound/host entries.
5. Remove `.env-node` on panel host:

```bash
rm /opt/remnawave/.env-node
```

6. Update node firewall rules for port `2222` to new panel IP.

---

## Installation (requires root)

```bash
curl -o ~/backup-restore.sh https://raw.githubusercontent.com/distillium/remnawave-backup-restore/main/backup-restore.sh \
  && chmod +x ~/backup-restore.sh \
  && ~/backup-restore.sh
```

## Command

- `rw-backup` — quick menu entrypoint from anywhere in the system
