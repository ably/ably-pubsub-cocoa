#!/bin/bash

# Generates Jazzy documentation: https://github.com/realm/jazzy

# We temporarily hide the SPM module map because Jazzy passes -fmodules to
# clang, which causes it to discover the Ably.Private module and document all
# of the SDK's internal headers. With the module map out of the way, clang only
# sees what the umbrella header (AblyPublic.h) imports.

trap 'mv Source/include/module.modulemap.jazzy-hidden Source/include/module.modulemap 2>/dev/null' EXIT
mv Source/include/module.modulemap Source/include/module.modulemap.jazzy-hidden || {
  echo "error: could not hide module map — are you running from the repo root?" >&2
  exit 1
}

bundle exec jazzy \
  --objc \
  --clean \
  --author Ably \
  --module-version 2.0.0 \
  --umbrella-header Source/include/Ably/AblyPublic.h \
  --framework-root Source \
  --module Ably \
  --sdk iphonesimulator \
  --readme Docs/Main.md \
  --output Docs/jazzy
