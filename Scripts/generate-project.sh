#!/bin/zsh
# Generates Ember.xcodeproj from project.yml, filling ${BUNDLE_ID}, ${TEAM_ID} and ${ORGANIZATION}
# from .env (see .env.example). Extra arguments go to xcodegen, e.g. --quiet.
set -euo pipefail
ROOT="${0:A:h:h}"
cd "$ROOT"
source Scripts/env.zsh
xcodegen generate "$@"
