#!/bin/bash

if [ ! -d "/Volumes/PHOTO FRAME" ]
then
	echo "Photo fram is not mounted"
	exit 1
fi

rsync $* --archive -c --delete --exclude=.Spotlight* --exclude=.DS_Store /Users/ajw/Pictures/Frame/ "/Volumes/PHOTO FRAME"
	
