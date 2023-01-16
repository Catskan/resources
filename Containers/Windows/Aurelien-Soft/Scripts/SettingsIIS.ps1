    Param(
        [string] $APP_NAME = "Default Web Site",
        [string] $AppPool_NAME = "DefaultAppPool",
        [string] $API_NAME = "WebAPI",
        [string] $API_Path = "C:\Program Files\Aurelien-Soft\Web-UI\WebAPI"
    )

    Start-Service -Name W3SVC
    Write-Host 'Importing module ''WebAdministration''...'
    Import-Module WebAdministration


    $apiPath = $null

    Write-Host "Website is: $APP_NAME"
    Write-Host "AppPool is: $AppPool_NAME"
    Write-Host "Api Name is: $API_NAME"
    Write-Host "Api path is: $API_Path"

    $RootFolder = "C:\Scripts\SettingsIIS\"

    $HelpersFolder = Join-Path -Path $RootFolder -ChildPath 'Helpers' -Resolve
    $Helpers = Get-ChildItem -Path $HelpersFolder

    foreach ($Script in $Helpers) {
        . $Script.FullName
    }

    try {

        $ExpectedModulesList = @(
            'ApplicationRequestRouting',
            'AspNetCoreModuleV2',
            'RewriteModule',
            'WebSocketModule'
        )

        Write-Host "Checking installed Web Modules..."

        foreach ($Module in $ExpectedModulesList) {

            Write-Host "`t- Checking module '$Module'"

            $IsModuleInstalled = Get-WebGlobalModule -Name "$Module"

            if ( !($IsModuleInstalled) ) {
                throw "`t`tModule named '$Module' is not installed."
            }
            else {
                Write-Host "`t`tModule named '$Module' is properly installed."
            }

        }

        Start-Process iisreset.exe -Wait -ArgumentList '/noforce' -NoNewWindow
        if ($null -eq $API_Path) {
            $apiPath = (Join-Path -Path $sitePath -ChildPath $API_NAME)
        }
        else {
            $apiPath = $API_Path
        }

        Write-Host "Creating Web Application named '$API_NAME' in '$apiPath'..."
        New-WebApplication -Name $API_NAME -Site $APP_NAME -PhysicalPath $apiPath -ApplicationPool $AppPool_NAME -Force

        # Trying to reach the Web UI URL
        try {
            $WebUIUrlToReach = 'localhost/WebApi/graphql'
            Write-Host "Trying to reach the Web UI URL '$WebUIUrlToReach'..."
            $Req = Invoke-WebRequest -Uri "$WebUIUrlToReach" -UseBasicParsing
            Write-Host "Web UI URL '$WebUIUrlToReach' successfully reached and triggered the Web UI revisions process"
        }
        catch {
            Write-Host "Web UI URL '$WebUIUrlToReach' not reached but triggered the Web UI revisions process"
        }

        Write-Host 'Retrieving SQL connection parameters...'
        # Registry keys
        $AurelienSoftRegistryKey = 'HKLM:\SOFTWARE\Aurelien-Soft'
        $ScanConfigRegistryKey = Join-Path $AurelienSoftRegistryKey -ChildPath "Scan Configuration Microservice"

        Set-ItemProperty -Path "IIS:\sites\$APP_NAME" -Name "physicalPath" -Value "C:\Program Files\Aurelien-Soft\Web-UI"
    }
    catch {
        $ErrorMessage = if ($_.Exception.InnerException -and $_.Exception.InnerException.Message) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        throw "Failed to reach the Web UI because of this error: $ErrorMessage"
    }