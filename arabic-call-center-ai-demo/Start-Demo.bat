@echo off
setlocal
cd /d "%~dp0"
title Arabic Call Center AI Demo

rem ================================================================
rem  1) Paste your ElevenLabs API key between = and the closing quote
rem     (ElevenLabs > Developers > API Keys). You can also leave it and
rem     paste it in the window when asked (saved to elevenlabs-key.txt). The key needs the
rem     "Speech to Text" permission, plus "Text to Speech" for Training.
rem ================================================================
set "ELEVENLABS_API_KEY=PASTE_YOUR_ELEVENLABS_KEY_HERE"

rem ================================================================
rem  2) FREE AI answers for ANY call: Google Gemini API key
rem     Free, no credit card: https://aistudio.google.com/apikey
rem     Paste it here, or leave empty and paste it in the window
rem     when asked (it is then saved to gemini-key.txt).
rem ================================================================
set "GEMINI_API_KEY="
rem Optional: force a Gemini model, e.g. gemini-2.5-flash (empty = automatic)
set "GEMINI_MODEL="

rem Paid alternative (not needed): Anthropic Claude key
set "ANTHROPIC_API_KEY="
rem Optional: force a Claude model id (empty = newest Sonnet your key can use)
set "ANTHROPIC_MODEL="

rem ---- Optional settings (leave as they are if unsure) ----
rem Speech-to-text model: scribe_v2 (falls back to scribe_v1 automatically)
set "ELEVENLABS_STT_MODEL=scribe_v2"
rem Force the language, e.g. ar  (empty = auto-detect Arabic/English)
set "ELEVENLABS_STT_LANGUAGE="
rem Number of speakers in the calls, e.g. 2 (empty = auto)
set "ELEVENLABS_NUM_SPEAKERS=2"
rem Voice used by the Training simulator
set "ELEVENLABS_VOICE_ID=21m00Tcm4TlvDq8ikWAM"
rem Company proxy, only if IT requires one, e.g. http://proxy.company.local:8080
rem set "HTTPS_PROXY="
rem Set to 1 if you get TLS / certificate revocation errors on the company network
set "DEMO_SSL_NO_REVOKE=0"
rem Local port for the demo page
set "PORT=8000"

if not exist "%~dp0server.ps1" (
  echo server.ps1 was not found next to this file.
  pause
  exit /b 1
)
if not exist "%~dp0index.html" (
  echo index.html was not found next to this file.
  pause
  exit /b 1
)

echo Starting the assistant AI Demo on http://localhost:%PORT%/ ...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1" -Port %PORT% -OpenBrowser
echo.
echo The demo server has stopped. Read any red message above.
pause
