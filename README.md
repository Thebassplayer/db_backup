chmod +x ~/supabase_backup.sh

sudo apt update
sudo apt install -y postgresql-client

crontab -e

# run full BOTH backup at 00:00, 08:00 & 16:00 every day

0 0,8,16 \* \* \* /home/croylopez/backup_script.sh BOTH /mnt/backups >/var/log/backup.log 2>&1
