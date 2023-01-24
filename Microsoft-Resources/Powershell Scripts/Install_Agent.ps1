##General variables
$AzureDevOpsOrganisation_URL="https://dev.azure.com/organisationName"
$AuthType="pat"
$PersonnalAccessToken=""
$AgentPoolName=""
$TempFilesDestination="C:\Temp"
$LocalAgentUsername = ""

$UnattendInstallMethod = 'passive' #passive or quiet

####### Softwares dependencies ########
$SoftDep = 'nssm-2.24', 'innosetup-5.6.1', 'elasticsearch-7.13.2', 'elasticsearch-7.16.1', 'elasticsearch-7.16.2', 'elasticsearch-6.8.22', 'elasticsearch-7.17.0'



######## Softwares ########
$VS2017 = 'Visual Studio Enterprise 2017'
$VS2017BuildTools = 'Visual Studio Build Tools 2017'
$VS2019 = 'Visual Studio Enterprise 2019'
$MSEdge = 'Microsoft Edge'
$MSBuild_ExtensionPack = 'MSBuild Extension Pack'
$AzCopy = 'AzCopy'
$InnoSetup = 'Inno Setup'
$WinZip = 'WinZip'
$Java = 'Java'
$Yarn = 'Yarn'
$NodeJS = 'NodeJS'

######## Package providers ########
$Nuget = 'Nuget'
$DockerProvider = 'DockerMsftProvider'
$Docker = 'Docker'

######## Windows Features ########
$HyperV = 'Hyper-V'
$Containers = 'Containers'

######## Packages/Modules ########
$AzModule = 'Az'
$AzCLI = 'AzCLI'
$AzCli_InstallPath = 'C:\Program Files (x86)\AzCLI'
$AzCopy = 'AzCopy'
$AzPowershellModule = 'AzCmdlets'

######## Windows Services ########
$AgentService = 'vstsagent'

######## Feature needed by all functions ########
if ([System.IO.Directory]::Exists("C:\Temp") -eq $False){
    New-Item -Name "Temp" -Path C:\ -Type Directory
}


#$ErrorActionPreference = 'SilentlyContinue'
$VerbosePreference = 'Continue'




function CreateAgentUser {
    #$Password = ""
    Clear-Host
    $ErrorActionPreference = 'Stop'
    $VerbosePreference = 'Continue'
    
    #User to search for
    
    #Declare LocalUser Object
    $ObjLocalUser = $null
    
    Try {
        $ObjLocalUser = Get-LocalUser $LocalAgentUsername
        Write-Verbose "User $($LocalAgentUsername) was found"
    }
    
    Catch [Microsoft.PowerShell.Commands.UserNotFoundException] {
        "User $($LocalAgentUsername) was not found" | Write-Warning
    }

    If (!$ObjLocalUser) {
        Write-Verbose "Creating User $($LocalAgentUsername)"
        $mtloagentadmin_Password = Read-Host "Enter the password for mtloagentadmin user" -AsSecureString
        New-LocalUser -Name $LocalAgentUsername -FullName "Agent Admin" -Password $mtloagentadmin_Password -Description "User to run the Azure agent service" -AccountNeverExpires    
        Add-LocalGroupMember -Group "Administrators" -Member $LocalAgentUsername
        $acl = Get-Acl $TempFilesDestination
        $AccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("$LocalAgentUsername","FullControl","Allow")
        $acl.SetAccessRule($AccessRule)
        $acl | Set-Acl $TempFilesDestination
        Write-Verbose "User successfully created"
    } 
}
    
function InstallEdgeBrowser {

    $Status_MSEdge = Get-Package -ProviderName Programs -IncludeWindowsInstaller $MSEdge
    
    If ($Status_MSEdge){
        Try {
            Write-Host "$($Status_MSEdge.Name) already installed with version $($Status_MSEdge.Version)"
        }
        Catch {
            Write-Error "$($MSEdge) is not installed. Installing it ..."
        }
    }
    Else {
        Write-Host "Installing $($MSEdge) ..."
        $Edge_URL = "https://msedge.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/e0f579f4-420a-43fb-b0b1-e6f86712ac76/MicrosoftEdgeEnterpriseX64.msi"
        (New-Object System.Net.WebClient).DownloadFile("$Edge_URL","$TempFilesDestination\MicrosoftEdgeEnterpriseX64.msi")
        msiexec /i $TempFilesDestination\MicrosoftEdgeEnterpriseX64.msi /$UnattendInstallMethod | Out-Null
    }
}
#Download Visual Studio 2017
function Install_VS2017 {
    $Status_VS2017 = Get-Package -ProviderName Programs -IncludeWindowsInstaller $VS2017*
    
    If ($Status_VS2017){
        Try {
            Write-Host "$($Status_VS2017.Name) already installed with version $($Status_VS2017.Version)"
        }
        Catch {
            Write-Error "$($VS2017) is not installed. Installing it ..."
        }
    }
    Else {
        Write-Host "Installing $($VS2017) ..."
        $VS2017_URL="https://aka.ms/vs/15/release/vs_enterprise.exe"
        (New-Object System.Net.WebClient).DownloadFile("$VS2017_URL","$TempFilesDestination\VS2017.exe")
        Start-Process -FilePath $TempFilesDestination\VS2017.exe -ArgumentList "--$($UnattendInstallMethod)", "--norestart", `
        "--add Microsoft.VisualStudio.Product.BuildTools",`
        "--add Microsoft.Netcore.Component.Web",`
        "--add Microsoft.VisualStudio.Component.Web" -Wait
        Write-Host "$($VS2017) successfully installed"
    }
}

function Install_VS2019 {
    $Status_VS2019 = Get-Package -ProviderName Programs -IncludeWindowsInstaller $VS2019*
    
    If ($Status_VS2019){
        Try {
            Write-Host "$($Status_VS2019.Name) already installed with version $($Status_VS2019.Version)"
        }
        Catch {
            Write-Error "$($VS2019) is not installed. Installing it ..."
        }
    }
    Else {
        Write-Host "Installing $($VS2019) ..."
        $VS2019_URL="https://aka.ms/vs/16/release/vs_enterprise.exe"
        (New-Object System.Net.WebClient).DownloadFile("$VS2019_URL","$TempFilesDestination\VS2019.exe")
        Start-Process -FilePath $TempFilesDestination\VS2019.exe -ArgumentList "--$($UnattendInstallMethod)","--norestart", `
        "--add Microsoft.VisualStudio.Product.BuildTools", `
        "--add Microsoft.Netcore.Component.Web", `
        "--add Microsoft.VisualStudio.Component.Web", `
        "--add Microsoft.Component.MSBuild", `
        "--add Microsoft.NetCore.Component.Runtime.3.1", `
        "--add Microsoft.Net.Component.4.5.1.TargetingPack", `
        "--add Microsoft.Net.Component.4.6.TargetingPack", `
        "--add Microsoft.Net.Component.4.TargetingPack", `
        "--add Microsoft.Net.ComponentGroup.TargetingPacks.Common", `
        "--add Microsoft.Net.Component.4.6.1.TargetingPack", `
        "--add Microsoft.Net.Component.4.6.2.TargetingPack", `
        "--add Microsoft.Net.Component.4.7.1.TargetingPack", `
        "--add Microsoft.Net.Component.4.7.2.TargetingPack", `
        "--add Microsoft.Net.Component.4.8.TargetingPack", `
        "--add Microsoft.Net.Component.4.8.SDK", `
        "--add Microsoft.NetCore.Component.SDK", `
        "--add Microsoft.Net.Core.Component.SDK.2.1", `
        "--add Microsoft.Net.Core.Component.SDK.3.0", `
        "--add Microsoft.Component.NetFX.Native", `
        "--add Microsoft.VisualStudio.ComponentGroup.UWP.NetCoreAndStandard", `
        "--add Microsoft.Component.CodeAnalysis.SDK", `
        "--add Microsoft.NetCore.ComponentGroup.DevelopmentTools.2.1", `
        "--add Microsoft.NetCore.ComponentGroup.Web.2.1", `
        "--add Microsoft.Net.Component.3.5.DeveloperTools", `
        "--add Microsoft.VisualStudio.Component.Windows10SDK.19041", `
        "--add Microsoft.NetCore.Component.Runtime.5.0", `
        "--add Microsoft.VisualStudio.Component.DiagnosticTools", `
        "--add Microsoft.VisualStudio.Component.IntelliTrace.FrontEnd", `
        "--add Microsoft.VisualStudio.Component.Debugger.JustInTime", `
        "--add Microsoft.VisualStudio.Component.IntelliCode", `
        "--add Microsoft.VisualStudio.Component.JavaScript.TypeScript", `
        "--add Component.Microsoft.VisualStudio.LiveShare", `
        "--add Microsoft.VisualStudio.Component.LiveUnitTesting", `
        "--add Microsoft.VisualStudio.Component.EntityFramework", `
        "--add Microsoft.VisualStudio.Component.TypeScript.4.3", `
        "--add Microsoft.VisualStudio.Component.Roslyn.LanguageServices", `
        "--add Microsoft.VisualStudio.Component.NuGet", `
        "--add Microsoft.VisualStudio.Component.NuGet.BuildTools", `
        "--add Microsoft.VisualStudio.Component.MSODBC.SQL", `
        "--add Microsoft.VisualStudio.Component.MSSQL.CMDLnUtils", `
        "--add Microsoft.VisualStudio.Component.SQL.SSDT", `
        "--add Microsoft.VisualStudio.Component.VC.140", `
        "--add Microsoft.VisualStudio.Component.AspNet45", `
        "--add Microsoft.VisualStudio.Component.JavaScript.Diagnostics", `
        "--add Microsoft.VisualStudio.Component.Debugger.Snapshot", `
        "--add Microsoft.VisualStudio.Component.Debugger.TimeTravel", `
        "--add Microsoft.VisualStudio.Component.Web" -Wait
        Write-Host "$($VS2019) successfully installed"
    }
}


function Install_MSBuildExtensionPack {
    $Status_MSBuildExtensionPack = Get-Package -ProviderName Programs -IncludeWindowsInstaller $MSBuild_ExtensionPack*
    
    If ($Status_MSBuildExtensionPack){
        Try {
            Write-Host "$($Status_MSBuildExtensionPack.Name) already installed with version $($Status_MSBuildExtensionPack.Version)"
        }
        Catch {
            Write-Error "$($MSBuild_ExtensionPack) is not installed. Installing it ..."
        }
    }
    Else {
        Write-Host "Installing $($MSBuild_ExtensionPack) ..."
        $ExtensionPack_URL = "https://github.com/mikefourie-zz/MSBuildExtensionPack/releases/download/4.0.15.0/MSBuild.Extension.Pack.4.0.15.0.zip"
        Write-Host "Downloading MSBuild Extension Pack"
        (New-Object System.Net.WebClient).DownloadFile("$ExtensionPack_URL","$TempFilesDestination\MSBuild.Extension.Pack.4.0.15.0.zip")
        Expand-Archive -Path "$TempFilesDestination\MSBuild.Extension.Pack.4.0.15.0.zip" -DestinationPath $TempFilesDestination -Force
        $Msi_Name = (Get-ChildItem $TempFilesDestination -Filter "MSBuild*(x64).msi" -Recurse).FullName
        Write-Host "Installing MSBuild Extension Pack"
        msiexec.exe /i $Msi_Name INSTALLFOLDER=`"C:\Program Files\MSBuild\ExtensionPack\4.0`" "/$($UnattendInstallMethod)" | Out-Null
        Write-Host "MSBuild Extension Pack Successfully installed"    
    }
}

function Install_VS2017BuildTools {
    $Status_VS2017BuildTools = Get-Package -ProviderName Programs -IncludeWindowsInstaller $VS2017BuildTools*
    
    If ($Status_VS2017BuildTools){
        Try {
            Write-Host "$($Status_VS2017BuildTools.Name) already installed with version $($Status_VS2017BuildTools.Version)"
        }
        Catch {
            Write-Error "$($Status_VS2017BuildTools) is not installed. Installing it ..."
        }
    }
    Else {
        Write-Host "Installing $($VS2017BuildTools) ..."
        $VS2017BuildTools_URL = "https://download.visualstudio.microsoft.com/download/pr/3e542575-929e-4297-b6c6-bef34d0ee648/639c868e1219c651793aff537a1d3b77/vs_buildtools.exe"
        Write-Host "Downloading $($VS2017BuildTools)"
        (New-Object System.Net.WebClient).DownloadFile("$VS2017BuildTools_URL","$TempFilesDestination\vs2017_buildtools.exe")
        Write-Host "Installing $($VS2017BuildTools)"
        Start-Process -FilePath "$($TempFilesDestination)\vs2017_buildtools.exe" -ArgumentList "--$($UnattendInstallMethod)", `
        "--add Microsoft.VisualStudio.Component.NuGet.BuildTools" -Wait
        Copy-Item -Path "C:\Program Files (x86)\Microsoft Visual Studio\2017\Enterprise\MSBuild\Microsoft\VisualStudio\v15.0\WebApplications" -Destination 'C:\Program Files (x86)\Microsoft Visual Studio\2017\BuildTools\MSBuild\Microsoft\VisualStudio\v15.0\' -Recurse -Force
        Write-Host "$($VS2017BuildTools) Successfully installed"    
    }
}

#Download SigCert & CertUtil
function Install_CertTools {

if ([System.IO.Directory]::Exists("C:\Digital Certificates") -eq $True) {
    $CertToolsDestination = Get-ItemProperty "C:\Digital Certificates"
} 
elseif ([System.IO.File]::Exists("C:\Digital Certificates\DigiCertUtil.exe") -eq $True -and ([System.IO.File]::Exists("C:\Digital Certificates\sigcheck64.exe") -eq $True)) {
    Write-Host "Files exists. Do nothing"
}
else {
    Write-Host "Installing Certificates tools"
    $CertToolsDestination = New-Item -Path C:\ -Name "Digital Certificates" -ItemType Directory
    $SigCert_URL = "https://download.sysinternals.com/files/Sigcheck.zip"
    $CertUtil_URL = "https://www.digicert.com/StaticFiles/DigiCertUtil.zip"
    (New-Object System.Net.WebClient).DownloadFile("$SigCert_URL", "$CertToolsDestination\Sigcheck.zip")
    (New-Object System.Net.WebClient).DownloadFile("$CertUtil_URL", "$CertToolsDestination\Certutil.zip")
    $Items = Get-ChildItem -Path "C:\Digital Certificates\*.zip"
    $NbItems = ($Items | Measure-Object).count
    For ($i=0;$i -lt $NbItems; $i++)
    {
        Expand-Archive "$($CertToolsDestination)\$($Items.Name[$i])" -DestinationPath $CertToolsDestination -Force
    }
    Remove-Item (Get-ChildItem $CertToolsDestination -Exclude sigcheck64.exe, DigiCertutil.exe) -Force
    Write-Host "Certificates tools successfully installed"
    }
}

#Download iQ Dependencies
function Download_iQDependencies {
$DependenciesPath = "C:\Dependencies"
if ([System.IO.Directory]::Exists($DependenciesPath) -eq $True){
        Write-host "Folder $DependenciesPath already exist"
    }
else {
    New-Item -Path "C:\" -Name "Dependencies" -ItemType Directory
}

switch ($SoftDep){
    'nssm-2.24' {            
            if ([System.IO.File]::Exists("$($DependenciesPath)\nssm-2.24\nssm.exe") -eq $False) {
            #NSSM
            Write-Host "Downloading NSSM"
            (New-Object System.Net.WebClient).DownloadFile("https://nssm.cc/release/nssm-2.24.zip","$DependenciesPath\$($SoftDep[0]).zip")
            #Extract and move nssm.exe to the nssm directory root
            Expand-Archive "$($DependenciesPath)\$($SoftDep[0]).zip" -DestinationPath $DependenciesPath  -Force
            Copy-Item -Path "$($DependenciesPath)\$($SoftDep[0])\win64\nssm.exe" -Destination "$($DependenciesPath)\$($SoftDep[0])" -Force
            Get-ChildItem "$($DependenciesPath)\$($SoftDep[0])" -Exclude "nssm.exe" | Remove-Item -Force -Recurse
            Remove-Item -Path "$($DependenciesPath)\$($SoftDep[0]).zip"
        }
    }
    'innosetup-5.6.1' {
        $Status_InnoSetup = Get-Package -ProviderName Programs -IncludeWindowsInstaller $InnoSetup*

        if ([System.IO.File]::Exists("$DependenciesPath\$($SoftDep[1]).exe") -eq $False) 
        {
    
            If ($Status_InnoSetup){
                Try {
                        Write-Host "$($Status_InnoSetup.Name) already installed with version $($Status_InnoSetup.Version)"
                    }
                Catch {
                        Write-Error "$($InnoSetup) is not installed. Installing it ..."
                        }
                    }
                Else {
                    #InnoSetup
                    Write-Host "Downloading Inno setup"
                    (New-Object System.Net.WebClient).DownloadFile("https://files.jrsoftware.org/is/5/innosetup-5.6.1.exe","$DependenciesPath\$($SoftDep[1]).exe") 
                    Write-Host "Installing Inno Setup"
                    Start-Process "$DependenciesPath\$($SoftDep[1]).exe" -ArgumentList "/SILENT","/NORESTART","/CLOSEAPPLICATIONS"
        }
    }
    }
    'elasticsearch-7.13.2' {
        if ([System.IO.Directory]::Exists("$DependenciesPath\$($SoftDep[2])") -eq $False) 
        {
            #ElasticSearch 7.13.2
            Write-Host "Downloading ElasticSearch 7.13.2"
            (New-Object System.Net.WebClient).DownloadFile("https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-7.13.2-windows-x86_64.zip","$DependenciesPath\$($SoftDep[2]).zip")

        }
    }
    'elasticsearch-7.16.1' {
        if ([System.IO.Directory]::Exists("$DependenciesPath\$($SoftDep[3])") -eq $False) 
        {
            #ElasticSearch 7.16.1 
            Write-Host "Downloading ElasticSearch 7.16.1"
            (New-Object System.Net.WebClient).DownloadFile("https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-7.16.1-windows-x86_64.zip","$DependenciesPath\$($SoftDep[3]).zip")
        }
    }
    'elasticsearch-7.16.2' {
        if ([System.IO.Directory]::Exists("$DependenciesPath\$($SoftDep[4])") -eq $False) 
        {
            #ElasticSearch 7.16.2
            Write-Host "Downloading ElasticSearch 7.16.2"
            (New-Object System.Net.WebClient).DownloadFile("https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-7.16.2-windows-x86_64.zip","$DependenciesPath\$($SoftDep[4]).zip")
        }
    }
    'elasticsearch-6.8.22' {
        if ([System.IO.Directory]::Exists("$DependenciesPath\$($SoftDep[5])") -eq $False) 
        {
            #ElasticSearch 6.8.22
            Write-Host "Downloading ElasticSearch 6.8.22"
            (New-Object System.Net.WebClient).DownloadFile("https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-6.8.22.zip","$DependenciesPath\$($SoftDep[5]).zip")
        }
    }
    'elasticsearch-7.17.0' {
        if ([System.IO.Directory]::Exists("$DependenciesPath\$($SoftDep[6])") -eq $False) 
        {
            #ElasticSearch 7.17.0
            Write-Host "Downloading ElasticSearch 7.17.0"
            (New-Object System.Net.WebClient).DownloadFile("https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-7.17.0.zip","$DependenciesPath\$($SoftDep[6]).zip")
        }
    }
}

#Extract all ElasticSearch archives
$ArchiveElastic = Get-ChildItem -Path $DependenciesPath | Where-Object {($_.Name -Match "elasticsearch" -and $_.Name -Match ".zip")}
$NbItems = ($ArchiveElastic | Measure-Object).count
For ($i=0;$i -lt $NbItems ; $i++)
{
        Expand-Archive "$($DependenciesPath)\$($ArchiveElastic.Name[$i])" -DestinationPath $DependenciesPath -Force | Out-Null
        Remove-Item -Path "$($DependenciesPath)\$($ArchiveElastic.Name[$i])*" -Recurse -Force
}

    }
function InstallWindowsFeatures{
    $Status_HyperV = Get-WindowsFeature -Name $HyperV
    $Status_Containers = Get-WindowsFeature -Name $Containers


    If ($Status_HyperV.InstallState -eq "Installed" -and $Status_Containers.InstallState -eq "Installed"){ #-and $Status_HyperV -and $Status_Containers){
        Try {
            Write-Host "$($Status_HyperV.Name) already installed with version $($Status_HyperV.Version)"
            Write-Host "$($Status_Containers.Name) already installed with version $($Status_Containers.Version)"
        }
        Catch {
            Write-Error "PackageProvider $($Nuget) is not installed. Installing it ..."
            Write-Error "Powershell module $($AzModule) is not installed. Installing it ..."
            Write-Error "Windows Feature $($HyperV) is not installed. Installing it ..."
            Write-Error "Windows Feature $($Containers) is not installed. Installing it ..."
            Write-Error "$($Docker) package is not installed. Installing it ... "
        }
    }
    Else {
        
        Write-Host "Installing $($Nuget)"
        Install-PackageProvider -Name Nuget -Force
        choco install nuget.commandline --version=6.0.0 -y
        Write-Host "Install Powershell $($AzModule) module ..."
        Write-Host "Installing Windows features ..."
        Install-WindowsFeature -Name Hyper-V, Containers
        Write-Host "$($HyperV), $($Containers) successfully installed"
        Write-Host "Installing $($DockerProvider) provider"
        Install-Module -Name DockerMsftProvider -Repository PSGallery -Force 
        Write-Host "$($DockerProvider) successfully installed"
        Write-Host "Installing $($Docker) package"
        Install-Package -Name docker -ProviderName DockerMsftProvider -Force
        Write-Host "$($Docker) successfully installed"
        Set-Content -Path C:\ProgramData\docker\config\daemon.json -Value "{`"experimental`": true}"
        type C:/ProgramData/docker/config/daemon.json
        Restart-Service docker
    }
}

#Download the Azure Agent binaries
function Install_AzureAgent {
    $Status_VSTSService = Get-Service -Name "vstsagent*"

    If ($Status_VSTSService) {
        Try {
            Write-Host "$($Status_VSTSService.Name) already installed and $($Status_VSTSService.Running)"
        }
        Catch {
            Write-Error "$($AgentService) is not installed"
        }
    }
    Else {
        if ([System.IO.Directory]::Exists("C:\agent") -eq $False){
            Write-Host "Agent directory creating ..."
            New-Item -Path "C:\" -Name "Agent" -ItemType Directory
        }
        else {
            Write-Host 'Removing existing "Agent" directory'
            Remove-Item "C:\Agent" -Recurse -Force
            Write-Host 'Creating "Agent" directory'
            New-Item -Path "C:\" -Name "Agent" -ItemType Directory
        }
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $wr = Invoke-WebRequest https://api.github.com/repos/Microsoft/azure-pipelines-agent/releases/latest
        $tag = ($wr | ConvertFrom-Json)[0].tag_name
        $tag = $tag.Substring(1)  
        write-host "$tag is the latest version"
        $AzureAgent_DownloadURL = "https://vstsagentpackage.azureedge.net/agent/$tag/vsts-agent-win-x64-$tag.zip"

        $SplitAgentURL = $AzureAgent_DownloadURL.Split('/')
        $CountArchiveName = $SplitAgentURL.Count
        $ArchiveName = $SplitAgentURL[$CountArchiveName-1]
        Write-Host "Downloading Agent ..."
        (New-Object System.Net.WebClient).DownloadFile("$($AzureAgent_DownloadURL)", "C:\agent\$($ArchiveName)")
        Write-Host "Agent successfully downloaded"
        Write-Host "Extracting Agent ..."
        Expand-Archive "C:\agent\$($ArchiveName)" -DestinationPath "C:\agent"
    
        #Install Azure Agent
        $AgentName = [System.Environment]::GetEnvironmentVariable('Computername')
        C:\agent\config.cmd --unattended --replace --url $AzureDevOpsOrganisation_URL --auth $AuthType --token $PersonnalAccessToken --pool $AgentPoolName --agent $AgentName --acceptTeeEula --runAsService --windowsLogonAccount "gsxdev\svc_vsts" --windowsLogonPassword 'Vwh.Xw*j8'
        Start-Service vstsagent*
        }
    }  

function Install_AzureAgent_mtlo {
        if ([System.IO.Directory]::Exists("C:\mtlo_agent") -eq $False){
            Write-Host "Agent directory creating ..."
            New-Item -Path "C:\" -Name "agent_mtlo" -ItemType Directory
        }
        else {
            Write-Host 'Removing existing "Agent" directory'
            Remove-Item "C:\agent_mtlo" -Recurse -Force
            Write-Host 'Creating "Agent" directory'
            New-Item -Path "C:\" -Name "agent_mtlo" -ItemType Directory
        }
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $wr = Invoke-WebRequest https://api.github.com/repos/Microsoft/azure-pipelines-agent/releases/latest
        $tag = ($wr | ConvertFrom-Json)[0].tag_name
        $tag = $tag.Substring(1)  
        write-host "$tag is the latest version"
        $AzureAgent_DownloadURL = "https://vstsagentpackage.azureedge.net/agent/$tag/vsts-agent-win-x64-$tag.zip"

        $SplitAgentURL = $AzureAgent_DownloadURL.Split('/')
        $CountArchiveName = $SplitAgentURL.Count
        $ArchiveName = $SplitAgentURL[$CountArchiveName-1]
        Write-Host "Downloading Agent ..."
        (New-Object System.Net.WebClient).DownloadFile("$($AzureAgent_DownloadURL)", "C:\agent_mtlo\$($ArchiveName)")
        Write-Host "Agent successfully downloaded"
        Write-Host "Extracting Agent ..."
        Expand-Archive "C:\agent_mtlo\$($ArchiveName)" -DestinationPath "C:\agent_mtlo"
    
        #Install Azure Agent
        $AgentName = ("$([System.Environment]::GetEnvironmentVariable('Computername'))_mtlo")
        C:\agent_mtlo\config.cmd --unattended --replace --url $AzureDevOpsOrganisation_URL_mtlo --auth $AuthType --token $PersonnalAccessToken_mtlo --pool $AgentPoolName --agent $AgentName --acceptTeeEula --runAsService --windowsLogonAccount "gsxdev\mtloagentadmin" --windowsLogonPassword "qERsFxwM27OHv2bTHh"
        }    
#Install AzureCLI
function Install_AzureCLI {
    Write-Host "Installing AzCLI ..."
    $AzureCLI_URL = "https://aka.ms/installazurecliwindows/"
    (New-Object System.Net.WebClient).DownloadFile("$AzureCLI_URL", "$TempFilesDestination\$AzCLI.msi")
    msiexec /i $TempFilesDestination\$AzCLI.msi AZURECLIFOLDER=`"$AzCli_InstallPath`" "/$($UnattendInstallMethod)" | Out-Null
}

#Install Azure Powershell Module
function Install_AzurePowershellModule {
    Write-Host "Installing Azure Powershell Module ..."
    $AzurePowershell_URL = "https://github.com/Azure/azure-powershell/releases/download/v7.5.0-April2022/Az-Cmdlets-7.5.0.35663-x64.msi"
    (New-Object System.Net.WebClient).DownloadFile("$AzurePowershell_URL", "$TempFilesDestination\$AzCmdlets.msi")
    msiexec /i $TempFilesDestination\$AzCmdlets.msi "/$($UnattendInstallMethod)" | Out-Null
}


#Install AzCopy tool
function Install_AzCopy {   
    if (Get-ChildItem "C:\" | Where-Object Name -EQ "AzCopy") {
        az upgrade
    } else {
    (New-Object System.Net.WebClient).DownloadFile("https://aka.ms/downloadazcopy-v10-windows", "$TempFilesDestination\$AzCopy.zip")
    Expand-Archive -Path "$TempFilesDestination\$AzCopy.zip" -DestinationPath 'C:\'
    $DirectoryName = Get-ChildItem C:\ -Filter azcopy* -Directory
    Rename-Item -Path C:\$DirectoryName -NewName "C:\AzCopy"
    Set-Item -Path Env:Path -Value ($Env:Path + ";C:\AzCopy")
    }
}
 
function CreateScheduledTaskDeleteImages {
    $TaskName = "Clean docker images"
    $Status_ScheduledTask = Get-ScheduledTask -TaskName $TaskName

    If ($Status_ScheduledTask){
        Try {
            Write-Host "$($Status_ScheduledTask.TaskName) already exist and $($Status_ScheduledTask.State)"
        }
        Catch {
            Write-Error "Scheduled task $($TaskName) not exist. Creating it ..."
        }
    }
    Else {
            $Action = New-ScheduledTaskAction -Execute '.\DeleteImagesScheduledTask.ps1'
            $Trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 10am
            $Principal = New-ScheduledTaskPrincipal -GroupId "BUILTIN\Administrators" -RunLevel Highest
            $Settings = New-ScheduledTaskSettingsSet
            $Task = New-ScheduledTask -Action $Action -Description "Delete all unused docker images" -Principal $Principal -Trigger $Trigger -Settings $Settings
            Register-ScheduledTask $TaskName -InputObject $Task
        }
    } 

function Install_Java {
    $Status_Java = Get-Package -ProviderName Programs -IncludeWindowsInstaller $Java*
    
    If ($Status_Java){
        Try {
            Write-Host "$($Status_Java.Name) already installed with version $($Status_Java.Version)"
        }
        Catch {
            Write-Error "$($Status_Java) is not installed. Installing it ..."
        }
    }
    Else {
            Write-Host "Installing $Java ..."
            $JRE_URL = "https://javadl.oracle.com/webapps/download/AutoDL?BundleId=245479_4d5417147a92418ea8b615e228bb6935"
            (New-Object System.Net.WebClient).DownloadFile("$JRE_URL", "$TempFilesDestination\Java.exe")
            Start-Process $TempFilesDestination\Java.exe -ArgumentList "/s" -Wait
            #$javapath=$(get-package java* | Where-Object 'Version' -Match "^17" | Select-Object -ExpandProperty 'Source').Trim("\")
            #[System.Environment]::SetEnvironmentVariable("JAVA_HOME", $javapath, "Machine")
            Write-Host "$Java successfully installed"
    }
    choco install oracle17jdk -y
}
function Install_WhiteSourceAdvise {
    $StorageAccountName="cluster1devopstools"
    $ToolsContainerName="tools"
    $WhiteSourceModuleFile="wss-vs2019.vsix"
    #Download the module file from our Azure Storage Account
    az storage blob download --account-name $StorageAccountName --auth-mode login --container-name $ToolsContainerName --file $TempFilesDestination\$WhiteSourceModuleFile --name ./$WhiteSourceModuleFile
    #Install WhiteSource to the Visual Studio already installed
    Start-Process "C:\Program Files (x86)\Microsoft Visual Studio\2019\Enterprise\Common7\IDE\VSIXInstaller.exe" -ArgumentList "$TempFilesDestination\$WhiteSourceModuleFile",  "/admin", "/$($UnattendInstallMethod)"
}

function Download_DockerImage {
    #Download base docker images
docker pull mcr.microsoft.com/windows/servercore:ltsc2019
docker pull mcr.microsoft.com/windows:1809
}

function Install_WinZip {
    $Status_WinZip = Get-Package -ProviderName Programs -IncludeWindowsInstaller $WinZip*
    
    If ($Status_WinZip){
        Try {
            Write-Host "$($Status_WinZip.Name) already installed with version $($Status_WinZip.Version)"
        }
        Catch {
            Write-Error "$($Status_WinZip) is not installed. Installing it ..."
        }
    }
    Else {
            Write-Host "Installing $WinZip ..."
            $WinZip_URL = "https://download.winzip.com/wzipse40.msi"
            (New-Object System.Net.WebClient).DownloadFile("$WinZip_URL", "$TempFilesDestination\wzipse40.msi")
            msiexec /i $TempFilesDestination\wzipse40.msi /$UnattendInstallMethod /qn | Out-Null
            [System.Environment]::SetEnvironmentVariable("winzip_self_extractor", "C:\Program Files (x86)\WinZip Self-Extractor\WINZIPSE.exe", "Machine")
            Write-Host "$WinZip successfully installed"
    }
}

# ###### install dotnet 2.1 & 3.5 & SDK 3.1
function Install_DotNet {
try {
    Install-WindowsFeature NET-Framework-Features
    $DotNetCore21_URL= "https://download.visualstudio.microsoft.com/download/pr/fdc2c572-1f7f-4d46-b767-dd0951d10865/ad32c09fbef96146ec6b763d0192fba7/dotnet-sdk-2.1.818-win-x64.exe"
    $DotNetCore312_URL = "https://download.visualstudio.microsoft.com/download/pr/43660ad4-b4a5-449f-8275-a1a3fd51a8f7/a51eff00a30b77eae4e960242f10ed39/dotnet-sdk-3.1.200-win-x64.exe"
    $DotNet601_URL = "https://download.visualstudio.microsoft.com/download/pr/343dc654-80b0-4f2d-b172-8536ba8ef63b/93cc3ab526c198e567f75169d9184d57/dotnet-sdk-6.0.101-win-x64.exe"

    (New-Object System.Net.WebClient).DownloadFile("$DotNetCore21_URL", "C:\Temp\DotNetCore21.exe")
    (New-Object System.Net.WebClient).DownloadFile("$DotNetCore312_URL", "$TempFilesDestination\DotNetCore312.exe")
    (New-Object System.Net.WebClient).DownloadFile("$DotNet601_URL", "$TempFilesDestination\DotNet601.exe")
    Write-Host "Installing .NetCore 2.1 ..."
    Start-Process -FilePath $TempFilesDestination\DotNetCore21.exe -ArgumentList "/install", "/$($UnattendInstallMethod)", "/norestart"  -Wait
    Write-Host ".NetCore 2.1 successfully installed"
    Write-Host "Installing .NetCore 3.1.2 ..."
    Start-Process -FilePath $TempFilesDestination\DotNetCore312.exe -ArgumentList "/install", "/$($UnattendInstallMethod)", "/norestart"  -Wait
    Write-Host ".NetCore 3.1.2 successfully installed"
    Write-Host "Installing .Net 6.0.1 ..."
    Start-Process -FilePath $TempFilesDestination\DotNet601.exe -ArgumentList "/install", "/$($UnattendInstallMethod)", "/norestart"  -Wait
    Write-Host ".Net 6.0.1 successfully installed"

    }
catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    }
}

function Install_Nodejs {
    $Status_NodeJS = Get-Package -ProviderName Programs -IncludeWindowsInstaller $NodeJS*

    If ($Status_NodeJS){
        Try {
            Write-Host "$($Status_NodeJS.Name) already installed with version $($Status_NodeJS.Version)"
        }
        Catch {
            Write-Error "$($Status_NodeJS) is not installed. Installing it ..."
        }
    }
    Else {
            $NodeJS_URL = "https://nodejs.org/download/release/v14.14.0/node-v14.14.0-x64.msi"
            Write-Host "Installing NodeJS v14.14"
            (New-Object System.Net.WebClient).DownloadFile("$NodeJS_URL", "$TempFilesDestination\NodeJS.exe")
            msiexec /i $TempFilesDestination\NodeJS.exe /$UnattendInstallMethod /qn | Out-Null
            Write-host "Node JS successfully installed"
        }
}

function Install_Yarn {
    $Status_Yarn = Get-Package -ProviderName Programs -IncludeWindowsInstaller $Yarn*
    
    If ($Status_Yarn){
        Try {
            Write-Host "$($Status_Yarn.Name) already installed with version $($Status_Yarn.Version)"
        }
        Catch {
            Write-Error "$($Status_Yarn) is not installed. Installing it ..."
        }
    }
    Else {
        Write-Host "Installing Yarn ..."
        $Yarn_URL = "https://github.com/yarnpkg/yarn/releases/download/v1.22.15/yarn-1.22.15.msi"
        (New-Object System.Net.WebClient).DownloadFile("$Yarn_URL", "$TempFilesDestination\yarn-1.22.15.msi")
        msiexec /i $TempFilesDestination\yarn-1.22.15.msi /$UnattendInstallMethod /qn | Out-Null
        $yarnpath=[Environment]::GetEnvironmentVariable('LOCALAPPDATA')+'\Yarn\bin'
        [System.Environment]::SetEnvironmentVariable("yarn", $yarnpath, "Machine")
        Write-Host "Yarn successfully installed"
    }
}

function Install_WixToolset {
    $WixToolSet_URL = "https://github.com/wixtoolset/wix3/releases/download/wix3112rtm/wix311.exe"
    try {
        Write-Host "Installing Wix Tools Set 3.11.2 ..."
        (New-Object System.Net.WebClient).DownloadFile("$WixToolSet_URL", "$TempFilesDestination\wix3112.exe")
        Start-Process $TempFilesDestination\wix3112.exe /q | Out-Null
        Write-Host "Wix Tools Set successfully installed"
    }
    catch {
        Write-Host $_.Exception.Message -ForegroundColor Red
    }   
}

function Install_Chocolatey {

    Set-ExecutionPolicy Bypass -Scope Process -Force; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
}




###############Run functions####################
#CreateAgentUser
Install_AzureCLI
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User") 
az login --use-device-code ; az account set --subscription 103c7f71-81d1-4b2b-a449-de04f8852478
Install_Chocolatey
InstallEdgeBrowser
InstallWindowsFeatures
Install_VS2017
Install_VS2019
Install_MSBuildExtensionPack
Install_VS2017BuildTools
Install_WhiteSourceAdvise
Install_CertTools
Download_iQDependencies
Install_AzureAgent
Install_AzCopy
CreateScheduledTaskDeleteImages
Install_Java
Install_WinZip
Install_DotNet
Install_Nodejs
Install_Yarn
Install_WixToolset
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User") 
Download_DockerImage
Remove-Item $TempFilesDestination -Recurse -Force
#Restart-Computer -Force
