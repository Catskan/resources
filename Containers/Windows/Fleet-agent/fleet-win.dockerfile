FROM mcr.microsoft.com/windows/servercore:ltsc2019

#Download the official image elastic-agent binaries
ADD "https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-#{FLEET_AGENT_VERSION}#-windows-x86_64.zip" "C:/Temp/"

#COPY the entrypoint script to C:\
COPY ./containers/Fleet-agent/entrypoint-script.ps1 C:/

#Extract the elastic-agent files to C:\
RUN powershell -command Expand-Archive -Path "C:/Temp/elastic-agent-#{FLEET_AGENT_VERSION}#-windows-x86_64.zip" -DestinationPath "C:/" -Force

ENTRYPOINT ["powershell.exe", "C:/entrypoint-script.ps1"]
