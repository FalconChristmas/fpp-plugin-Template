#!/bin/bash
set -e

# fpp-plugin-Template install script

# Include common scripts functions and variables
. ${FPPDIR}/scripts/common

# Add required Apache CSP (Content-Security-Policy allowed domains
# Possible Keys are: 'default-src', 'connect-src', 'img-src', 'script-src', 'style-src', 'object-src'
# Examples:
# ${FPPDIR}/scripts/ManageApacheContentPolicy.sh add connect-src https://domaintotrust.co.uk
# ${FPPDIR}/scripts/ManageApacheContentPolicy.sh add img-src https://anotherdomain.com

# This template ships commands/descriptions.json, which fppd only reads once,
# at its own startup (PluginManager::loadUserPlugins(), src/Plugins.cpp) - not
# on every plugin install/update. Until fppd restarts, a freshly-installed (or
# changed) command type stays invisible to playlists/schedules/events even
# though the rest of the plugin (api.php, content.php) is already live. Set
# the restart flag so the Plugin Manager's "Restart Required" banner appears
# right after install instead of leaving the command silently unavailable.
# Remove this if your plugin doesn't ship commands/descriptions.json or a
# native (Makefile-built) plugin - not every plugin needs it.
setSetting restartFlag 1

