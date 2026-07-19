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

