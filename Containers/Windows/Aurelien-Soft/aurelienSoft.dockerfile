#escape=`
#Argument passed in build task to populate FROM instruction with the gizmo-requirements to use
ARG requirement_repository
FROM $requirement_repository

#Begin working directory in C:\
WORKDIR C:\

#Download LogMonitor.exe to save logs output the container save it into C:/LogMonitor directory
ADD "https://github.com/microsoft/windows-container-tools/releases/download/v1.1/LogMonitor.exe" "C:/LogMonitor/"
ARG programFiles="C:\Program Files\Aurelien Software"
#Copy Gizmo Program Files directory
ARG srcProgramFiles="./AurelienSoft_ProgramFiles/"
ARG dstProgramFiles="C:/Program Files"
COPY ${srcProgramFiles} ${dstProgramFiles}

#Copy Gizmo ProgramData directory
ARG srcProgramData="./AurelienSoft_ProgramData/"
ARG dstProgramData="C:/ProgramData"
COPY ${srcProgramData} ${dstProgramData}

#COPY the directory with all scripts used by Gizmo image
COPY ./resouces/Containers/Aurelien-Soft/Scripts C:/Scripts

#Copy the logmonitor configuration file
COPY ./resouces/Containers/Aurelien-Soft/Modules/LogMonitorConfig.json C:/LogMonitor/

#Set ports to listen inside the docker network
EXPOSE 80

#Enable Powershell Shell
SHELL ["powershell", "-command"]

#Set the IIS service to Manual
RUN Set-Service -Name W3SVC -StartupType "Manual"

#Execute Powershell scripts to finished Gizmo configuration
RUN C:\Scripts\ServicesACLs.ps1

RUN New-WebVirtualDirectory -Name 'Downloads' -Site 'Default Web Site' -PhysicalPath 'C:\ProgramData\GSX Solutions\Downloads'  -Force
RUN Set-WebConfiguration system.webServer/directoryBrowse -PSPath 'IIS:' -Location 'Default Web Site' -Value @{enabled='False'}

#Start ServiceMonitor to take container running (Microsoft official solution)
ENTRYPOINT ["C:\\LogMonitor\\LogMonitor.exe", "powershell", "C:/Scripts/SettingsGizmo.ps1;"]
