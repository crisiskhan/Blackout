#!/bin/sh
set -e

echo "CI_BRANCH=${CI_BRANCH-}"
echo "CI_GIT_REF=${CI_GIT_REF-}"
echo "CI_XCODE_PROJECT=${CI_XCODE_PROJECT-}"
echo "CI_XCODE_SCHEME=${CI_XCODE_SCHEME-}"

if [ "${CI_BRANCH-}" = "main" ] || [ "${CI_GIT_REF-}" = "refs/heads/main" ]; then
  echo "Do not build main"
  exit 1
fi

exit 0
