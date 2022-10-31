$Username="GizmoAPI"
$LocalUser=$null
$Feature = "Web-Windows-Auth"

if (Get-WindowsFeature -Name Web-Windows-Auth | Where-Object InstallState -eq Installed) {

try {
    $LocalUser = Get-LocalUser -Name $Username
    Write-Host $($Username) Already exist
    } 

Catch [Microsoft.PowerShell.Commands.UserNotFoundException] {
    "$($Username) was not found"
    } 

If ( -not $LocalUser) {
    $SecureString = ConvertTo-SecureString "G1zm0AP1" -AsPlainText -Force
    New-LocalUser -Name $Username -Password $SecureString -AccountNeverExpires -PasswordNeverExpires -UserMayNotChangePassword
    }
if ((Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST'  -filter "system.webServer/proxy" -Name "enabled") | Where-Object "Value" -eq True ) {
        Write-Host Already exist
} else {
    Set-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST'  -filter "system.webServer/proxy" -name "enabled" -value "True" #Enable IIS Proxy
    }

try {
#If the new website are correctly create, enable windowsAuthentication & disable anonymousAuth. And copy the rewrite rules file into the website directory
if (Get-Website | Where-Object "Name" -eq gsxapi){
    Write-Host Already exist
    } else {
        New-Item -Path C:\inetpub -Name "gsxapi" -ItemType "Directory" #Create the gsxapi directory to use it in gsxapi IIS website
        New-WebAppPool -Name "gsxapi" #Create a new ApplicationPool named "gsxapi"
        New-Website -Name 'gsxapi' -Port '8080' -PhysicalPath 'C:\inetpub\gsxapi' -ApplicationPool 'gsxapi' #Create the new website named "gsxapi"
        Copy-Item -Path $PSScriptRoot\api\web.config -Destination C:\inetpub\gsxapi\
        Set-WebConfiguration system.webServer/security/authentication/anonymousAuthentication -PSPath IIS:\ -Location gsxapi -Value @{enabled="False"}
        Set-WebConfiguration system.webServer/security/authentication/windowsAuthentication -PSPath IIS:\ -Location gsxapi -Value @{enabled="True"}   
    }
}

catch {
    $ErrorMessage = if ($_.Exception.InnerException -and $_.Exception.InnerException.Message) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
    throw "Failed to enable APIs because of this error: $ErrorMessage."
}
} else {
    Write-Warning "$($Feature) was not installed"
}


