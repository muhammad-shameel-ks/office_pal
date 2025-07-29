#!/bin/bash

# Clone flutter SDK if it doesn't exist
if [ ! -d "flutter" ]; then
  git clone https://github.com/flutter/flutter.git
fi

# Add Flutter to PATH
export PATH="$PWD/flutter/bin:$PATH"

# Run Flutter setup
flutter doctor
flutter config --enable-web
flutter pub get
flutter clean
