:: Use RK browstat vw %NetTransp% to enumerate active machines (in net neighb)
:: Leave behind _EnumA_ file
:: 011112, blb
@echo off
echo Enumerating machines active in browser....
if NOT defined NetTransp call SetNetTransp.cmd

:: List machines active in browser, only keep lines with UNC \\ (& trash extra)
%NTRESKIT%\browstat vw %NetTransp% |grep \\ |grep -v NetServerEnum > %TEMP%\_EnumT_.txt

:: Parse down to UNC machine names
FOR /F "tokens=1,2* delims= " %%i in ( %TEMP%\_EnumT_.txt ) do echo %%i >> %TEMP%\_EnumA_.txt

:: Clean up
if exist %TEMP%\_EnumT_.txt del %TEMP%\_EnumT_.txt > nul
