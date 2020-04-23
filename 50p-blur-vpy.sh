#!/bin/bash
scripts="${HOME}/Desktop/Sal/BATCHES/bash-tool-scripts/vpy"

# it's likely i'll have to include some kind of check in here to ensure the generated file actually returns video...

echo $1
cat $scripts/vs-template-50p-blur-QT.vpy | sed -e "s@SOURCE@$1@g" > "${1%.*}.vpy"
