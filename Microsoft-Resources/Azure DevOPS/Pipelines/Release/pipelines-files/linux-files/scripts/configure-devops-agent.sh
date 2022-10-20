echo $@echo "start" 
cd /home/azureuser 
mkdir agent 
cd agent 
AGENTRELEASE="$(curl -s https://api.github.com/repos/Microsoft/azure-pipelines-agent/releases/latest | grep -oP '"tag_name": "v\K(.*)(?=")')" 
AGENTURL="https://vstsagentpackage.azureedge.net/agent/${AGENTRELEASE}/vsts-agent-linux-x64-${AGENTRELEASE}.tar.gz" 
echo "Release "${AGENTRELEASE}" appears to be latest" 
echo "Downloading..." 
wget -O agent.tar.gz ${AGENTURL} 
tar zxvf agent.tar.gz 
chmod -R 777 . 
echo "extracted" 
./bin/installdependencies.sh 
echo "dependencies installed" 
sudo -u azureuser ./config.sh --unattended --url '#{AZ_DEVOPS_URL}#' --auth pat --token '#{AZ_DEVOPS_PAT}#' --pool '#{agent-pool-name}#' --agent '#{AGENT_NAME}#' --acceptTeeEula --work ./_work --runAsService 
echo "configuration done" 
sudo ./svc.sh install azureuser
echo "service installed" 
sudo ./svc.sh start 
echo "service started" 
echo "agent config done" 
exit 0'