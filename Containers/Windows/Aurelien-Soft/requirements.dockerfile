# escape=`
FROM mcr.microsoft.com/windows/servercore:ltsc2019
#Begin working directory in C:\
WORKDIR C:\

#COPY the directory with all scripts used by image
COPY ./resouces/Containers/Aurelien-Soft/Scripts C:/Scripts

ARG srcProgramFiles="./AurelienSoft_Prerequisites/"
ARG dstProgramFiles="C:/Program Files"
COPY ${srcProgramFiles} ${dstProgramFiles}

#Enable Powershell Shell
SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'Continue';"]
#Enable IIS Feature with WebSocket's Dependancies
RUN Install-WindowsFeature -Name Web-Server,  Web-Windows-Auth, Web-WebSockets
#Install SQLServer Powershell module needed by cmdlets
RUN Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force ; Install-Module -Name SqlServer -AllowClobber -Force

#Install all requierements
RUN Start-Process 'C:\Program Files\Aurelien Software\Powershell\Installer.Prerequisites\NDP462-KB3151800-x86-x64-AllOS-ENU.exe' '/install','/quiet','norestart' -PassThru | Wait-Process 
RUN Start-Process 'C:\Program Files\Aurelien Software\PowerShell\Installer.Prerequisites\dotnet-hosting-3.1.2-win.exe' '/quiet','/install','/norestart' -PassThru | Wait-Process
RUN Start-Process 'C:\Program Files\Aurelien Software\Powershell\Installer.Prerequisites\VC_redist.x64.exe' '/install','/quiet','/norestart' -PassThru | Wait-Process
RUN Start-Process 'C:\Program Files\Aurelien Software\Powershell\Installer.Prerequisites\VC_redist.x86.exe' '/install','/quiet','/norestart' -PassThru | Wait-Process
RUN Start-Process 'C:\Program Files\Aurelien Software\Powershell\Installer.Prerequisites\SharedManagementObjects.msi' '/qn' -PassThru | Wait-Process
RUN Start-Process 'C:\Program Files\Aurelien Software\Powershell\Installer.Prerequisites\SQLSysClrTypes.msi' '/qn' -PassThru | Wait-Process
RUN Start-Process 'C:\Program Files\Aurelien Software\Powershell\Installer.Prerequisites\rewrite_amd64.msi' '/qn' -PassThru | Wait-Process
RUN Start-Process 'C:\Program Files\Aurelien Software\Powershell\Installer.Prerequisites\requestRouter_amd64.msi' '/qn' -PassThru | Wait-Process

#Run the script to set IIS configuration
RUN C:\Scripts\SettingsIIS.ps1

#Enable APIs
RUN C:\Scripts\EnableAPIs.ps1

#Delete Prerequisites folder
RUN Remove-Item -Path 'C:\Program Files\Aurelien Software' -Force -Recurse


