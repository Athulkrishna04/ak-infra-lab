# Runbook: restore from backup

**Rule:** always restore into a scratch directory first, compare, and only then copy the file you need into place. Never extract an archive straight over `/`.

## 1. Pick the archive and prove it isn't corrupt

On mon01:

The directory is `0700 akbackup`, so every command needs sudo (a plain `cd` fails):

```bash
sudo ls -lt /srv/backups/web01/ | head
sudo sh -c 'cd /srv/backups/web01 && sha256sum -c web01_<STAMP>.tar.gz.sha256'   # must say OK
sudo tar -tzvf /srv/backups/web01/web01_<STAMP>.tar.gz | less                      # browse the contents
```

If web01 still has its local copy (the last 3 days are kept in `/var/backups/ak/`), use that. Otherwise copy the archive to web01:

```bash
# on mon01: stage it where akadmin can read it
sudo install -m 600 -o akadmin /srv/backups/web01/web01_<STAMP>.tar.gz* /home/akadmin/
scp /home/akadmin/web01_<STAMP>.tar.gz* web01:
```

## 2. Extract into a scratch directory (on web01)

```bash
sudo mkdir -p /root/restore && cd /root/restore
sudo tar --acls --xattrs --selinux -xzpf ~akadmin/web01_<STAMP>.tar.gz etc/nginx/conf.d/app.conf   # just what you need
sudo diff -u etc/nginx/conf.d/app.conf /etc/nginx/conf.d/app.conf
ls -lZ etc/nginx/conf.d/app.conf /etc/nginx/conf.d/app.conf     # owner, mode and SELinux label came back
```

## 3. Put it back

```bash
sudo cp -a /root/restore/etc/nginx/conf.d/app.conf /etc/nginx/conf.d/app.conf
sudo restorecon -v /etc/nginx/conf.d/app.conf       # belt and braces for the label
sudo nginx -t && sudo systemctl reload nginx
```

To restore a whole directory (for example `/srv/www`), extract `srv/www` into the scratch directory, then `sudo rsync -aAX --delete /root/restore/srv/www/ /srv/www/`. `-A` keeps ACLs and `-X` keeps xattrs, which include the SELinux label.

## 4. Verify and clean up

- The service works (`curl`, `verify.sh`).
- Remove the scratch copies: `sudo rm -rf /root/restore ~akadmin/web01_*.tar.gz*`. They contain `/etc/shadow`.
- Write down in the incident or change record which archive was used and how long the restore took. That's your measured RTO.
