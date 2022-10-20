
#Connect to your Azure tenant
#Connect-AzAccount

#Choose and select the properly subcription (ID)
#-----
#Get-AzSubscription
#Select-AzSubscription -Subscription

#Select the properly WorkSpace ID
#-----
#Get-AzOperationalInsightsWorkspace
#$WorkspaceID = {yourWorkspaceID

$i = 0
$resourceID = Get-AzResource -ResourceType Microsoft.Sql/servers/databases #Get all Databases into the selected subscription
$count = $resourceID.Count #Count the total databases 

#Enable AzureDiagnostics for all your databases and send it to the Workspace selected
while ($i -le $count){
    
    $value = $resourceID.ResourceID.GetValue($i)
    $i++
    Set-AzDiagnosticSetting -ResourceId $value -WorkspaceId $WorkspaceId -Enabled $true
}

