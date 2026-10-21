#!/bin/bash
# Records the README's demo: runs the scripted performance in ScaleCheck/Demo.swift
# on the booted simulator and turns the screen recording into docs/demo.gif.
# Run: tools/record-demo.sh   (needs a booted iPhone simulator and ffmpeg)
set -euo pipefail
cd "$(dirname "$0")/.."

ID=net.killingar.ScaleCheck
WORK=build-tmp/demo
mkdir -p "$WORK" docs

xcodebuild -project ScaleCheck.xcodeproj -scheme ScaleCheck -configuration Debug \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath "$WORK/dd" -quiet build
xcrun simctl install booted "$WORK/dd/Build/Products/Debug-iphonesimulator/ScaleCheck.app"
xcrun simctl terminate booted "$ID" 2>/dev/null || true

# Light mode and a tidy status bar. The demo picks its own starting scale.
xcrun simctl ui booted appearance light
xcrun simctl status_bar booted override --time 9:41 --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4

xcrun simctl io booted recordVideo --codec h264 --force "$WORK/demo.mov" &
recorder=$!
sleep 2
# Blocks until the demo quits the app.
xcrun simctl launch --console booted "$ID" -demo >/dev/null
kill -INT "$recorder"
wait "$recorder" || true
xcrun simctl status_bar booted clear

# Skip the recorder's start and the app launch, stop before the app quits to
# the home screen, and make a palette-optimized GIF.
duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$WORK/demo.mov")
ffmpeg -loglevel error -y -ss 2.5 -to "$(echo "$duration - 1" | bc)" -i "$WORK/demo.mov" \
    -vf "fps=15,scale=320:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=64[p];[b][p]paletteuse=dither=none" \
    docs/demo.gif
echo "Wrote docs/demo.gif ($(du -h docs/demo.gif | cut -f1))"
