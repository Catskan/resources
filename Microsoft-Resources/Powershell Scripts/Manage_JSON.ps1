function SettingsAppSettings.json {

    $FileParsed = Get-Content -Raw -Path "C:\Users\Aurel\AppData\Roaming\Bitwarden\data.json" | ConvertFrom-Json

    $FileParsed.global.environmentUrls.base = "{{ bitwarden_server_url }}"
    $FileParsed.global.rememberedEmail = "{{ bitwarden_email }}"
    
    $FileParsed | ConvertTo-Json | Out-File "C:\Users\Aurel\AppData\Roaming\Bitwarden\data.json" -Force