# Force les associations navigateur vers Firefox pour l'utilisateur COURANT.
# Lance par une tache planifiee au logon (contexte user interactif -> le hash
# UserChoice est valide, contrairement a une execution WinRM en logon reseau).
#
# http / https / .pdf peuvent etre bloques par UCPD (User Choice Protection
# Driver, Win11 24H2+) : les echecs sont ignores (try/catch). Si UCPD est
# desactive, ces associations passent aussi automatiquement au prochain logon.
#
# Deploye par le role windows_gaming (console_ux.yml) a cote de SFTA.ps1.

$ErrorActionPreference = 'Continue'
$sfta = Join-Path $PSScriptRoot 'SFTA.ps1'
if (-not (Test-Path $sfta)) { $sfta = 'C:\ProgramData\ansible-tools\SFTA.ps1' }
. $sfta

# ProgId Firefox lus dynamiquement (jamais code en dur : survivent a une reinstall)
$html = (Get-ChildItem 'HKLM:\SOFTWARE\Classes' | Where-Object { $_.PSChildName -like 'FirefoxHTML-*' } | Select-Object -First 1).PSChildName
$url  = (Get-ChildItem 'HKLM:\SOFTWARE\Classes' | Where-Object { $_.PSChildName -like 'FirefoxURL-*' } | Select-Object -First 1).PSChildName

if ($html) {
  foreach ($e in '.html', '.htm', '.shtml', '.xht', '.xhtml', '.pdf') {
    try { Set-FTA $html $e } catch { }   # .pdf peut echouer (UCPD)
  }
}
if ($url) {
  foreach ($p in 'http', 'https', 'ftp') {
    try { Set-PTA $url $p } catch { }     # http/https peuvent echouer (UCPD)
  }
}
