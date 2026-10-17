#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
    -h|--help)
        echo "Usage: $0 [-h|--help]"
        echo "Install local nginx configuration, validate it, and reload active nginx."
        exit 0
        ;;
    '') ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
esac

if (( $# > 1 )); then
    echo "Too many arguments" >&2
    exit 1
fi

source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

if (( EUID != 0 )); then
    exec sudo -- bash "$source_dir/deploy.sh"
fi

exec 9>/run/lock/nginx-config-deploy.lock
flock -n 9 || { echo "Another deployment is running" >&2; exit 1; }

systemctl is-active --quiet nginx || {
    echo "nginx must already be running" >&2
    exit 1
}

[[ -d "$source_dir/servers-private" ]] || {
    echo "Create servers-private/ and add your private server configurations first" >&2
    exit 1
}

stage=$(mktemp -d /tmp/nginx-deploy.XXXXXXXX)
backup=''
modified=0
reload_attempted=0
paths=(nginx.conf common-cfg/php-setup.conf common-cfg/deny-htaccess.conf servers-private)

finish() {
    result=$?
    trap - EXIT INT TERM
    if (( modified )); then
        echo "Restoring configuration from $backup" >&2
        restore_failed=0
        for path in "${paths[@]}"; do
            rm -rf -- "/etc/nginx/$path" || restore_failed=1
            if [[ -e "$backup/$path" ]]; then
                cp -a -- "$backup/$path" "/etc/nginx/$path" || restore_failed=1
            fi
        done
        if (( reload_attempted )); then
            if ! nginx -t || ! systemctl reload nginx; then
                restore_failed=1
            fi
        fi
        if (( restore_failed )); then
            echo "Recovery incomplete. Restore manually from $backup" >&2
        fi
        result=1
    fi
    rm -rf -- "$stage"
    exit "$result"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

install -d "$stage/common-cfg" "$stage/servers-private"
for path in nginx.conf common-cfg/php-setup.conf common-cfg/deny-htaccess.conf; do
    [[ -f "$source_dir/$path" && ! -L "$source_dir/$path" ]] || {
        echo "Expected a regular source file: $path" >&2
        exit 1
    }
    install -m 0644 -- "$source_dir/$path" "$stage/$path"
done

shopt -s nullglob dotglob
for file in "$source_dir/servers-private/"*; do
    [[ -f "$file" && ! -L "$file" && "$file" == *.conf ]] || {
        echo "servers-private/ may contain only regular .conf files" >&2
        exit 1
    }
    install -m 0644 -- "$file" "$stage/servers-private/"
done

changed=0
for path in "${paths[@]}"; do
    if [[ -L "/etc/nginx/$path" ]]; then
        echo "Refusing to replace symlink: /etc/nginx/$path" >&2
        exit 1
    fi
    if [[ ! -e "/etc/nginx/$path" ]]; then
        echo "Adding /etc/nginx/$path"
        changed=1
    elif diff -ru -- "/etc/nginx/$path" "$stage/$path"; then
        :
    else
        status=$?
        (( status == 1 )) || exit "$status"
        changed=1
    fi
done

if (( !changed )); then
    echo "Configuration is unchanged"
    exit 0
fi

# Refuse an already broken installation before replacing any files.
nginx -t
install -d -m 0700 /var/backups/nginx
backup=$(mktemp -d /var/backups/nginx/"$(date +%Y%m%d-%H%M%S)".XXXXXXXX)
mkdir -p "$backup/common-cfg"
for path in "${paths[@]}"; do
    if [[ -e "/etc/nginx/$path" ]]; then
        cp -a -- "/etc/nginx/$path" "$backup/$path"
    fi
done

echo "Backup: $backup"
modified=1
install -d -m 0755 /etc/nginx/common-cfg
for path in nginx.conf common-cfg/php-setup.conf common-cfg/deny-htaccess.conf; do
    install -o root -g root -m 0644 -- "$stage/$path" "/etc/nginx/$path"
done
# This dedicated directory is managed entirely by this repository.
rm -rf -- /etc/nginx/servers-private
install -d -m 0755 /etc/nginx/servers-private
for file in "$stage/servers-private/"*.conf; do
    install -o root -g root -m 0644 -- "$file" /etc/nginx/servers-private/
done

nginx -t
reload_attempted=1
systemctl reload nginx
modified=0
echo "Configuration installed and nginx reloaded"
