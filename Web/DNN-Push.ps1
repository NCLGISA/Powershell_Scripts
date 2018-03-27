$SrcWebSitePath = "\\testserver\c$\.....\wwwroot2"
$DstWebSitePath = "\\prodserver\c$\.....\wwwroot"
$SqlInstance = "DOTNETNUKE"
#DNN user for the web.config file
$LocalDBUser = "sqluser"
$LocalDBPass = "password"
# Production SQL Admin Account to perform the restore with sense this machine is on DMZ and Trusted Auth will not work
$ProdDBUser = "sqlproduser"
$ProdDBPass = "sqlprodpass"
$ProdDBName = "DNN"
$StageDBServer = "TESTSERVER"
$ProdDBServer = "PRODSERVER"
$StageDBName = "DNN-Test"
#Path that is local to the SQL DB
$TmpBAKPath = "C:\TEMP"

# Clear screen
cls 

[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | out-null
$SrcDBServer = New-Object ("Microsoft.SqlServer.Management.Smo.Server") ($StageDBServer + "\" + $SqlInstance)
$DBBakFile = $TmpBAKPath + "\" + $StageDBName + ".bak"
write-host "Backup Staging DB $StageDBName to $DBBakFile..."
[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SmoExtended') | out-null
$dbBackup = new-object ("Microsoft.SqlServer.Management.Smo.Backup")
$dbBackup.Database = $StageDBName
$dbBackup.Devices.AddDevice($DBBakFile, "File")
$dbBackup.Action = "Database"
$dbBackup.SqlBackup($SrcDBServer)

$SrcTMPPath = "\\" + $StageDBServer + $TmpBAKPath.Replace("C:", "\c$")
$DstTMPPath = "\\" + $ProdDBServer + $TmpBAKPath.Replace("C:", "\c$")

#Copy Bak to destination DB server. Could use common storage but this is for a DMZ server.
Write-Host "Copying DB Backup from $SrcTMPPath to $DstTMPPath"
xcopy $SrcTMPPath $DstTMPPath /E /D /C /Y

#Restore the database
#load assembly
[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMO") | Out-Null
$DstDBServer = New-Object ("Microsoft.SqlServer.Management.Smo.Server") ($ProdDBServer + "\" + $SqlInstance)

#This sets the connection to mixed-mode authentication 
$DstDBServer.ConnectionContext.LoginSecure=$false; 
#This sets the login name 
$DstDBServer.ConnectionContext.set_Login($ProdDBUser); 
#This sets the password 
$DstDBServer.ConnectionContext.set_Password($ProdDBPass)  

 
Write-Host "Restoring $StageDBName Database from $DBBakFile as $ProdDBName..."
$db = $DstDBServer.Databases[$ProdDBName]
$DBMasterPath = $db.PrimaryFilePath + "\"
Write-Host "DB File Path $DBMasterPath"
 
# DB Filename + Logfilename shortening (RESTORE DATABASE MOVE syntax ...)
$moveDB = $ProdDBName
if ($moveDB.Length -gt 16)
{
   $moveDB = $moveDB.Substring(0,16)
}
$moveDBLog = ($ProdDBName + "_log")
if ($moveDBLog.Length -gt 20)
{
   $moveDBLog = $moveDBLog.Substring(0,20)
}


 
# Open ADO.NET Connection with Windows authentification to local $SqlInstance.
$con = New-Object Data.SqlClient.SqlConnection;
$con.ConnectionString = "Data Source=" + $ProdDBServer + "\" + $SqlInstance + ";Initial Catalog=master;User ID="+$ProdDBUser+";Password="+$ProdDBPass
$con.Open();
 
$sql = "USE [master]; ALTER DATABASE [" + $ProdDBName + "] SET OFFLINE WITH ROLLBACK IMMEDIATE; RESTORE DATABASE [" + $ProdDBName + "] FROM  DISK = N'" + $DBBakFile + "' WITH  FILE = 1,  MOVE N'"+ $moveDB + "' TO N'" + $DBMasterPath + $ProdDBName +".mdf',  MOVE N'" + $moveDBLog + "' TO N'"+ $DBMasterPath + $ProdDBName+ "_log.ldf',  NOUNLOAD,  REPLACE,  STATS = 5; ALTER DATABASE [" + $ProdDBName + "] SET ONLINE WITH ROLLBACK IMMEDIATE"
#Write-Host $sql

$cmd = New-Object Data.SqlClient.SqlCommand $sql, $con;
$dummy = $cmd.ExecuteNonQuery();       
Write-Host "Database $ProdDBName is Restored!";
 
#Sync changed files from staging to prod
Write-Host "Copying app files to destination host"
xcopy $SrcWebSitePath $DstWebSitePath /E /D /C /Y

$connectionString = "Data Source=LOCALHOST\$SqlInstance;Initial Catalog=$ProdDBName;User ID=$LocalDBUser;Password=$LocalDBPass"

# Change web.config connection string
write-host "Change connectionstring in web.config..."
$webConfigPath = $DstWebSitePath + "\web.config"
$backup = $webConfigPath + ".bak"
 
# Get the content of the config file and cast it to XML and save a backup copy labeled .bak
$xml = [xml](get-content $webConfigPath)
$xml.Save($backup)
 
# Change original connectionString
$root = $xml.get_DocumentElement();
$node = $root.SelectSingleNode("//connectionStrings/add[@name='SiteSqlServer']")
$node.connectionString = $connectionString
 
# Save it
$xml.Save($webConfigPath)
Write-Host "Cleaning up BAK file... $SrcTMPPath\$StageDBName.bak"
remove-item "$SrcTMPPath\$StageDBName.bak"
write-host "Restore Done!"