#!/bin/bash

# Define time window
START_HOUR=03
END_HOUR=08

# Server
SERVER=
USER=

# Paths
PATH1=
DESTINATION1=

PATH2=
DESTINATION2=

# Rsync options
RSYNC_OPTIONS="-av"

is_within_time_window() {
    CURRENT_HOUR=$(date +%H)
    if [ "$START_HOUR" -le "$END_HOUR" ]; then
        [ "$CURRENT_HOUR" -ge "$START_HOUR" ] && [ "$CURRENT_HOUR" -lt "$END_HOUR" ]
    else
        [ "$CURRENT_HOUR" -ge "$START_HOUR" ] || [ "$CURRENT_HOUR" -lt "$END_HOUR" ]
    fi
}

sync_folder() {
    local SOURCE_PATH=$1
    local DEST_PATH=$2
    rsync $RSYNC_OPTIONS "$USER@$SERVER:$SOURCE_PATH" "$DEST_PATH"
    echo "Synchronization of $SOURCE_PATH to $DEST_PATH completed."
}

while true
do
    if is_within_time_window; then
        echo "It is within the defined time window (${START_HOUR}h - ${END_HOUR}h), starting rsync..."
        sync_folder "$PATH1" "$DESTINATION1"
        sync_folder "$PATH2" "$DESTINATION2"
        sleep 3600
    else
        echo "Outside the defined time window. Waiting..."
        sleep 3600
    fi
done
