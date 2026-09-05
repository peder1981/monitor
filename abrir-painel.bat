@echo off
rem abrir-painel.bat -- garante que MonitorTUI.exe roda dentro de um
rem console de verdade (stdin TTY). Aberto direto por duplo-clique no
rem Explorer, o AdvPP acha que deve abrir uma janela Fyne em vez do
rem console -- este .bat evita isso.
cd /d "%~dp0"
MonitorTUI.exe
pause
