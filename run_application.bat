@echo off
setlocal
set "ROOT=%~dp0"
set "BACKEND=%ROOT%backend"
set "FLUTTER_APP=%ROOT%flutter_app"
set "PYTHON=%BACKEND%\.venv312\Scripts\python.exe"

if not exist "%PYTHON%" (
    echo Backend Python was not found: "%PYTHON%"
    pause
    exit /b 1
)
if not exist "%FLUTTER_APP%\pubspec.yaml" (
    echo Flutter project was not found: "%FLUTTER_APP%"
    pause
    exit /b 1
)
where flutter.bat >nul 2>&1
if errorlevel 1 (
    if exist "D:\flutter\bin\flutter.bat" (
        set "PATH=D:\flutter\bin;%PATH%"
    ) else (
        echo Flutter was not found on PATH or at D:\flutter\bin\flutter.bat
        pause
        exit /b 1
    )
)

start "AlignFlow Backend" /D "%BACKEND%" cmd /k ""%PYTHON%" -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload"
start "AlignFlow Flutter Web" /D "%FLUTTER_APP%" cmd /k "flutter run -d chrome --web-port 8080"

echo Started backend and Flutter web in separate windows.
echo Backend health: http://127.0.0.1:8000/health
echo For your phone, enter this PC's Wi-Fi IPv4 address followed by :8000.
echo Flutter web:    http://localhost:8080
endlocal
