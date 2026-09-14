#!/bin/bash
set -e

# fpp-plugin-Template install script

# Include common scripts functions and variables
. ${FPPDIR}/scripts/common

# Add required Apache CSP (Content-Security-Policy allowed domains
# Possible Keys are: 'default-src', 'connect-src', 'img-src', 'script-src', 'style-src', 'object-src', 'font-src'
# (an iframe or media load is governed by 'default-src'). Every domain added here receives the
# user's browser address on each page view, so it must be a `sends` entry in pluginInfo.json's
# privacy block (PLUGIN_GUIDELINES.md 14.1)
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

