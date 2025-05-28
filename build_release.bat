@echo off

if EXIST "bin" (
    rmdir /s /q "bin"
    mkdir "bin"
)

call .\build.bat

odin build ./src -o:speed -out:bin/game.exe -subsystem:windows