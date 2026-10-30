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


# From FPP 10.4, Reinstall (and Reinstall All) runs this with
# FPP_PLUGIN_REINSTALL=1 before installing again; every other uninstall has 0,
# and FPP 10.3 and earlier set nothing.
# State to keep across a Reinstall lives outside the plugin directory
# (PLUGIN_GUIDELINES.md 2.12):
# if [ "${FPP_PLUGIN_REINSTALL:-0}" != "1" ]; then
#     rm -rf "${MEDIADIR}/plugindata/fpp-plugin-Template"
#     rm -f "${MEDIADIR}/config/plugin.fpp-plugin-Template"
# fi
