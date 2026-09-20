#!/bin/bash

scriptdir=$(realpath $(dirname -- "${BASH_SOURCE[0]}"))
/opt/Gowin/GowinIDE.app/Contents/Resources/Gowin_EDA/Programmer/bin/programmer_cli --device GW5A-25B  --operation_index 2 -f $scriptdir/*.fs --frequency 15MHz
