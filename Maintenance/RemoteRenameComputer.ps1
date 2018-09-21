$oldname= read-host "computername to change"
$newname= read-host "new computer name"
Rename-Computer -ComputerName "$oldname" -NewName "$newname" -PassThru -DomainCredential domain\admin -Force

## This part sends the reboot to the computer which is needed to complete the rename but gives the user 5 minutes to finish and save their work. 
##There will be a popup on their screen alerting them of the pending reboot

shutdown /r /m \\$oldname /t 300 /f
## The pause is to see if there are any error messages
pause
