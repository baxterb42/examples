:: Use  netdom member to enumerate domain member list machines (in dom db)
:: Leave behind _EnumM_ file
:: Requires:  NetDom.exe
:: 011112, blb
@echo off
echo Enumerating machines in domain db....

:: List machines in db, only keep lines with UNC \\ (& trash extra)
netdom member |grep \\ |grep Member > %TEMP%\_EnumT_.txt

:: Parse down to UNC machine names
FOR /F "tokens=1-4* delims= " %%i in ( %TEMP%\_EnumT_.txt ) do echo %%l >> %TEMP%\_EnumM_.txt

:: Clean up
if exist %TEMP%\_EnumT_.txt del %TEMP%\_EnumT_.txt > nul
