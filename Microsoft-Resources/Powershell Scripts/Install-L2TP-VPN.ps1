New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\PolicyAgent" -Name "AssumeUDPEncapsulationContextOnSendRule" -Value "2" -PropertyType "Dword"
Install-Module -Name VPNCredentialsHelper -Force
Add-VpnConnection -Name "" -ServerAddress "vpn.domain.com" -TunnelType "L2tp" -L2tpPsk "" -AuthenticationMethod MsChapv2 -RememberCredential -PassThru -Force
Set-VpnConnectionUsernamePassword -connectionname "" -username "" -password ""
