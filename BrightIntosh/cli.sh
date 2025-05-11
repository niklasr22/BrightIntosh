#
#  cli.sh
#  BrightIntosh
#
#  Created by Niklas Rousset on 11.05.25.

#!/bin/bash

# Get the absolute path to the script (resolving symlinks)
SCRIPT_PATH="$(realpath "$0")"

# Get the parent directory of the script
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

# Go up one level to the .app/Contents directory
APP_ROOT="$(dirname "$SCRIPT_DIR")"

# Construct the path to the BrightIntosh binary inside the app bundle
BRIGHTINTOSH_EXEC="$APP_ROOT/MacOS/BrightIntosh"

# Run the executable with all the passed arguments
"$BRIGHTINTOSH_EXEC" "$@"
