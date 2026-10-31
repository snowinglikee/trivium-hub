@echo off
rem Compila o Trivium Hub.exe (fica na pasta acima de app). Usa o compilador C# que vem com o Windows.
cd /d "%~dp0"
"%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /codepage:65001 /target:winexe /optimize+ ^
  /win32icon:..\icon.ico /win32manifest:app.manifest ^
  /reference:"%WINDIR%\Microsoft.NET\assembly\GAC_MSIL\System.Management.Automation\v4.0_3.0.0.0__31bf3856ad364e35\System.Management.Automation.dll" ^
  /reference:System.Windows.Forms.dll ^
  /out:"..\..\Trivium Hub.exe" TriviumHub.cs
