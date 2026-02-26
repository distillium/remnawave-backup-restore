<p aling="center"><a href="https://github.com/distillium/remnawave-backup-restore">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="./media/logo.png" />
   <source media="(prefers-color-scheme: light)" srcset="./media/logo-black.png" />
   <img alt="Backup & Restore" src="https://github.com/distillium/remnawave-backup-restore" />
 </picture>
</a></p>

**🇬🇧 English** | [🇷🇺 Русский](README-RU.md)

> [!CAUTION]
> **THIS SCRIPT PERFORMS BACKUP AND RESTORE OF THE ENTIRE REMNAWAVE DIRECTORY AND DATABASE, AS WELL AS (OPTIONALLY) TELEGRAM SHOP. BACKUP AND RESTORE OF ANY OTHER SERVICES AND CONFIGURATIONS IS ENTIRELY THE USER'S RESPONSIBILITY. IT IS RECOMMENDED TO CAREFULLY FOLLOW THE INSTRUCTIONS DURING SCRIPT EXECUTION BEFORE RUNNING ANY COMMANDS.**

<details>
<summary>🌌 Main menu preview</summary>

![screenshot](./media/preview.png)
</details>

## Features:
- interactive menu
- manual and scheduled automatic backup creation
- backup/restore in panel+bot, panel only, and bot only modes
- external PostgreSQL support
- notifications directly to Telegram bot or group topic with attached backup
- script version update notifications
- backup size check before sending to TG and limit exceeded notification
- backup upload to Google Drive (optional)
- server-side backup retention policy (7 days)

## Additional migration instructions:

<details>
  <summary>📝 Panel only: migrating to a new server</summary>
  
- edit the panel subdomain in Cloudflare to point to the new IP address. Also update subdomains of other services if they will be hosted on the new server
- perform directory and database restore
- restore domain certificates on your own (if required)
- the access link and password will be from the old panel that was previously backed up
- delete the old rule for the service port (default 2222) on all nodes and create a new one. This is necessary for the panel with the new IP address to communicate with them. Run the command on each node, replacing `OLD_IP` and `NEW_IP` with your own:

```bash
ufw delete allow from OLD_IP to any port 2222 && ufw allow from NEW_IP to any port 2222
```

- you're all set! All that's left is to install and configure any other services you need (e.g. kuma, beszel, etc.)

</details>

<details>
  <summary>📝 Panel+node: migrating to a new server</summary>
  
- edit the panel and "root" node (co-located with the panel) subdomains in Cloudflare to point to the new IP address. Also update subdomains of other services if they will be hosted on the new server
- restore domain certificates on your own (if required)
- perform directory and database restore
- enable panel access via port 8443 (eGames script, "Panel access management" option)
- the access link and password will be from the old panel that was previously backed up
- in node management, find the root node co-located with the panel. It contains the old server address. Change it to the new one — the node will activate automatically
- now close panel access via port 8443 the same way you opened it
- delete the old rule for the service port (default 2222) on all external nodes and create a new one. This is necessary for the panel with the new IP address to communicate with them. Run the command on each node, replacing `OLD_IP` and `NEW_IP` with your own:

```bash
ufw delete allow from OLD_IP to any port 2222 && ufw allow from NEW_IP to any port 2222
```

- you're all set! All that's left is to install and configure any other services you need (e.g. kuma, beszel, etc.)

</details>

<details>
  <summary>📝 Panel+node: switching to "Panel only" on the current server</summary>
  
- perform directory and database restore
- the access link and password will be from the old panel that was previously backed up
- delete the old "root" node from the panel along with its associated inbound and host
- delete the `.env-node` file from the panel server:
  
```bash
rm /opt/remnawave/.env-node
```

- you're all set! All that's left is to install and configure any other services you need (e.g. kuma, beszel, etc.)

</details>

<details>
  <summary>📝 Panel+node: switching to "Panel only" on a new server</summary>

- edit the panel subdomains in Cloudflare to point to the new IP address. Also update subdomains of other services if they will be hosted on the new server
- restore domain certificates on your own (if required)
- perform directory and database restore
- the access link and password will be from the old panel that was previously backed up
- delete the old "root" node from the panel along with its associated inbound and host
- delete the `.env-node` file from the panel server:
  
```bash
rm /opt/remnawave/.env-node
```

- delete the old rule for the service port (default 2222) on all nodes and create a new one. This is necessary for the panel with the new IP address to communicate with the nodes. Run the command on each node, replacing `OLD_IP` and `NEW_IP` with your own:

```bash
ufw delete allow from OLD_IP to any port 2222 && ufw allow from NEW_IP to any port 2222
```

- you're all set! All that's left is to install and configure any other services you need (e.g. kuma, beszel, etc.)
  
</details>

## Installation (requires root):

```
curl -o ~/backup-restore.sh https://raw.githubusercontent.com/distillium/remnawave-backup-restore/main/backup-restore.sh && chmod +x ~/backup-restore.sh && ~/backup-restore.sh
```
## Commands:
- `rw-backup` — quick menu access from anywhere in the system
