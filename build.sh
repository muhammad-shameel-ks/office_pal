#!/bin/bash

# This script will exit immediately if any command fails.
set -e

# --- 1. SETUP PHASE ---

FLUTTER_VERSION="3.22.7"
FLUTTER_SDK_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
FLUTTER_SDK_ARCHIVE="flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"

# THE FIX: Use a directory name that is NOT in .gitignore
FLUTTER_SDK_DIR="flutter_sdk"

# Check if the renamed Flutter SDK directory is already in the cache
if [ ! -d "$FLUTTER_SDK_DIR" ]; then
  echo "Flutter SDK not found in cache. Downloading and extracting..."
  curl -o "$FLUTTER_SDK_ARCHIVE" "$FLUTTER_SDK_URL"
  # Extract to a temporary name and then rename it to our desired directory name
  tar xf "$FLUTTER_SDK_ARCHIVE"
  mv flutter "$FLUTTER_SDK_DIR" # The extracted folder is named "flutter" by default
  rm "$FLUTTER_SDK_ARCHIVE"
else
  echo "Flutter SDK found in cache. Skipping download."
fi

# Add the renamed Flutter SDK directory to the PATH
export PATH="$PWD/$FLUTTER_SDK_DIR/bin:$PATH"

# Mark the renamed directory as safe for Git
git config --global --add safe.directory "$PWD/$FLUTTER_SDK_DIR"

# Run basic Flutter setup commands
flutter config --enable-web
flutter pub get


# --- 2. BUILD PHASE ---

if [ "$VERCEL_ENV" = "production" ]; then
  echo "Building for production..."
  flutter build web --release
else
  echo "Building for preview..."
  flutter build web
fi

echo "Build finished successfully."