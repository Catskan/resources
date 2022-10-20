$rmquser = '#{rmqUser}#'
$rmqpass = '#{rmqPWD}#'
$rmqvhost = '#{rmqVhost}#'
$rmqcluster = '#{rmqCluster}#'
$instanceUser = '#{rmqInstanceAdminUser}#'
$instancePass = '#{rmqInstanceAdminPwd}#'
$pair = "$($instanceUser):$($instancePass)"
$encodedCredentials = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))
$headers = @{ Authorization = "Basic $encodedCredentials" }

$userbody = @{
        'password' = "$rmqpass"
        'tags' = "$rmquser"
} | ConvertTo-Json

$permissionsbody = @{
                'configure' = '.*'
                'write' = '.*'
                'read' = '.*'
            } | ConvertTo-Json

$vhostUrl = "https://$rmqcluster/api/vhosts/$rmqvhost"
$userUrl = "https://$rmqcluster/api/users/$rmquser"
$permissionsUrl = "https://$rmqcluster/api/permissions/$rmqvhost/$rmquser"

#create vhost
Invoke-WebRequest -Uri $vhostUrl -Method put -Headers $headers
start-sleep 1

#create user
Invoke-WebRequest -Uri $userUrl -Method put -Headers $headers -ContentType "application/json" -Body $userbody
start-sleep 1

#create permissions for the user to access vhost 
Invoke-WebRequest -Uri $permissionsUrl -Method put -Headers $headers -ContentType "application/json" -Body $permissionsbody