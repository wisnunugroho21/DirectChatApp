param([string]$SettingsPath = "$PSScriptRoot/backend/appsettings.json")
$ErrorActionPreference = 'Stop'
$config = (Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json).Firebase.Web
if (-not $config.ApiKey -or -not $config.AppId -or -not $config.ProjectId) {
    throw 'Fill Firebase.Web in the backend settings before generating the public web configuration.'
}
$publicConfig = @{
    apiKey = $config.ApiKey
    appId = $config.AppId
    projectId = $config.ProjectId
    messagingSenderId = $config.MessagingSenderId
    authDomain = $config.AuthDomain
    storageBucket = $config.StorageBucket
}
$output = 'self.FIREBASE_CONFIG = ' + ($publicConfig | ConvertTo-Json -Compress) + ';'
Set-Content -LiteralPath "$PSScriptRoot/flutter_app/web/firebase-config.js" -Value $output -Encoding utf8
Write-Output 'Public Firebase web configuration generated. Rebuild Flutter web.'

