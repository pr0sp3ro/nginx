# NGINX

A minimal nginx setup for local PHP applications, with private server definitions and manual deployment to `/etc/nginx`.

## Requirements

- Linux with systemd, Bash, sudo, GNU coreutils, diffutils and util-linux (`flock`).
- nginx installed with its standard configuration files in `/etc/nginx`.
- An active `nginx` systemd service.
- PHP-FPM listening on `/run/php-fpm/php-fpm.sock` for PHP applications.

Standard files such as `mime.types`, `fastcgi_params` and module definitions are supplied by the system package. The copies in this repository are not deployed.

## Private servers

Store server definitions as regular `*.conf` files directly in `servers-private/`. The entire directory is ignored by Git. Create it manually on a fresh clone:

```bash
mkdir -p servers-private
```

Each file contains a complete nginx `server` block. Use `listen 127.0.0.1:80` for local access. Add local domain names to `/etc/hosts` when needed.

For PHP servers, include `/etc/nginx/common-cfg/deny-htaccess.conf` before `/etc/nginx/common-cfg/php-setup.conf`. The first snippet blocks all hidden paths, including `.well-known`. The second uses the existing PHP-FPM socket and routes missing non-PHP paths to `index.php`.

Private configurations are not included in clones or Git backups. Keep a separate private backup. Git ignore rules do not protect files that were previously committed. Do not store credentials in these files, as installed configurations are readable by local users.

## Deploy

```bash
./deploy.sh
```

Running the script authorizes installation and reload without an additional prompt. It requests sudo privileges when necessary and works from any current directory. Deployment is never triggered automatically.

The script shows differences, creates a backup under `/var/backups/nginx/`, installs the configuration, runs `nginx -t`, and reloads the active service. If nothing changed, it exits without reloading. It does not start a stopped service.

Only these paths are managed:

- `/etc/nginx/nginx.conf`
- `/etc/nginx/common-cfg/php-setup.conf`
- `/etc/nginx/common-cfg/deny-htaccess.conf`
- `/etc/nginx/servers-private/`

The private server directory is replaced in full. Removing a local server file removes its deployed copy on the next deployment. An empty directory intentionally disables all managed servers. Other files in `/etc/nginx` are left alone.

Installation or validation failures restore the previous files. A reload failure also triggers restoration and an attempt to reload the previous configuration. Errors exit with a nonzero status and report the backup location. Deployment is not an atomic directory swap. Avoid editing system configuration or updating nginx packages during deployment.

Differences may contain private configuration details. Do not publish deployment output.

## Recovery

Backups mirror the managed paths that existed before deployment. To recover manually, restore those paths from the printed backup directory, remove managed paths that did not exist in that backup, then run:

```bash
sudo nginx -t
sudo systemctl reload nginx
```

Do not replace the whole `/etc/nginx` directory with a backup. Backups contain only managed paths. Backups are retained until you remove them manually.

## Verification

Check shell syntax without deploying:

```bash
bash -n deploy.sh
```

After deployment, check the local application in a browser, PHP requests and imports. Confirm that hidden paths are denied, missing PHP scripts return 404, and the application cannot be reached through the computer's LAN address. PHP upload limits may restrict imports below nginx's configured request limit.
