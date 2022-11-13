[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$url = "https://raw.githubusercontent.com/jborean93/ansible-windows/master/scripts/Install-WMF3Hotfix.ps1"
$file = "$env:temp\Install-WMF3Hotfix.ps1"

(New-Object -TypeName System.Net.WebClient).DownloadFile($url, $file)
powershell.exe -ExecutionPolicy ByPass -File $file -

Start-Service WinRM
winrm quickconfig
cmd.exe /C winrm set winrm/config/service/auth @{Basic="true"}
winrm set winrm/config/service '@{AllowUnencrypted="true"}'

Get-NetAdapter
Get-NetConnectionProfile
Set-NetConnectionProfile -InterfaceAlias Ethernet -NetworkCategory Private