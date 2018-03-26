#Script for cleaning up IIS logs and retain 14 days.
#Schedule in Windows to run nightly

forfiles /p "C:\inetpub\logs\" /s /m *.* /c "cmd /c Del @path" /d -14