$InterfaceIndex=(Get-NetConnectionProfile).InterfaceIndex
Set-NetConnectionProfile -InterfaceIndex $InterfaceIndex -NetworkCategory Private

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Start-Service WinRM
winrm quickconfig -quiet

# NTLM (Negotiate) is enabled by default and encrypts the payload at the
# message level, so Basic auth over an unencrypted channel is not needed.
# Explicitly disable both to avoid sending credentials in clear text.
winrm set winrm/config/service/auth '@{Basic="false"}'
winrm set winrm/config/service '@{AllowUnencrypted="false"}'

Install-Module PSCX -Force -AllowClobber
