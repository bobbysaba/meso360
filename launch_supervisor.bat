@echo off
set ENV_NAME=meso360
set SCRIPT=%~dp0supervisor.py

:: Search common conda install locations
for %%p in (
    "%USERPROFILE%\miniforge3"
    "%USERPROFILE%\Anaconda3"
    "%USERPROFILE%\miniconda3"
    "%USERPROFILE%\anaconda3"
    "%LOCALAPPDATA%\miniforge3"
    "%LOCALAPPDATA%\miniconda3"
) do (
    if exist "%%~p\Scripts\activate.bat" (
        set CONDA_ROOT=%%~p
        goto found
    )
)

echo ERROR: Could not find a conda installation in common locations.
echo Please edit this script and set CONDA_ROOT manually.
pause
exit /b 1

:found
call "%CONDA_ROOT%\Scripts\activate.bat" %ENV_NAME%
python "%SCRIPT%"
pause
