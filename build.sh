#!/bin/bash

set -e

echo "Building Teumnirm..."

# Build
swift build -c release

# Create app bundle
APP_NAME="Teumnirm"
BUILD_DIR=".build/release"
APP_DIR="build/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "Creating app bundle..."

rm -rf build
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# Copy executable
cp "${BUILD_DIR}/Teumnirm" "${MACOS_DIR}/"

# Copy Info.plist
cp "Info.plist" "${CONTENTS_DIR}/"

echo "Build complete!"
echo "App bundle created at: ${APP_DIR}"
echo ""
echo "To run: open build/Teumnirm.app"
echo "Or copy to /Applications folder"
