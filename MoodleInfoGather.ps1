#Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
./MoodleDownloader/venv/bin/Activate.ps1

function Get-MoodleCredentials {
    Import-Clixml -Path MoodleCredentials.xml
}

function New-MoodleCredentials {
    param (
        [string]$username,
        [SecureString]$password
    )
    $session = (python ./powershell-connector.py login $username $password) | ConvertTo-SecureString -AsPlainText
    $moodle_credentials = @{username=$username; password=$password; session=$session}
    Export-Clixml -Path MoodleCredentials.xml -InputObject $moodle_credentials
}

function Test-MoodleSession {
    python ./powershell-connector.py sessionvalid ($moodle_credentials.session)
}

New-MoodleCredentials "user" ("password" | ConvertTo-SecureString -AsPlainText)
Get-MoodleCredentials
