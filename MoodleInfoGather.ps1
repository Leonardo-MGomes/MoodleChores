#Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
./.venv/Scripts/Activate.ps1

function Get-MoodleCredentials {
    <#
    .SYNOPSIS
        Loads Moodle credentials from the XML.
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param ()
    Import-Clixml -Path MoodleCredentials.xml
}

function Set-MoodleCredentials {
    <#
    .SYNOPSIS
        Authenticates with Moodle and saves credentials to the XML.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$Username,
        [Parameter(Mandatory)] [SecureString]$Password
    )
    $session = (python ./powershell-connector.py login $Username ($Password | ConvertFrom-SecureString -AsPlainText)) | ConvertTo-SecureString -AsPlainText
    Export-Clixml -Path MoodleCredentials.xml -InputObject @{username = $Username; password = $Password; session = $session}
}

function Update-MoodleCredentials {
    <#
    .SYNOPSIS
        Re-authenticates with Moodle and updates the session in the XML.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [psobject]$Credentials
    )
    $Credentials.session = (python ./powershell-connector.py login $Credentials.username ($Credentials.password | ConvertFrom-SecureString -AsPlainText)) | ConvertTo-SecureString -AsPlainText
    Export-Clixml -Path MoodleCredentials.xml -InputObject $Credentials
}

function Test-MoodleSession {
    <#
    .SYNOPSIS
        Returns $true if the session cookie stored in the given credentials is still valid.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)] [psobject]$Credentials
    )
    [System.Convert]::ToBoolean((python ./powershell-connector.py sessionvalid ($Credentials.session | ConvertFrom-SecureString -AsPlainText)))
}
