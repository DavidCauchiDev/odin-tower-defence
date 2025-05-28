#!/bin/bash

/Applications/Aseprite.app/Contents/MacOS/aseprite -b ./res_workbench/art/art.ase --script ./tools/export_all_layers.lua

# https://github.com/floooh/sokol-tools/blob/master/docs/sokol-shdc.md
./tools/sokol-shdc/osx_arm64/sokol-shdc -i src/shader.glsl -o src/shader.odin -l metal_macos:wgsl -f sokol_odin

if [ $? -ne 0 ]; then
   echo "Error: sokol-shdc failed with exit code $?"
   exit $?
fi

'/Applications/FMOD Studio.app/Contents/MacOS/fmodstudio' -build ./res_workbench/audio/noct_01/noct_01.fspro

mkdir -p bin/res/fonts bin/res/audio

/Users/davey/Tools/Odin/odin build tools/asset_processor.odin -file -debug -use-separate-modules -o:none -out:tools/asset_processor
./tools/asset_processor

cp res_workbench/audio/noct_01/Build/Desktop/*.bank bin/res/audio/
cp res_workbench/fmod/*.dylib bin/
cp res_workbench/fonts/*.ttf bin/res/fonts/

COMMIT_HASH=$(git rev-parse --short HEAD)
echo $COMMIT_HASH > commit_hash.txt

/Users/davey/Tools/Odin/odin build src -debug -o:none -out:bin/game -use-separate-modules -define:PROFILE_ENABLE=true -vet