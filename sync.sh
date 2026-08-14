#!/bin/bash

OUT_PATH="/Volumes/PHOTO FRAME"

if [ ! -d "$OUT_PATH" ]
then
	echo "Photo frame is not mounted"
	exit 1
fi

# The frame is FAT32, which has no concept of ownership, permissions or symlinks, so
# --archive (-rlptgoD) would fail per-file with exit status 23. Sync recursively and
# preserve mtimes only. --modify-window=1 accommodates FAT's 2 second timestamp
# granularity, which would otherwise make every file look changed on each run.
if ! rsync "$@" -rt -c --delete --modify-window=1 \
	--no-perms --no-owner --no-group \
	--exclude=.Spotlight* --exclude=.DS_Store --exclude=.fseventsd --exclude=.Trashes \
	/Users/ajw/Pictures/Frame/ "$OUT_PATH"
then
	echo "rsync failed"
	exit 1
fi

# Remove any ._ files that rsync may have created, which are useless on the frame and take up space
dot_clean -m "$OUT_PATH"
