#!/bin/sh
set -e

if [ "${CI_BRANCH-}" = "main" ] || [ "${CI_GIT_REF-}" = "refs/heads/main" ]; then
  echo "Do not build main"
  exit 1
fi

echo "Archive is the expected action"
echo "CI_XCODEBUILD_ACTION=${CI_XCODEBUILD_ACTION-}"

exit 0
