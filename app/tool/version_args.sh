#!/usr/bin/env bash
# Prints --build-name/--build-number flags for `flutter build`.
#
# On a tag like v0.2.0 or v0.2.0-preview the version becomes 0.2.0.
# The build number is the GitHub Actions run number, so every build is
# higher than the last one and Android accepts it as an update.
set -euo pipefail

args=()
if [[ "${GITHUB_REF_TYPE:-}" == "tag" ]]; then
  name="${GITHUB_REF_NAME#v}"
  name="${name%%-*}"
  if [[ "$name" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    args+=("--build-name=$name")
  fi
fi
if [[ -n "${GITHUB_RUN_NUMBER:-}" ]]; then
  args+=("--build-number=$GITHUB_RUN_NUMBER")
fi
echo "${args[@]:-}"
