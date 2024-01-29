#!/bin/bash

set -e

# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
file_env() {
        local var="$1"
        local fileVar="${var}_FILE"
        local def="${2:-}"
        if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
                echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
                exit 1
        fi
        local val="$def"
        if [ "${!var:-}" ]; then
                val="${!var}"
        elif [ "${!fileVar:-}" ]; then
                val="$(< "${!fileVar}")"
        fi
        export "$var"="$val"
        unset "$fileVar"
}

# Get PASSWORD from PASSWORD_FILE if available
file_env 'PASSWORD'

# Get USERNAME from USERNAME_FILE if availabile
file_env 'USERNAME'

# Select user to run the process
user="root"
if [ "$USER_ID" ] && [ "$USER_ID" != "1" ]; then
        usermod --uid $USER_ID automysqlbackup > /dev/null
        groupmod --gid $USER_ID automysqlbackup

        # make sure we can write to stdout and stderr as user
        chown --dereference automysqlbackup "/proc/$$/fd/1" "/proc/$$/fd/2" || :
        # ignore errors thanks to https://github.com/docker-library/mongo/issues/149

        user="automysqlbackup"
fi

# Select group to run the process
group="$user"
if [ "$GROUP_ID" ]; then
        if [ "$GROUP_ID" == "1" ]; then
                group="root"
        else
                groupmod -g $GROUP_ID automysqlbackup
                group="automysqlbackup"
        fi
fi

## START Configure WebDAV ##

# Get WEBDAV_PASS from WEBDAV_PASS_FILE if available
file_env 'WEBDAV_PASS'

# Set variables
WEBDAV_MOUNT_POINT="/mnt/koofr"
DAVFS_SECRET_FILE="/etc/davfs2/secrets"
WEBDAV_MOUNT_URL="https://app.koofr.net:443/dav/Koofr/"
# davs://app.koofr.net:443/dav/Koofr

# Create mount point
mkdir -p "${WEBDAV_MOUNT_POINT}"
chmod 700 "${WEBDAV_MOUNT_POINT}"

# Fill in credentials
if [ "${WEBDAV_PASS}" ]; then
    echo "${WEBDAV_MOUNT_POINT} ${WEBDAV_USER} ${WEBDAV_PASS}" >> "$DAVFS_SECRET_FILE";
    chmod 600 "${DAVFS_SECRET_FILE}"
else  
    echo "No WebDAV password provided, please set WEBDAV_PASS or WEBDEV_PASS_FILE environment variable"
    exit 1
fi

BACKUP_LOCATION="${WEBDAV_MOUNT_POINT}/backups/antiftw/db/"

# Check if backup location directory exists, if not, create it
if [ ! -d "$BACKUP_LOCATION" ]; then
    mkdir -p "$BACKUP_LOCATION";
fi

# Mount WebDAV share
echo "$WEBDAV_MOUNT_URL $WEBDAV_MOUNT_POINT davfs defaults,uid=root,_netdev,auto 0 0" >> /etc/fstab
mount -a

## END Configure WebDAV ##

# Configure cronjob if set, or execute backup
if [ "${CRON_SCHEDULE}" ]; then
    exec gosu $user:$group go-cron -s "0 ${CRON_SCHEDULE}" -- automysqlbackup
else
    exec gosu $user:$group bash /usr/local/bin/automysqlbackup
fi
