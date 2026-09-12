#!/usr/bin/env python3
# App Store Connect submission helper used on 2026-09-12 to move 1.1 (waiting for review) to 1.3 build 36 on
# iOS/macOS/tvOS and create visionOS 1.3: cancel → rename versions + attach build → visionOS version with copied
# localizations → texts (AppStore/store_meta.py: descriptions, keywords, promo, What's New, TV paragraph) →
# subtitles (App Info) → review submissions. Usage: python3 scripts/asc_submit.py <jwt-file> [cancel|rename|vision|texts|subtitle|submit|all]
# Version/build/submission ids are the ones of that day: update the VER/BUILD/CANCEL tables before reusing.
import json, sys, time, urllib.request, urllib.error, importlib.util
