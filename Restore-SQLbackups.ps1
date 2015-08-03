<# 
NAME:     Restore-SQLbackups.ps1 
AUTHOR:   Todd Thatcher
DATE:     20150729
PURPOSE:  This script was written to restore 5000+ databases from backups to a new server. 
#>                              
import-module "SQLPS" -DisableNameChecking

###  need to CHANGE these to parameters.             
$FS = ""     #Root of Parent Directory for backups.
$Serverinstance = "" # the server that we're restoring to e.g. "SQLSERVER\Instance"
$DataPath = "" # The root path for the data files on the target instance e.g. "d:\sql\Data"
$LogPath = "" # The root path for the log files on the target instance

### Don't change these
$SQLSVR = New-Object -TypeName  Microsoft.SQLServer.Management.Smo.Server("$ServerInstance")
$SF = gci $FS -Recurse | ?{ $_.PSIsContainer} | where-object {($_.getfiles().Count -ge 1)};  # Find all non-empty directories
$DeviceType = [Microsoft.SqlServer.Management.Smo.DeviceType]::File
    
	###Walk through the Backup directory tree and restore any backup found there. 
    foreach ($Target  in $SF){
        $BackupFile = $Target .getfiles().fullname | select -last 1
        $FileInfo = Invoke-Sqlcmd -query "restore filelistonly from disk =`'$BackupFile`'"
        $DataFiles= $FileInfo | ?{$_.type -eq "D"}
        $Restore = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Restore
   
       ### Striped  Backup - Iterate through the directory and add all backup files.
	   ###  Testing file name for string indicating a striped backup. Is there a way do determine number of files in a striped set from a single backup file?
        IF ($BackupFile -like "*_?_C*.bak"){ 
            foreach ($File in $Target .getfiles()){    
                $BackupName = $File.FullName
                $RestoreDevice = New-Object -TypeName Microsoft.SQLServer.Management.Smo.BackupDeviceItem($BackupName,$DeviceType)
                $Restore.Devices.Add($RestoreDevice)
				}
			}
       ### Single File backups         
        Else { 
            $BackupName = $Target .getfiles().FullName | select -last 1 ### Select last 1 ensures that 
            $RestoreDevice = New-Object -TypeName Microsoft.SQLServer.Management.Smo.BackupDeviceItem($BackupName,$DeviceType)
            $Restore.Devices.Add($RestoreDevice)
            }
                
       ### Iterate through the logical files and set new physical locations
        Foreach ($Entry in $FileInfo){
            $Restorefile = new-object('Microsoft.SqlServer.Management.Smo.RelocateFile')
            $Restorefile.LogicalfileName = $Entry.LogicalName
            If ($Entry.type -eq "D"){    
                $Restorefile.PhysicalFilename = ($DataPath+$($Target ).name+"\"+$Entry.LogicalName+".mdf")
                }
            Else { $Restorefile.PhysicalFilename = ($LogPath+$($Target ).name+"\"+$Entry.LogicalName+".ldf")
                }
            $Restore.RelocateFiles.Add($Restorefile) | out-null
            }
   
        $Restore.Database = "$Target "
        $Restore.ReplaceDatabase = $False
      TRY {  $Restore.SQLRestore($SQLSVR)}
      CATCH {$_.Exception.GetBaseException().Message}
      }
