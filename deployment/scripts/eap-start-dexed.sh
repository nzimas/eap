#!/bin/sh
set -eu

export HOME=/home/we
export XDG_CONFIG_HOME=/home/we/.config
export XDG_DATA_HOME=/home/we/.local/share

install -d "$XDG_CONFIG_HOME"
if [ -f /opt/electroacoustic-playground/dexed/Dexed.settings ]; then
    cp /opt/electroacoustic-playground/dexed/Dexed.settings "$XDG_CONFIG_HOME/Dexed.settings"
fi

exec xvfb-run -a /usr/local/bin/Dexed
