function SettingsAppSettings.json {

    $FileParsed = Get-Content -Raw -Path "C:\Users\Aurel\AppData\Roaming\Bitwarden\data.json" | ConvertFrom-Json

    $FileParsed.global.rememberedEmail = "{{ bitwarden_email }}"
    $FileParsed.AppSettings.DbConfig.Database = $SQL_Database
    $FileParsed.AppSettings.DbConfig.UseWindowsCredentials = $SQL_UseWindowsCredentials
    $FileParsed.AppSettings.DbConfig.UserID = $SQL_Username
    $FileParsed.AppSettings.DbConfig.Password = $SQL_Password_Encoded

    $FileParsed.AppSettings.BusConfig.Hostname = $RMQ_Hostname
    $FileParsed.AppSettings.BusConfig.VirtualHostname = $RMQ_Vhost
    $FileParsed.AppSettings.BusConfig.ExchangeName = "robot-manager"
    $FileParsed.AppSettings.BusConfig.Port = $RMQ_Port
    $FileParsed.AppSettings.BusConfig.Username = $RMQ_Username
    $FileParsed.AppSettings.BusConfig.Password = $RMQ_Password_Encoded
    $FileParsed.AppSettings.BusConfig.UseSsl = $RMQ_SSL

    $FileParsed | ConvertTo-Json | Out-File "$InstallFolderPath\GSX-Web-UI\WebAPI\appsettings.json" -Force