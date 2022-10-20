$VerbosePreference='Continue'

$FLEET_URL = $env:FLEET_URL
$FLEET_ENROLLMENT_TOKEN = $env:FLEET_ENROLLMENT_TOKEN

#Get full path of the agent directory
$AGENT_PATH = (Get-ChildItem C:\ -Filter "elastic-agent*" -Directory).Fullname

#Enroll the agent to the fleet cloud server
Start-Process "$($AGENT_PATH)\elastic-agent.exe" -ArgumentList "enroll --url=$($FLEET_URL) --enrollment-token=$($FLEET_ENROLLMENT_TOKEN) --insecure --force" -NoNewWindow 

#Run the agent and keep the container running
Start-Process "$($AGENT_PATH)\elastic-agent.exe" -ArgumentList "run" -NoNewWindow -Wait
