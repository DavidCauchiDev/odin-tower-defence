@echo off

aseprite -b ./res_workbench/art/art.ase --script ./tools/export_all_layers.lua

rem https://github.com/floooh/sokol-tools/blob/master/docs/sokol-shdc.md
call .\tools\sokol-shdc\win32\sokol-shdc.exe -i src\shader.glsl -o src\shader.odin -l hlsl5:wgsl -f sokol_odin

if %ERRORLEVEL% neq 0 (
   echo Error: sokol-shdc failed with exit code %ERRORLEVEL%
   exit /b %ERRORLEVEL%
)

call fmodstudio -build .\res_workbench\audio\noct_01\noct_01.fspro

if NOT EXIST "bin" (
    mkdir "bin"
)

if NOT EXIST "bin/res" (
    mkdir "bin/res"
)

if NOT EXIST "bin/res/fonts" (
    mkdir "bin/res/fonts"
)

if NOT EXIST "bin/res/audio" (
    mkdir "bin/res/audio"
)


odin build tools/asset_processor.odin -file -debug -use-separate-modules -o:none -out:tools/asset_processor.exe
.\tools\asset_processor

copy "res_workbench\audio\noct_01\Build\Desktop\*.bank" "bin\res\audio"
copy "res_workbench\fmod\*.dll" "bin\"
copy "res_workbench\fonts\*.ttf" "bin\res\fonts"

for /f %%i in ('git rev-parse --short HEAD') do set COMMIT_HASH=%%i
echo %COMMIT_HASH% > commit_hash.txt