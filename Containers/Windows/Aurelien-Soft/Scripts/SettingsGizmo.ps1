Start-Transcript -Path C:\Logs\Startup\Startup-Full.log
#Powershell variables populates with Windows Environement variables setted in COnfigMaps (file)
$InstallFolderPath = [System.Environment]::GetEnvironmentVariable("InstallFolderPath")
$DownloadURI = [System.Environment]::GetEnvironmentVariable("DownloadURI")
$LicenseCode = [System.Environment]::GetEnvironmentVariable("LicenseCode")
$ScanConfig_Pkg_Path = [System.Environment]::GetEnvironmentVariable("ScanConfig_Pkg_Path")
$Scripts_Path = [System.Environment]::GetEnvironmentVariable("Scripts_Path")
$Validator_Folder_Name= [System.Environment]::GetEnvironmentVariable("ValidatorFolderName")
$ValidatorScriptName = [System.Environment]::GetEnvironmentVariable("ValidatorScriptName")
$ValidatorParamName = [System.Environment]::GetEnvironmentVariable("Validator_Param_Name")


$RMQ_Hostname = [System.Environment]::GetEnvironmentVariable("RMQ_Hostname")
$RMQ_Username = [System.Environment]::GetEnvironmentVariable("RMQ_Username")
$RMQ_Vhost = [System.Environment]::GetEnvironmentVariable("RMQ_Vhost")
$RMQ_Password = [System.Environment]::GetEnvironmentVariable("RMQ_Password")
$RMQ_Port = [System.Environment]::GetEnvironmentVariable("RMQ_Port")
$RMQ_SSL = [System.Environment]::GetEnvironmentVariable("RMQ_SSL")


$SQL_Server = [System.Environment]::GetEnvironmentVariable("SQL_Server")
$SQL_UseWindowsCredentials = [System.Environment]::GetEnvironmentVariable("SQL_UseWindowsCredentials")
$SQL_Username = [System.Environment]::GetEnvironmentVariable("SQL_Username")
$SQL_Password = [System.Environment]::GetEnvironmentVariable("SQL_Password")
$SQL_Database = [System.Environment]::GetEnvironmentVariable("SQL_Database") 

$Script_DBRev_Folder = [System.Environment]::GetEnvironmentVariable("Script_DBRev_Folder")
$Script_DBRev_Name = [System.Environment]::GetEnvironmentVariable("Script_DBRev_Name")

$SWO_Enable = [System.Environment]::GetEnvironmentVariable("SWO")

#Function to Encode in right format SQL and RabbitMQ Passwords
function EncodePassword {
    param ($Password)
    $EncodedText = [Convert]::ToBase64String([System.Text.Encoding]::UTF32.GetBytes($Password))
    return $EncodedText
}

#Stock password encoded
$RMQ_Password_Encoded = (EncodePassword -Password "$RMQ_Password")
$SQL_Password_Encoded = (EncodePassword -Password "$SQL_Password")

#Check if registry keys exist
function New-ItemPathIfNotExists {
    Param(
        $Path,
        $Name
    )

    $FullPath = Join-Path "$Path" -ChildPath "$Name"

    if (Test-Path "$FullPath") {
        Write-Host "'$FullPath' already exists"
    }
    else {
        Write-Host "'$FullPath' does not exist. Creating it ..."
        New-Item -Path "$Path" -Name "$Name"
        Write-Host "Created key '$Name' in '$Path'"
    }

}

#Create or modify registry keys syntax
function Set-OrCreatePropertyIfNotExists {
    param (
        $Path,
        $Name,
        $Value,
        $PropertyType
    )

    $PropertyExists = $true

    try {

        $ItemProperty = Get-ItemProperty -Path "$Path" -Name "$Name" -ErrorAction Stop

    }
    catch {
        $PropertyExists = $false
    }

    if ( !$PropertyExists ) {
        Write-Host "Key '$Name' does not exist in '$Path'. Creating it ... "
        $null = New-ItemProperty -Path "$Path" -Name "$Name" -Value $Value -PropertyType "$PropertyType"
        Write-Host "Key '$Name' successfully created in '$Path' with its values"
    }
    else {
        Write-Host "Key '$Name' exists in '$Path'. Updating its values ... "
        $null = Set-ItemProperty -Path "$Path" -Name "$Name" -Value $Value
        Write-Host "Values successfully updated for Key '$Name' in '$Path'"
    }

}
#Use back one function to set registry keys with environment variables passed before
function SetRegistryKeys {
    Write-Host @"
    ####################################################
    ######START - Set up Registry Keys########
    ####################################################
"@
    #--------------------------- begin Registry Keys-------------------------------------

    #General configuration
    New-ItemPathIfNotExists -Path "HKLM:\SOFTWARE\" -Name "Aurelien-Soft"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft" -Name "InstallFolderPath" -Value $InstallFolderPath -PropertyType "String"

    #Settings for Alert Microservice
    New-ItemPathIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft" -Name "Alert Microservice"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Alert Microservice" -Name "Port" -Value "60004" -PropertyType "DWord"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Alert Microservice" -Name "UseHttps" -Value "false" -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Alert Microservice" -Name "AlertDescriptionLoadingIntervalInMin" -Value "15" -PropertyType "DWord"

    #Settings for Alert Microservice RabbitMQ
    New-ItemPathIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Alert Microservice" -Name "BusConfig"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Alert Microservice\BusConfig" -Name "Hostname" -Value $RMQ_Hostname -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Alert Microservice\BusConfig" -Name "Password" -Value $RMQ_Password_Encoded -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Alert Microservice\BusConfig" -Name "Port" -Value $RMQ_Port -PropertyType "DWord"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Alert Microservice\BusConfig" -Name "Username" -Value $RMQ_Username -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Alert Microservice\BusConfig" -Name "VirtualHostname" -Value $RMQ_Vhost -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Alert Microservice\BusConfig" -Name "UseSsl" -Value $RMQ_SSL -PropertyType "String"

    #Settings for Alert Microservice Database
    New-ItemPathIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Alert Microservice" -Name "DbConfig"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Alert Microservice\DbConfig" -Name "Database" -Value $SQL_Database -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Alert Microservice\DbConfig" -Name "DataSource" -Value $SQL_Server -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Alert Microservice\DbConfig" -Name "UseWindowscredentials" -Value $SQL_UseWindowsCredentials -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Alert Microservice\DbConfig" -Name "UserID" -Value $SQL_Username -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Alert Microservice\DbConfig" -Name "Password" -Value $SQL_Password_Encoded -PropertyType "String"
    #-----------------------------------------------------
    #Settings for Data Tier Microservice
    New-ItemPathIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft" -Name "Data Tier Microservice"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Data Tier Microservice" -Name "Port" -Value "60001" -PropertyType "DWord"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Data Tier Microservice" -Name "UseHttps" -Value "false" -PropertyType "String"

    #Settings for Data Tier Microservice RabbitMQ
    New-ItemPathIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Data Tier Microservice" -Name "BusConfig"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Data Tier Microservice\BusConfig" -Name "Hostname" -Value $RMQ_Hostname -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Data Tier Microservice\BusConfig" -Name "Password" -Value $RMQ_Password_Encoded -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Data Tier Microservice\BusConfig" -Name "Port" -Value $RMQ_Port -PropertyType "DWord"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Data Tier Microservice\BusConfig" -Name "Username" -Value $RMQ_Username -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Data Tier Microservice\BusConfig" -Name "VirtualHostname" -Value $RMQ_Vhost -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Data Tier Microservice\BusConfig" -Name "UseSsl" -Value $RMQ_SSL -PropertyType "String"

    #Settings for Data Tier Microservice Database
    New-ItemPathIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Data Tier Microservice" -Name "DbConfig"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Data Tier Microservice\DbConfig" -Name "Database" -Value $SQL_Database -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Data Tier Microservice\DbConfig" -Name "DataSource" -Value $SQL_Server -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Data Tier Microservice\DbConfig" -Name "UseWindowscredentials" -Value $SQL_UseWindowsCredentials -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Data Tier Microservice\DbConfig" -Name "UserID" -Value $SQL_Username -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Data Tier Microservice\DbConfig" -Name "Password" -Value $SQL_Password_Encoded -PropertyType "String"
    #-----------------------------------------------------
    #Settings for Preprocessing Microservice
    New-ItemPathIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft" -Name "Preprocessing Microservice"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Preprocessing Microservice" -Name "Port" -Value "60002" -PropertyType "DWord"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Preprocessing Microservice" -Name "PreprocessingDescriptionsLoadingIntervalInMin" -Value "30" -PropertyType "DWord"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Preprocessing Microservice" -Name "UseHttps" -Value "false" -PropertyType "String"

    #Settings for Preprocessing Microservice RabbitMQ
    New-ItemPathIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Preprocessing Microservice" -Name "BusConfig"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Preprocessing Microservice\BusConfig" -Name "Hostname" -Value $RMQ_Hostname -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Preprocessing Microservice\BusConfig" -Name "Password" -Value $RMQ_Password_Encoded -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Preprocessing Microservice\BusConfig" -Name "Port" -Value $RMQ_Port -PropertyType "DWord"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Preprocessing Microservice\BusConfig" -Name "Username" -Value $RMQ_Username -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Preprocessing Microservice\BusConfig" -Name "VirtualHostname" -Value $RMQ_Vhost -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Preprocessing Microservice\BusConfig" -Name "UseSsl" -Value $RMQ_SSL -PropertyType "String"

    #Settings for Preprocessing Microservice Database
    New-ItemPathIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Preprocessing Microservice" -Name "DbConfig"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Preprocessing Microservice\DbConfig" -Name "Database" -Value $SQL_Database -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Preprocessing Microservice\DbConfig" -Name "DataSource" -Value $SQL_Server -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Preprocessing Microservice\DbConfig" -Name "UseWindowscredentials" -Value $SQL_UseWindowsCredentials -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Preprocessing Microservice\DbConfig" -Name "UserID" -Value $SQL_Username -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Preprocessing Microservice\DbConfig" -Name "Password" -Value $SQL_Password_Encoded -PropertyType "String"
    #-----------------------------------------------------
    #Settings for Scan configuration Microservice
    New-ItemPathIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft" -Name "Scan Configuration Microservice"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Scan Configuration Microservice" -Name "Port" -Value "60000" -PropertyType "DWord"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Scan Configuration Microservice" -Name "CertificateThumbprint" -Value "" -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Scan Configuration Microservice" -Name "PackagesDestinationPath" -Value "$ScanConfig_Pkg_Path" -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Scan Configuration Microservice" -Name "PackagesDownloadUri" -Value $DownloadURI -PropertyType "String"

    #Settings for Scan configuration Microservice RabbitMQ
    New-ItemPathIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Scan configuration Microservice" -Name "BusConfig"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Scan Configuration Microservice\BusConfig" -Name "Hostname" -Value $RMQ_Hostname -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Scan Configuration Microservice\BusConfig" -Name "Password" -Value $RMQ_Password_Encoded -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Scan Configuration Microservice\BusConfig" -Name "Port" -Value $RMQ_Port -PropertyType "DWord"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Scan Configuration Microservice\BusConfig" -Name "Username" -Value $RMQ_Username -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Scan Configuration Microservice\BusConfig" -Name "VirtualHostname" -Value $RMQ_Vhost -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Scan Configuration Microservice\BusConfig" -Name "UseSsl" -Value $RMQ_SSL -PropertyType "String"

    #Settings for Scan configuration Microservice Database
    New-ItemPathIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Scan Configuration Microservice" -Name "DbConfig"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Scan Configuration Microservice\DbConfig" -Name "Database" -Value $SQL_Database -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Scan Configuration Microservice\DbConfig" -Name "DataSource" -Value $SQL_Server -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Scan Configuration Microservice\DbConfig" -Name "UseWindowscredentials" -Value $SQL_UseWindowsCredentials -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Scan Configuration Microservice\DbConfig" -Name "UserID" -Value $SQL_Username -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Scan Configuration Microservice\DbConfig" -Name "Password" -Value $SQL_Password_Encoded -PropertyType "String"
    #-----------------------------------------------------
    #Settings for Status Calculation Microservice
    New-ItemPathIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft" -Name "Status Calculation Microservice"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Status Calculation Microservice" -Name "Port" -Value "60003" -PropertyType "DWord"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Status Calculation Microservice" -Name "UseHttps" -Value "false" -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Status Calculation Microservice" -Name "StatusDescriptionLoadingIntervalInMin" -Value "15" -PropertyType "DWord"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Status Calculation Microservice" -Name "CachePersistenceIntervalInMin" -Value "15" -PropertyType "DWord"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Status Calculation Microservice" -Name "RobotCacheLoadingIntervalInMin" -Value "15" -PropertyType "DWord"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Status Calculation Microservice" -Name "ForceDebugMode" -Value "False" -PropertyType "String"

    #Settings for Status Calculation Microservice RabbitMQ
    New-ItemPathIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Status Calculation Microservice" -Name "BusConfig"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Status Calculation Microservice\BusConfig" -Name "Hostname" -Value $RMQ_Hostname -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Status Calculation Microservice\BusConfig" -Name "Password" -Value $RMQ_Password_Encoded -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Status Calculation Microservice\BusConfig" -Name "Port" -Value $RMQ_Port -PropertyType "DWord"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Status Calculation Microservice\BusConfig" -Name "Username" -Value $RMQ_Username -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Status Calculation Microservice\BusConfig" -Name "VirtualHostname" -Value $RMQ_Vhost -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Status Calculation Microservice\BusConfig" -Name "UseSsl" -Value $RMQ_SSL -PropertyType "String"

    #Settings for Status Calculation Microservice Database
    New-ItemPathIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Status Calculation Microservice" -Name "DbConfig"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Status Calculation Microservice\DbConfig" -Name "Database" -Value $SQL_Database -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Status Calculation Microservice\DbConfig" -Name "DataSource" -Value $SQL_Server -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Status Calculation Microservice\DbConfig" -Name "UseWindowscredentials" -Value $SQL_UseWindowsCredentials -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Status Calculation Microservice\DbConfig" -Name "UserID" -Value $SQL_Username -PropertyType "String"
    Set-OrCreatePropertyIfNotExists -Path "HKLM:\SOFTWARE\Aurelien-Soft\Status Calculation Microservice\DbConfig" -Name "Password" -Value $SQL_Password_Encoded -PropertyType "String"
    #--------------------------- Stop Registry Keys-------------------------------------
    Write-Host @"
    ####################################################
    ######END - Set up Registry Keys########
    ####################################################
"@
}

#--------------------------- begin write appsettings.json to update WebUI-------------------------------------
function SettingsAppSettings.json {
    $ClientID = [System.Environment]::GetEnvironmentVariable("ClientID")
    $TenantID = [System.Environment]::GetEnvironmentVariable("TenantID")

    $FileParsed = Get-Content -Raw -Path "$InstallFolderPath\AurelienSoft_Web\WebAPI\appsettings.json" | ConvertFrom-Json

    $FileParsed.AzureAd.ClientId = $ClientID
    $FileParsed.AzureAd.TenantID = $TenantID

    $FileParsed.AppSettings.DbConfig.Datasource = $SQL_Server
    $FileParsed.AppSettings.DbConfig.Database = $SQL_Database
    $FileParsed.AppSettings.DbConfig.UseWindowsCredentials = $SQL_UseWindowsCredentials
    $FileParsed.AppSettings.DbConfig.UserID = $SQL_Username
    $FileParsed.AppSettings.DbConfig.Password = $SQL_Password_Encoded

    $FileParsed.AppSettings.BusConfig.Hostname = $RMQ_Hostname
    $FileParsed.AppSettings.BusConfig.VirtualHostname = $RMQ_Vhost
    $FileParsed.AppSettings.BusConfig.Port = $RMQ_Port
    $FileParsed.AppSettings.BusConfig.Username = $RMQ_Username
    $FileParsed.AppSettings.BusConfig.Password = $RMQ_Password_Encoded
    $FileParsed.AppSettings.BusConfig.UseSsl = $RMQ_SSL

    $FileParsed | ConvertTo-Json | Out-File "$InstallFolderPath\AurelienSoft_Web\WebAPI\appsettings.json" -Force
#--------------------------- Stop write appsettings.json to update WebUI-------------------------------------
}


#--------------------------- begin startings Microservices-------------------------------------
function StartMicroservices {
    Start-Service -Name W3SVC 
    # Write-Host @"
    Set-Location "C:\Program Files\Aurelien-Soft\Alert"
    Start-Process "C:\Program` Files\Aurelien-Soft\Alert\Microservice.Alert.exe" "disable-servicemode" -PassThru
    Set-Location "C:\Program Files\Aurelien-Soft\Data-Tier"
    Start-Process "C:\Program` Files\Aurelien-Soft\Data-Tier\Microservice.DataTier.exe" "disable-servicemode" -PassThru
    Set-Location "C:\Program Files\Aurelien-Soft\Preprocessing"
    Start-Process "C:\Program` Files\Aurelien-Soft\Preprocessing\Microservice.Preprocessing.exe" "disable-servicemode" -PassThru
    Set-Location "C:\Program Files\Aurelien-Soft\Status-Calculation"
    Start-Process "C:\Program` Files\Aurelien-Soft\Status-Calculation\Microservice.StatusCalculation.exe" "disable-servicemode" -PassThru -Wait
    ####################################################
    #############END - Start Services###############
    ####################################################
}


#Create licence file by licensecode environment variable
function SetLicenseCode {
    $LicenseCode | Out-File $InstallFolderPath\Scan-Configuration\license
}

#Start the installatio validation script
function Validation {
    Write-Host @"
    ####################################################
    #############START - Validation Script##############
    ####################################################
"@
    Start-Transcript -Path C:\Logs\Startup\Validation.log
    Invoke-Expression "& '$InstallFolderPath\Powershell\$Validator_Folder_Name\$ValidatorScriptName.ps1' -ParametersFilePath '$InstallFolderPath\Powershell\$Validator_Folder_Name\Scope\$ValidatorParamName.ps1'"
    Stop-Transcript
    Write-Host @"
    ####################################################
    #############END - Validation Script##############
    ####################################################
"@
}

#Start the revision script to initalize an empty database or upgrade it if needed
function InjectAllRevisions {
    Write-Host @"
    ####################################################
    #############START - Revision Script################
    ####################################################
"@
    Start-Transcript -Path C:\Logs\Startup\InjectDBRevisions.log
    Invoke-Expression "& '$Scripts_Path\$Script_DBRev_Folder\$Script_DBRev_Name.ps1'"
    Stop-Transcript
    Write-Host @"
    ####################################################
    #############END - Revision Script##################
    ####################################################
"@
}

#Installer all descriptions & scans capability into the database
function PopulateDatabase {
    Write-Host @"
    ####################################################
    ########START - Install Default Description#########
    ####################################################
"@
    Start-Transcript -Path C:\Logs\Startup\InstallDescriptons.log
    if ($SWO_Enable -eq 'False') {
        Invoke-Expression "& '$InstallFolderPath\Powershell\Installer.Default.Descriptions\InstallerDescriptions.ps1'"
} elseif ($SWO_Enable -eq 'True') {
            Invoke-Expression "& '$InstallFolderPath\Powershell\Installer.Default.Descriptions\InstallerDescriptions.ps1' -ProductDescriptionJsonFilePath '$InstallFolderPath\Powershell\Installer.Default.Descriptions\ClientDescription\SWO.ProductDescriptions.json'"
}
    #Invoke-Expression "& '$InstallFolderPath\Powershell\Installer.Default.Descriptions\InstallerDescriptions.ps1'"
    Stop-Transcript
    Write-Host @"
    ####################################################
    #########END - Install Default Description##########
    ####################################################
"@
}

#Start the script to generated the clientAgent.zip archive with rights tenants informations
function clientAgent.zip {
    Write-Host @"
    ####################################################
    ########START - Create clientAgent archive#########
    ####################################################
"@
    Start-Transcript -Path C:\Logs\Startup\CreateclientAgentArchive.log
    Invoke-Expression "& '$InstallFolderPath\Powershell\Installer.clientAgentInstaller\clientAgentInstaller.ps1' -RmqHostname ([System.Environment]::GetEnvironmentVariable('RMQ_Hostname')) -RmqVirtualHostname ([System.Environment]::GetEnvironmentVariable('RMQ_Vhost')) -RmqPort ([System.Environment]::GetEnvironmentVariable('RMQ_Port')) -RmqUseSSL ([System.Environment]::GetEnvironmentVariable('RMQ_SSL')) -RmqUsername ([System.Environment]::GetEnvironmentVariable('RMQ_Username')) -RmqPassword ([System.Environment]::GetEnvironmentVariable('RMQ_Password'))"
    Stop-Transcript
    Write-Host @"
    ####################################################
    #########END - Create clientAgent archive##########
    ####################################################
"@
}

#Import powershell cmdlets
function ImportCmdlets {
    Start-Transcript -Path C:\Logs\Startup\ImportCmdlets.log
    Invoke-Expression "& 'C:\ProgramData\Aurelien-Soft\ManagementShellLoader.ps1'"
    Stop-Transcript
}

SetRegistryKeys # Start SetRegistyKeys function
SettingsAppSettings.json #Start SettingsAppSettings.json function
SetLicenseCode #Start SetLicenseCode function
Start-Process "C:\Program Files\Aurelien-Soft\Scan-Configuration\ScanConfiguration.exe" "disable-servicemode" -PassThru
CreateclientAgent.zip #Start the function to generate clientAgent.zip
PopulateDatabase #Start the script to enable templates, scans configurations, ...
StartMicroservices #Start StartMicroservices
Stop-Transcript