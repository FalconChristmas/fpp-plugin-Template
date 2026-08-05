#!/bin/bash

# fpp-plugin-Template uninstall script

# This template ships commands/descriptions.json. scripts/uninstall_plugin
# runs this script and THEN unconditionally deletes the plugin directory -
# this is the only code that runs before the files are gone. Without
# requesting a restart here, the removed command type lingers as a ghost in
# fppd's in-memory list (still selectable in playlists/schedules/events)
# until fppd restarts for some unrelated reason - fppd only re-reads
# commands/descriptions.json at its own startup (PluginManager::
# loadUserPlugins(), src/Plugins.cpp), never on uninstall. Remove this if
# your plugin doesn't ship commands/descriptions.json or a native
# (Makefile-built) plugin - not every plugin needs it.
. ${FPPDIR}/scripts/common
setSetting restartFlag 1

