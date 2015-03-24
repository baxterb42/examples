:: Iterate across domain active (browser) machines, calls %1 with non-UNC and UNC name
:: Requires:  NetDom.exe, DomEnumActive.cmd
:: 021206, blb
::	%1 = file with lines to pass as parameters to %2 (.cmd file to call)
::	sub-parameters should work, space delimited on same line
@echo off

if (%BATDIR%)==() set BATDIR=C:\Bat

if not (%2)==() goto ParmOK
echo Missing parameter(s)!
echo Syntax:	%0 listfile.txt DoThis.cmd	Exiting....
goto END

:ParmOK
if exist %1 goto ParmOK2
echo %0:  File '%1' does not exist!
goto END

:ParmOK2
if exist %BATDIR%\%2_0.cmd call %BATDIR%\%2_0.cmd %1 %2 %3 %4

:: Just call it once....
call today.cmd

:: Iterate, hoping to pass:  subr, PC name, UNC PC name
FOR /F "tokens=1-4* delims= " %%i in ( %1 ) do call %2 %%i %3 %4

:: Post-process, a/r
if exist %BATDIR%\%2_1.cmd call %BATDIR%\%2_1.cmd %1 %2 %3 %4

:END