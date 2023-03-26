<?php
/*
A way for plugins to provide their own PHP API endpoints.

To use, create a file called api.php file in the plugin's directory
and provide a getEndpointsPLUGINNAME() function which returns an
array describing the endpoints the plugin implements.  Since PHP
does not allow hyphens in function names, any hyphens in the plugin
name must be removed when substituting for PLUGINNAME above and if
the plugin name is used in any callback function names.  It is
also best to use unique endpoint names as shown below to eliminate
any conflicts with stock FPP code or other plugin API callbacks.

All endpoints are prefixed with /api/plugin/PLUGIN-NAME but only
the part after PLUGIN-NAME is specified in the getEndpointsPLUGINNAME()
data.  The plugin name is used as-is in the endpoint URL, hyphens
are not removed.  -- limonade.php is used for the underlying implementation so
param("param1" ) can be used for an api like /api/plugin/fpp-BigButtons/:param1

Here is a simple example which would add a
/api/plugin/fpp-BigButtons/version endpoint to the fpp-Bigbuttons plugin.
*/


function getEndpointsfppBigButtons() {
    $result = array();

    $ep = array(
        'method' => 'GET',
        'endpoint' => 'version',
        'callback' => 'fppBigButtonsVersion');

    array_push($result, $ep);

    return $result;
}

// GET /api/plugin/fpp-BigButtons/version
function fppBigButtonsVersion() {
    $result = array();
    $result['version'] = 'fpp-BigButtons v1.2.3';

    return json($result);
}

?>