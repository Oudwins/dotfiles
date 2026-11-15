# WordPress Backups

Production WordPress backups run daily for `heike` and `tzkrasner`. Each site
has its own repository, keeps 7 daily and 6 monthly snapshots, and runs
`restic check` after each backup. Failure alerts are still TODO.

## Verification

Run and inspect a backup, replacing `heike` with `tzkrasner` as needed:

```bash
SITE=heike
sudo systemctl start "restic-backups-wordpress-${SITE}.service"
sudo systemctl status "restic-backups-wordpress-${SITE}.service"
sudo journalctl -u "restic-backups-wordpress-${SITE}.service"
sudo "restic-wordpress-${SITE}" snapshots
sudo "restic-wordpress-${SITE}" check
sudo "restic-wordpress-${SITE}" ls latest
```

## Restore Drill

Perform a non-destructive restore drill:

```bash
SITE=heike
RESTORE_DIR="/var/tmp/wordpress-${SITE}-restore"
SQL_DUMP="${RESTORE_DIR}/var/lib/wordpress-litespeed-proxy/backups/${SITE}/database.sql"

sudo rm -rf "$RESTORE_DIR"
sudo mkdir -p "$RESTORE_DIR"
sudo "restic-wordpress-${SITE}" restore latest --target "$RESTORE_DIR"
sudo test -s "$SQL_DUMP"
sudo test -f "$RESTORE_DIR"/var/lib/wordpress-litespeed-proxy/sites/*/html/wp-config.php

sudo docker run --name wordpress-restore-check -e MARIADB_ROOT_PASSWORD=restore-check -d mariadb:11.4
until sudo docker exec wordpress-restore-check mariadb-admin ping -uroot -prestore-check --silent; do sleep 2; done
sudo sh -c "docker exec -i wordpress-restore-check mariadb -uroot -prestore-check < '$SQL_DUMP'"
sudo docker exec wordpress-restore-check mariadb -uroot -prestore-check -e 'SHOW TABLES FROM hfcom;'
sudo docker rm -f wordpress-restore-check
sudo rm -rf "$RESTORE_DIR"
```

## Live Restore

```bash
SITE=heike
sudo "wordpress-${SITE}-restore" latest
```

Pass a snapshot ID instead of `latest` to restore a specific snapshot. The
command pauses that site's backup timer, restores into a temporary directory,
stops its WordPress container, replaces the complete HTML tree, imports the
database dump, and restarts WordPress and the timer. It also attempts to
restart both if the restore fails.
