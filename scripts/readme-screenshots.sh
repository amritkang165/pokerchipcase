#!/bin/sh
# Takes the README screenshots in docs/images with debug bots on a simulator.
# Usage: scripts/readme-screenshots.sh ["simulator name"]   (default: iPhone 17)
# Run from the repo root after the app build in AGENTS.md (it installs .build/app).
# Needs ffmpeg (brew install ffmpeg) to scale and posterize the shots.
set -eu

SIM=${1:-iPhone 17}
APP_ID=io.github.mauwii.pokerchipcase
OUT=docs/images
RAW=$(mktemp -d)
trap 'rm -rf "$RAW"' EXIT

xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl install "$SIM" .build/app/Build/Products/Debug-iphonesimulator/PokerChipCase.app
xcrun simctl status_bar "$SIM" override --time 9:41 --batteryState charged --batteryLevel 100 \
    --wifiBars 3 --cellularMode notSupported

# shot <file> <-debugStop> <-theme> <-appearance> <-digitalCards> <seconds until the scene is reached>
shot() {
    name=$1
    file=$OUT/$name.png
    stop=$2
    theme=$3
    appearance=$4
    digital=$5
    seconds=$6
    xcrun simctl terminate "$SIM" "$APP_ID" 2>/dev/null || true
    xcrun simctl launch "$SIM" "$APP_ID" -debugTable -playerName Alex -debugStop "$stop" -theme "$theme" \
        -appearance "$appearance" -digitalCards "$digital" >/dev/null
    sleep "$seconds"
    xcrun simctl io "$SIM" screenshot "$RAW/$name.png" >/dev/null 2>&1
    # 600 points wide, 6 bits per channel: keeps each file under 500 KB. 256-color quantizing
    # banded the gradients and turned Neon's blue chip grey; posterizing does neither.
    ffmpeg -loglevel error -y -i "$RAW/$name.png" -vf "scale=600:-1:flags=lanczos,format=rgb24,lutrgb=r='bitand(val,252)':g='bitand(val,252)':b='bitand(val,252)'" "$file"
    echo "$file"
}

shot lobby lobby felt light NO 12
shot table turn felt light NO 25
shot showdown showdown felt light NO 75
shot payout payout felt light NO 80
shot cards payout felt light YES 80
shot neon turn neon dark YES 25
