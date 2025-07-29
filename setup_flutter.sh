#!/bin/bash

# Define the Flutter version you want to use
FLUTTER_VERSION="3.32.7"
FLUTTER_SDK_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
FLUTTER_SDK_ARCHIVE="flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
FLUTTER_SDK_DIR="flutter"

# Check if the Flutter executable exists in the cache to avoid re-downloading
if [ ! -f "$FLUTTER_SDK_DIR/bin/flutter" ]; then
  echo "Flutter SDK not found. Downloading and extracting..."
  # Download the Flutter SDK
  curl -o "$FLUTTER_SDK_ARCHIVE" "$FLUTTER_SDK_URL"
  # Extract the archive
  tar xf "$FLUTTER_SDK_ARCHIVE"
  # Clean up the downloaded archive
  rm "$FLUTTER_SDK_ARCHIVE"
else
  echo "Flutter SDK already exists."
fi

# Add Flutter to the PATH for the current session
export PATH="$PWD/$FLUTTER_SDK_DIR/bin:$PATH"

# FIX: Mark the Flutter SDK directory as safe for Git
git config --global --add safe.directory "$PWD/$FLUTTER_SDK_DIR"

# Run Flutter commands
flutter config --enable-web
flutter pub get