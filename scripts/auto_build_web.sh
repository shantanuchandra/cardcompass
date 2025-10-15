#!/bin/bash
# This script sets BUILD_DATE to the current date/time and builds the Flutter web app with the correct version format.
# Usage: ./auto_build_web.sh

BUILD_DATE=$(date '+%Y-%m-%d %H:%M')
echo "Building with BUILD_DATE=$BUILD_DATE"
flutter build web --dart-define=BUILD_DATE="$BUILD_DATE"
