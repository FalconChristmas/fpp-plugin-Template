# fpp-plugin-Template
Template plugin for FPP Plugin developers

Ships with `LICENSE` defaulted to GPLv2 (the convention most FPP plugins use).
Replace it with a license of your own choosing if you'd prefer — just keep
*some* `LICENSE`/`COPYING` file in the repo root for redistribution clarity.

## Building a plugin

- [`PLUGIN_GUIDELINES.md`](PLUGIN_GUIDELINES.md) - rules and conventions for a
  well-behaved plugin. Read this (or point your AI assistant at it) before you
  start, and again whenever you add a feature.
- [`PLUGININFO_FORMAT.md`](PLUGININFO_FORMAT.md) - the `pluginInfo.json`
  metadata format reference.

**These two files document how to build a plugin in general - they aren't part
of your plugin.** Once you've forked this template, delete
`PLUGIN_GUIDELINES.md` and `PLUGININFO_FORMAT.md` from your own repo; they
should only ever live here, in fpp-plugin-Template.

## Getting your plugin listed

Once it's built, submit it via
[fpp-data](https://github.com/FalconChristmas/fpp-data) - see that repo's
`README.md` for the submission form and `PLUGINS.md` for the rules.

