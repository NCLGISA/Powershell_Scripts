<#
A script to build and maintain a CoreOS cluster
- Builds any machines that don't exist
- Stops and updates machine .vmx file as necessary
- Waits for machine to start before taking down and updating next node
Author: robert.labrie@gmail.com
#>

#list of machines to make - hostname will be set to this unless overridden
$vmlist = @('CoreOS-Node1','CoreOS-Node2','CoreOS-Node3')

#hashmap of machine specific properties
$vminfo = @{}
$vminfo['CoreOS-Node1'] = '192.168.x.x'
$vminfo['CoreOS-Node2'] = '192.168.x.x'
$vminfo['CoreOS-Node3'] = '192.168.x.x'

#hashmap of properties common for all machines
$gProps = @{}

$vminfo_temp = @{}

#pack in the cloud config
if (Test-Path .\cloud-config.yml)
{
    $cc = Get-Content "cloud-config.yml" -raw
    $vminfo.GetEnumerator() | foreach-object {
        $cn = $cc.Replace('{IP}', $_.Value)
        $b = [System.Text.Encoding]::UTF8.GetBytes($cn)
        $vminfo_temp[$_.Key] = [System.Convert]::ToBase64String($b)
        #Write-Output $cn
    }
    $gProps['coreos.config.data.encoding'] = 'base64'
}

#load VMWare snapin and connect
Add-PSSnapin VMware.VimAutomation.Core
if (!($global:DefaultVIServers.Count)) { Connect-VIServer vcenter.yourdomain.com }

#build the VMs as necessary
$template = Get-Template -Name "CoreOS-Template"
$vmhost = Get-VMHost -Name vmwarehost.yourdomain.com
$vmds = get-datastore -name DATASTORE1
$tasks = @()
foreach ($vmname in $vmlist)
{
    if (get-vm | Where-Object {$_.Name -eq $vmname }) { continue }
    Write-Host "creating $vmname"
    $task = New-VM -Template $template -Name $vmname -host $vmhost -datastore $vmds -RunAsync
    $tasks += $task
}

#wait for pending builds to complete
if ($tasks)
{
    Write-Host "Waiting for clones to complete"
    foreach ($task in $tasks)
    {
        Wait-Task $task
    }
}

#setup and send the config
foreach ($vmname in $vmlist)
{
    $vmxLocal = "$($ENV:TEMP)\$($vmname).vmx"
    $vm = Get-VM -Name $vmname
    
    #power off if running
    if ($vm.PowerState -eq "PoweredOn") { $vm | Stop-VM -Confirm:$false }

    #fetch the VMX file
    $datastore = $vm | Get-Datastore
    $vmxRemote = "$($datastore.name):\$($vmname)\$($vmname).vmx"
    if (Get-PSDrive | Where-Object { $_.Name -eq $datastore.Name}) { Remove-PSDrive -Name $datastore.Name }
    $null = New-PSDrive -Location $datastore -Name $datastore.Name -PSProvider VimDatastore -Root "\"
    Copy-DatastoreItem -Item $vmxRemote -Destination $vmxLocal
    
    #get the file and strip out any existing guestinfo
    $vmx = ((Get-Content $vmxLocal | Select-String -Pattern guestinfo -NotMatch) -join "`n").Trim()
    $vmx = "$($vmx)`n"

    #build the property bag
    $props = $gProps
    $vminfo_temp[$vmname].Keys | ForEach-Object {
        $props['coreos.config.data'] = $vminfo_temp[$vmname]
    }

    #add to the VMX
    $props.Keys | ForEach-Object {
        $vmx = "$($vmx)guestinfo.$($_) = ""$($props[$_])""`n" 
    }

    #write out the VMX
    $vmx | Out-File $vmxLocal -Encoding ascii

    #replace the VMX in the datastore
    Copy-DatastoreItem -Item $vmxLocal -Destination $vmxRemote

    #start the VM
    $vm | Start-VM
    $status = "toolsNotRunning"
    while ($status -eq "toolsNotRunning")
    {
        Start-Sleep -Seconds 1
        $status = (Get-VM -name $vmname | Get-View).Guest.ToolsStatus
    }
    
}