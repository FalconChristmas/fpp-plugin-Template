<?php

# $menuEntries is an array of menu entries for this plugin
# text - menu entry text
# type - status/content/output/help (main menu area)
# page - PHP file to display for this menu item
# wrap - 0/1 to hide or display the FPP header, menu, and footer on this page.
#        This does not apply for pages which begin with http:// or https://

# PLUGIN_GUIDELINES.md #9.1: at most ONE entry per type (status/content/output/
# help) - a plugin may appear under multiple areas, just never twice within the
# same one. If you have several things a user might want under one area (a help
# page, a home-page link, a credits page, ...), put them all on one page instead
# of adding an entry per page - see about.php, which folds help text, the repo
# link, and credits into a single page for the one 'help' entry below.
#
# Comment out sub arrays to not display an item under a menu; uncomment at most
# one of 'content'/'output' if your plugin needs one of those areas too.

$menuEntries = Array(
	Array(
		'text' => 'Template - Status',
		'type' => 'status',
		'page' => 'status.php',
		'wrap' => 1
	),
#	Array(
#		'text' => 'Template - Content Setup',
#		'type' => 'content',
#		'page' => 'content.php',
#		'wrap' => 1
#	),
#	Array(
#		'text' => 'Template - Output',
#		'type' => 'output',
#		'page' => 'output.php',
#		'wrap' => 1
#	),
	Array(
		'text' => 'Template - Help',
		'type' => 'help',
		'page' => 'about.php',
		'wrap' => 1
	)
);

##############################################################################
# Display the menu entries for this plugin.
#
# It is expected that two variables are already set:
# $plugin - contains the name of the current plugin directory/repoName
# $menu - contains the name of the menu section/type
foreach ($menuEntries as $entry)
{
	if ($entry['type'] != $menu)
		continue;

	if (preg_match('/^http.?:\/\//', $entry['page']))
	{
		printf("<li><a href='%s' target='_blank'>%s</a></li>\n",
			$entry['page'], $entry['text']);
	}
	else
	{
		$nopage = '';
		if (isset($entry['wrap']) && ($entry['wrap'] == 0))
			$nopage = '&nopage=1';

		printf("<li><a href='plugin.php?plugin=%s&page=%s%s'>%s</a></li>\n",
			$plugin, $entry['page'], $nopage, $entry['text']);
	}
}
?>
