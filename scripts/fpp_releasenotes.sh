#!/bin/bash

# fpp-plugin-Template release notes script
#
# Only used when pluginInfo.json declares "releaseNotesStyle": "script"
# (the template declares "gitHistory", so this is inert until you switch it;
# see PLUGININFO_FORMAT.md > Release notes). The Plugin Manager runs this
# when the user clicks Release Notes and shows whatever it prints to stdout,
# as plain text - not markdown, not HTML.
#
# Unlike fpp_install.sh and the start/stop hooks, this runs as the web user
# (fpp), NOT root, synchronously while the user waits on the dialog. So:
#  - no sudo (nothing to elevate for, and a prompt would hang the request)
#  - no downloads, builds or sleeps - read something you already have
#  - exit 0 with something printed; a non-zero exit or empty output is shown
#    as "no release notes available"
#
# FPPDIR and SRCDIR are set, same as fpp_update_check.sh. The plugin's own
# directory is wherever this script lives.

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Simplest case: ship a changelog in the repo root and print it. Replace this
# with whatever your plugin actually keeps (a version file your
# fpp_update_check.sh fetched, a notes file inside a downloaded bundle, ...).
for f in CHANGELOG.md CHANGELOG.txt CHANGELOG; do
    if [ -s "${PLUGIN_DIR}/${f}" ]; then
        cat "${PLUGIN_DIR}/${f}"
        exit 0
    fi
done

# Fallback: recent commit log of the installed clone (roughly what
# "releaseNotesStyle": "gitHistory" shows, without needing a changelog file).
if [ -d "${PLUGIN_DIR}/.git" ]; then
    git -C "${PLUGIN_DIR}" log --no-color --pretty=format:'%h  %ad  %s' --date=short -n 25
    echo
    exit 0
fi

echo "No release notes are available for this plugin."
exit 0
