#!/bin/bash
#testing build speed
#test v2 speed test

# This script will exit immediately if any command fails.
set -e

# --- 1. SETUP PHASE ---

# Using your specified Flutter version
FLUTTER_VERSION="3.32.7"
FLUTTER_SDK_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
FLUTTER_SDK_ARCHIVE="flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
FLUTTER_SDK_DIR="flutter"

# Check if the Flutter SDK is already in the cache
if [ ! -d "$FLUTTER_SDK_DIR" ]; then
  echo "Flutter SDK not found in cache. Downloading and extracting..."
  curl -o "$FLUTTER_SDK_ARCHIVE" "$FLUTTER_SDK_URL"
  tar xf "$FLUTTER_SDK_ARCHIVE"
  rm "$FLUTTER_SDK_ARCHIVE"
else
  echo "Flutter SDK found in cache. Skipping download."
fi

# Add the Flutter SDK to the PATH
export PATH="$PWD/$FLUTTER_SDK_DIR/bin:$PATH"

# Mark the Flutter directory as safe for Git to prevent ownership errors
git config --global --add safe.directory "$PWD/$FLUTTER_SDK_DIR"

# Run basic Flutter setup commands
flutter config --enable-web
flutter pub get


# --- 2. BUILD PHASE ---

# Check the VERCEL_ENV variable to decide which build to run
if [ "$VERCEL_ENV" = "production" ]; then
  echo "Building for production..."
  # The release command is still correct
  flutter build web --release
else
  echo "Building for preview..."
  # UPDATED COMMAND: Removed the invalid --web-renderer and --no-tree-shake-icons flags.
  # A standard build command without --release is now the correct way to get a fast debug/preview build.
  flutter build web
fi

echo "Build finished successfully."