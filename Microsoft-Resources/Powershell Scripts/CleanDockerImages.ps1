Function Get-DiskSize {
    $Disks = @()
    $DiskObjects = Get-WmiObject -namespace "root/cimv2" -query "SELECT Name, Capacity, FreeSpace FROM Win32_Volume"
    $DiskObjects | ForEach-Object {
      $Disk = New-Object PSObject -Property @{
        Name           = $_.Name
        Capacity       = [math]::Round($_.Capacity / 1073741824, 2)
        FreeSpace      = [math]::Round($_.FreeSpace / 1073741824, 2)
        FreePercentage = [math]::Round($_.FreeSpace / $_.Capacity * 100, 1)
      }
      $Disks += $Disk
    }
    Write-Output $Disks | Sort-Object Name
  }
  Get-DiskSize | Format-Table Name,@{L='Capacity (GB)';E={$_.Capacity}},@{L='FreeSpace (GB)';E={$_.FreeSpace}},@{L='FreePercentage (%)';E={$_.FreePercentage}}

  if ($FreePercant | Where-Object FreePercentage -le "15") {
      docker image prune -a
  }