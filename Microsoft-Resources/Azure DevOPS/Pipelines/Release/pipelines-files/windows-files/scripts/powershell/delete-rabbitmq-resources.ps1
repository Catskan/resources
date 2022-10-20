#RMQ Cluster Information
$clusterName = '#{rmqCluster}#'
$admLogin = '#{rmqInstanceAdminUser}#'
$admPass = '#{rmqInstanceAdminPwd}#'

#RMQ Elements to Delete
$appUser = '#{rmqUser}#'
$vhost = '#{rmqVhost}#'

#Credentials Creation
$Creds = New-Object PSCredential -ArgumentList ([pscustomobject] @{ 
    UserName = $admLogin;
    Password = (ConvertTo-SecureString -AsPlainText -Force -String $admPass)[0]
})

#RMQ get elements info, if not exists, response value is stored in the variables (ex. 404)
try {
    $vhostInfo = Invoke-RestMethod -Credential $creds -ContentType "application/json" -Method Get -uri https://$clusterName/api/vhosts/$vhost -Verbose
} catch {
    $vhostInfo = $_.Exception.Response.StatusCode.value__
}

try {
    $appUserInfo = Invoke-RestMethod -Credential $creds -ContentType "application/json" -Method Get -uri https://$clusterName/api/users/$appUser -Verbose
} catch {
    $appUserInfo = $_.Exception.Response.StatusCode.value__
}

#checks if the info of vhost/user exists, if not, it means that the vhost/user doesn't exists
if($vhostinfo -ne 404){ 
    Invoke-RestMethod -Credential $creds -ContentType "application/json" -Method Delete  -uri https://$clusterName/api/vhosts/$vhost -Verbose
} else{
    Write-Output "the vhost is already deleted or doesn't exists"
}

if($appUserInfo -ne 404){ 
    Invoke-RestMethod -Credential $creds -ContentType "application/json" -Method Delete -uri https://$clusterName/api/users/$appUser -Verbose
} else{
    Write-Output "the user is already deleted or doesn't exists"
}