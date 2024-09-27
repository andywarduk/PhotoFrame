#!/bin/bash

bin/Release/PhotoFrame --flatten --width 800 --height 600 --skip "WhatsApp.*" --skip '.*Unsorted.*' $* /Users/ajw/Pictures/Frame

