<div align="center">

<a href="https://github.com/distillium/remnawave-backup-restore">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="./media/logo.png" />
   <source media="(prefers-color-scheme: light)" srcset="./media/logo-black.png" />
   <img alt="Remnawave Backup & Restore" src="./media/logo.png" width="520" />
 </picture>
</a>

Backup and restore for the **Remnawave** panel and your **Telegram shop**:<br>
scheduled, to Telegram or S3, encrypted, with selective restore.

**English** · [Русский](README-RU.md)

<details>
<summary><b>What the menu looks like</b></summary>
<br>

<img src="./media/preview.png" alt="Main menu" width="720">

</details>

</div>

> [!CAUTION]
> The script backs up only the **Remnawave directory and database** and, optionally, a **Telegram shop**. Other services are up to you.

> [!IMPORTANT]
> **Google Drive is not supported since 4.3.0**: the script switches to Telegram on its own. For backups over 50 MB, connect S3.

## Installation

```bash
curl -o ~/backup-restore.sh https://raw.githubusercontent.com/distillium/remnawave-backup-restore/main/backup-restore.sh && chmod +x ~/backup-restore.sh && ~/backup-restore.sh
```

Requires root. After installation, open the menu with `rw-backup`.

## Details

<details>
<summary><b>Features</b></summary>
<br>

- manual or scheduled backups: panel and bot, panel only or bot only
- the panel's Docker database and external PostgreSQL
- upload to Telegram (direct chat or group topic) or to S3 storage, up to 5 at once
- retention on the server (days or hours) and in each S3 separately
- disk and S3 usage, with an optional S3 limit
- encryption with an [age](https://github.com/FiloSottile/age) key
- selective restore: everything, database only or files only
- S3 and Telegram proxy tests with clear error diagnostics
- new version notices and auto-update

</details>

<details>
<summary><b>Menu</b></summary>
<br>

| # | Item | Inside |
|:-:|---|---|
| 1 | Create backup now | a backup with the current settings |
| 2 | Restore from backup | pick an archive and what to restore |
| 3 | What to back up | panel, bot, backup mode |
| 4 | Where to send | Telegram or S3, list of storages |
| 5 | Schedule and retention | schedule and retention periods |
| 6 | Settings | Telegram, encryption, language, auto-update |
| 7 | Logs | backup, restore, errors, cron |

</details>

<details>
<summary><b>Selective restore</b></summary>
<br>

If a backup has both a database and files, the script asks what to restore:

| Option | What happens |
|---|---|
| **Everything** | database and files |
| **Database only** | the DB volume is recreated, files are left as they are. The panel or bot must already be installed |
| **Files only** | files and settings are replaced, the database is left as it is |

Handy for rolling back only the database after a failed update.

</details>

<details>
<summary><b>Encryption</b></summary>
<br>

Turn it on in **Settings → Encryption**. Backups are encrypted with an [age](https://github.com/FiloSottile/age) public key, and only that key is kept on the server. To restore, the script asks for the private key.

**Important:** without the private key an encrypted backup can't be restored. Keep it away from the server.

</details>

<details>
<summary><b>Supported bots</b></summary>
<br>

| Bot | Directory |
|---|---|
| Jesus Bot | `remnawave-telegram-shop` |
| Private Jesus Bot | `rwp-shop` |
| Machka Bot | `remnawave-tg-shop` |
| Snoups Bot | `remnashop` |
| Minishop Bot | `remnawave-minishop` |

</details>

<details>
<summary><b>Moving to another server</b></summary>
<br>

<blockquote>

<details>
  <summary>◦ Panel only: moving to a new server</summary>
  <br>

1. In Cloudflare, point the panel subdomain to the new IP. If other services move to the new server too, update their subdomains as well.
2. Restore the directory and the database.
3. Restore the domain certificates if needed.
4. The access link and password stay the same as in the old panel the backup was made from.
5. On every node, replace the rule for the service port (2222 by default) so the panel on the new IP can reach them. Run on each node, with your own `OLD_IP` and `NEW_IP`:

```bash
ufw delete allow from OLD_IP to any port 2222 && ufw allow from NEW_IP to any port 2222
```

Done. All that's left is to install and set up the other services you need (e.g. kuma, beszel).

</details>

<details>
  <summary>◦ Panel + node: moving to a new server</summary>
  <br>

1. In Cloudflare, point the subdomains of the panel and the "root" node (the one on the panel server) to the new IP. If other services move to the new server too, update their subdomains as well.
2. Restore the domain certificates if needed.
3. Restore the directory and the database.
4. Open panel access via port 8443 (eGames script, "Panel access management").
5. The access link and password stay the same as in the old panel the backup was made from.
6. In node management, find the root node. It has the old server address: change it to the new one and the node comes up on its own.
7. Close panel access via port 8443 the same way you opened it.
8. On every external node, replace the rule for the service port (2222 by default). Run on each node, with your own `OLD_IP` and `NEW_IP`:

```bash
ufw delete allow from OLD_IP to any port 2222 && ufw allow from NEW_IP to any port 2222
```

Done. All that's left is to install and set up the other services you need (e.g. kuma, beszel).

</details>

<details>
  <summary>◦ Panel + node → "Panel only" on the current server</summary>
  <br>

1. Restore the directory and the database.
2. The access link and password stay the same as in the old panel the backup was made from.
3. Delete the old "root" node from the panel together with its inbound and host.
4. Delete the `.env-node` file from the panel server:

```bash
rm /opt/remnawave/.env-node
```

Done. All that's left is to install and set up the other services you need (e.g. kuma, beszel).

</details>

<details>
  <summary>◦ Panel + node → "Panel only" on a new server</summary>
  <br>

1. In Cloudflare, point the panel subdomain to the new IP. If other services move to the new server too, update their subdomains as well.
2. Restore the domain certificates if needed.
3. Restore the directory and the database.
4. The access link and password stay the same as in the old panel the backup was made from.
5. Delete the old "root" node from the panel together with its inbound and host.
6. Delete the `.env-node` file from the panel server:

```bash
rm /opt/remnawave/.env-node
```

7. On every node, replace the rule for the service port (2222 by default). Run on each node, with your own `OLD_IP` and `NEW_IP`:

```bash
ufw delete allow from OLD_IP to any port 2222 && ufw allow from NEW_IP to any port 2222
```

Done. All that's left is to install and set up the other services you need (e.g. kuma, beszel).

</details>

</blockquote>

</details>

<details>
<summary><b>Commands and files</b></summary>
<br>

| Command | What it does |
|---|---|
| `rw-backup` | open the menu |
| `rw-backup backup` | back up without the menu (this is what the schedule runs) |
| `rw-backup restore` | restore |
| `rw-backup update` | update the script |
| `rw-backup remove` | remove the script |

Everything lives in `/opt/rw-backup-restore`: settings in `config.env`, backups in `backup/`, logs in `logs/`.

</details>

<div align="center">

## Support the Project

<p align="center">
  <a href="https://t.me/tribute/app?startapp=dRNM">
    <img src="https://img.shields.io/badge/Donate-Telegram%20Mini%20App-26A5E4?style=for-the-badge&logo=telegram&logoColor=white" alt="Donate via Telegram">
  </a>
  &nbsp;
  <a href="https://web.tribute.tg/d/RNM">
    <img src="https://img.shields.io/badge/Donate-Tribute%20Web-8A2BE2?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="Donate via Tribute Web">
  </a>
</p>

Thank you for your support!

</div>
