#!/bin/bash

bin/Release/PhotoFrame --flatten --width 800 --height 600 --skip "WhatsApp.*" --skip '.*Unsorted.*' --skip 'PlantNet' "$@" /Users/ajw/Pictures/Frame
