#!/bin/sh
set -eu

export HOME=/home/we
export XDG_CONFIG_HOME=/home/we/.config
export XDG_DATA_HOME=/home/we/.local/share

if [ "${EAP_ENABLE_DEXED:-0}" != "1" ]; then
    echo "Dexed external engine disabled; set EAP_ENABLE_DEXED=1 to launch it."
    exit 0
fi

install -d "$XDG_CONFIG_HOME"
if [ -f /opt/electroacoustic-playground/dexed/Dexed.settings ]; then
    cp /opt/electroacoustic-playground/dexed/Dexed.settings "$XDG_CONFIG_HOME/Dexed.settings"
fi

exec xvfb-run -a /usr/local/bin/Dexed
