$Services = Get-Service gsx*
foreach ($service in $Services) 
{
   $SvcName = $service.Name
   write-host "Enabling service $SvcName"
   CMD /C "sc sdset $SvcName D:(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;IU)(A;;RPWPDTRC;;;BU)"   
}