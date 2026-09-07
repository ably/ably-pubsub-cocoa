#!/bin/bash
set -e

source "$(dirname "$0")/version-constants.sh"

if [[ $(git diff --stat) != '' ]]; then
  echo "ERROR: Your Git working directory is dirty."
  echo "This script creates a commit and a tag, so it needs a clean starting point."
  exit 1
fi

prefix="$VERSION_CONFIG_VAR = "
version_config=$(cat $VERSION_CONFIG_FILE)
OLD_VERSION=${version_config:${#prefix}}
NEW_VERSION="$1"

if [[ -z "NEW_VERSION" ]]; then
  echo "ERROR: You must specify a version."
  exit 1
fi

echo "New version: $NEW_VERSION"
echo "Old version: $OLD_VERSION"

# Assign new version
echo "$VERSION_CONFIG_VAR = $NEW_VERSION" > $VERSION_CONFIG_FILE
git add Version.xcconfig

other_files=(
  "README.md"
  "Scripts/jazzy.sh"
  "Source/ARTClientInformation.m"
  "Test/AblyTests/Tests/ARTDefaultTests.swift"
  "Test/AblyTests/Tests/ClientInformationTests.swift"
  "Test/AblyTests/Tests/PubSubDeviceTests.swift"
  "Test/AblyTests/Tests/RealtimeClientConnectionTests.swift"
  "Test/AblyTests/Tests/RestClientTests.swift"
  "Test/AblyTests/Tests/WrapperSDKProxyTests.swift"
)

for file in ${other_files[@]};
do
  sed -i '' -e 's/'"$OLD_VERSION"'/'"$NEW_VERSION"'/g' "${file}"
  git add "${file}"
done

git commit -m "Bump version to $NEW_VERSION."
