#
# Script.ps1
#

Add-AzureAccount 

$vnet = "the vnet your machines are in" 
$subnet = "the subnet to recreate your vm in"
$serviceName = "the cloud service the vm should be created in"
$sourceServiceName = "the source cloud service"
$subscriptionId = "your storage id"
$storageAcc = "your storage account name"
$instanceSize = "the destination vm size"

Set-AzureSubscription -SubscriptionId $subscriptionId -CurrentStorageAccountName $storageAcc

$machines = Get-Content machinelist.txt

foreach($machineName in $machines)
{
	$attachedDrives = Get-AzureDisk |where {$_.AttachedTo -like "*$machineName*" }
	
	$vmc = New-AzureVMConfig -Name $machineName -InstanceSize $instanceSize -DiskName $attachedDrives[0].DiskName
	Add-AzureEndpoint -Protocol tcp -LocalPort 3389 -PublicPort 5842 -Name 'RDP' -VM $vmc
	Set-AzureSubnet $subnet -VM $vmc
	
	# remove disk 0 as this is part of the config command. Any remaining ones we add as dataDisks
	
	$dataDisks = $attachedDrives[1..($attachedDrives.Length-1)]
	
	foreach($diskName in $dataDisks.DiskName)
	{
		$lun = 1
		Add-AzureDataDisk -Import $diskName -LUN $lun -VM $vmc
		$lun++
	}
	
	#grab it's IP address for later use
	$ipaddress = Get-AzureVM -Name AzureVMMigrationTest -ServiceName $sourceServiceName |Get-AzureStaticVNetIP
	
	#power down the Existing VM
	
	Stop-AzureVM -Name $machineName -serviceName $sourceServiceName
	
	#remove the existing VM
	Remove-AzureVM -Name $machineName -serviceName $sourceServiceName
	
	# found moving on immediately just upsets things, so we'll wait 2 minutes...
	Start-Sleep -s 120
	
	#create it again, and wait for it to powerup
	New-AzureVM -ServiceName $serviceName -VMs $vmc -VNetName $vnet
	$vmState = Get-AzureVM -Name $machineName -serviceName $ServiceName
	while($vmState.Status -ne "ReadyRole")
	{
		Start-Sleep -s 10
		$vmState = Get-AzureVM -Name $machineName -serviceName $ServiceName
	}

	# re-ip the server, then move on
	Get-AzureVM -Name $machineName -serviceName $ServiceName | Set-AzureStaticVNetIP -IPAddress $ipaddress
}

