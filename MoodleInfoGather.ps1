#Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
./.venv/bin/Activate.ps1

function Get-MoodleCredentials {
    Import-Clixml -Path MoodleCredentials.xml
}

function Set-MoodleCredentials {
    param (
        [string]$username,
        [SecureString]$password
    )
    $session = (python ./powershell-connector.py login $username ($password | ConvertFrom-SecureString -AsPlainText)) | ConvertTo-SecureString -AsPlainText
    $moodle_credentials = @{username=$username; password=$password; session=$session}
    Export-Clixml -Path MoodleCredentials.xml -InputObject $moodle_credentials
}

function Update-MoodleCredentials {
    param (
        [psobject]$moodle_credentials
    )
    Set-MoodleCredentials $moodle_credentials.username $moodle_credentials.password
}

function Test-MoodleSession {
    param (
        [PSObject]$moodle_credentials
    )
    $out = python ./powershell-connector.py sessionvalid ($moodle_credentials.session | ConvertFrom-SecureString -AsPlainText)
    [System.Convert]::ToBoolean($out)
}
