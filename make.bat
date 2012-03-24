@echo off

if "%1"=="clean" goto clean

pyz80.py -I samdos2 --exportfile=shamview.sym shamview.asm
goto end

:clean
if exist shamview.dsk del shamview.dsk shamview.sym

:end
