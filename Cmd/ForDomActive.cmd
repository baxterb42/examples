:: Iterate across domain active (browser) machines, calls %1 with non-UNC and UNC name
:: Requires:  NetDom.exe, DomEnumActive.cmd
:: 011112, blb
:: 020723, blb:  Add pre- & post-processing calls
:: 020820, blb:  Add called parameters to pre & post calls
:: @echo off
if (%BATDIR%)==() set BATDIR=C:\Bat

if not (%1)==() goto ParmOK
echo %0:  command to call required!  Exiting....
goto END

:ParmOK
if exist %BATDIR%\%1_0.cmd call %BATDIR%\%1_0.cmd %1 %2 %3 %4

if exist %TEMP%\_EnumA_.txt del %TEMP%\_EnumA_.txt >nul
call DomEnumActive.cmd

:: Just call it once....
call today.cmd

:: Iterate, hoping to pass:  subr, PC name, UNC PC name
FOR /F "tokens=1-2* delims=\\ " %%i in ( %TEMP%\_EnumA_.txt ) do call %1 %%i \\%%i %2 %3 %4
::	if exist %TEMP%\_EnumA_.txt del %TEMP%\_EnumA_.txt >nul

:: Post-process, a/r
if exist %BATDIR%\%1_1.cmd call %BATDIR%\%1_1.cmd %1 %2 %3 %4

:END