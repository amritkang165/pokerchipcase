#!/bin/sh
# Takes the README screenshots in docs/images with debug bots on a simulator.
# Usage: scripts/readme-screenshots.sh ["simulator name"]   (default: iPhone 17)
# Run from the repo root after the app build in AGENTS.md (it installs .build/app).
set -eu

SIM=${1:-iPhone 17}
APP_ID=io.github.mauwii.pokerchipcase
OUT=docs/images

xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl install "$SIM" .build/app/Build/Products/Debug-iphonesimulator/PokerChipCase.app
xcrun simctl status_bar "$SIM" override --time 9:41 --batteryState charged --batteryLevel 100 \
    --wifiBars 3 --cellularMode notSupported

# shot <file> <-debugStop> <-appearance> <seconds until the scene is reached>
shot() {
    xcrun simctl terminate "$SIM" "$APP_ID" 2>/dev/null || true
    xcrun simctl launch "$SIM" "$APP_ID" -debugTable -playerName Alex -debugStop "$2" -appearance "$3" >/dev/null
    sleep "$4"
    xcrun simctl io "$SIM" screenshot "$OUT/$1.png" >/dev/null 2>&1
    sips --resampleWidth 600 "$OUT/$1.png" >/dev/null
    echo "$OUT/$1.png"
}

shot lobby lobby felt 12
shot table turn felt 25
shot showdown showdown felt 75
shot payout payout felt 80
shot dark turn dark 25
