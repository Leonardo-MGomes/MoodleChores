<# Scriptname: MoodleInfoGather.ps1
Author: Leonardo Miranda Gomes
Date: 2026-06-22
Version: 1.0
Description: Funktionen-Bibliothek zur Kapselung des Python-Connectors und der XML-Credential-Verwaltung.
#>

$installPackages = $false
if (-not (Test-Path -Path ".venv")) {
    (python -m venv .venv)
    $installPackages = $true
}
if ($IsWindows) {
    $venvPath = "./.venv/Scripts/Activate.ps1"
} elseif ($IsLinux || $IsMacOS) {
    $venvPath = "./.venv/bin/Activate.ps1"
}

. $venvPath

if ($installPackages) {
    (pip install -r ./requirements.txt)
}

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
    $out = (python ./powershell-connector.py login $Username ($Password | ConvertFrom-SecureString -AsPlainText)) | ConvertFrom-Json
    $session = $out.session | ConvertTo-SecureString -AsPlainText
    $sesskey = $out.sesskey | ConvertTo-SecureString -AsPlainText
    Export-Clixml -Path MoodleCredentials.xml -InputObject @{username = $Username; password = $Password; session = $session; sesskey = $sesskey}
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
    $out = (python ./powershell-connector.py login $Credentials.username ($Credentials.password | ConvertFrom-SecureString -AsPlainText)) | ConvertFrom-Json
    $Credentials.session = $out.session | ConvertTo-SecureString -AsPlainText
    $Credentials.sesskey = $out.sesskey | ConvertTo-SecureString -AsPlainText
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
function Get-MoodleCourse {
    <#
    .SYNOPSIS
        Scrapes a course from Moodle and returns it as a PowerShell object.
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param (
        [Parameter(Mandatory)] [psobject]$Credentials,
        [Parameter(Mandatory)] [int]$CourseId
    )
    $out = (python ./powershell-connector.py get-course ($Credentials.session | ConvertFrom-SecureString -AsPlainText) $CourseId)
    Write-Verbose $out
    $out | ConvertFrom-Json
}

function Get-IndexedCourses {
    <#
    .SYNOPSIS
        Returns all courses currently indexed in the local SQLite database.
    #>
    [CmdletBinding()]
    [OutputType([psobject[]])]
    param ()
    (python ./powershell-connector.py db-courses) | ConvertFrom-Json
}

function Get-IndexedCourse {
    <#
    .SYNOPSIS
        Returns a single course from the local database by its Moodle course ID.
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param (
        [Parameter(Mandatory)] [int]$CourseId
    )
    Get-IndexedCourses | Where-Object { $_.Id -eq $CourseId } # Getting all the courses and filtering is worse than just using the connector for the one course; fix later
}

function Test-IndexedCourse {
    <#
    .SYNOPSIS
        Returns $true if the given course ID is already indexed in the local database.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)] [int]$CourseId
    )
    [System.Convert]::ToBoolean((python ./powershell-connector.py db-check-course $CourseId))
}

function Add-IndexedCourse {
    <#
    .SYNOPSIS
        Scrapes a course from Moodle, saves it to the local database, and returns it as a PowerShell object.
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param (
        [Parameter(Mandatory)] [psobject]$Credentials,
        [Parameter(Mandatory)] [int]$CourseId
    )
    (python ./powershell-connector.py db-index-course ($Credentials.session | ConvertFrom-SecureString -AsPlainText) $CourseId) | ConvertFrom-Json
}

function Sync-IndexedCourses {
    <#
    .SYNOPSIS
        Automatically updates the local index by scraping all courses the user is enrolled in.
    #>
    [CmdletBinding()]
    [OutputType([psobject[]])]
    param (
        [Parameter(Mandatory)] [psobject]$Credentials
    )
    $out = (python ./powershell-connector.py db-sync ($Credentials.session | ConvertFrom-SecureString -AsPlainText) ($Credentials.sesskey | ConvertFrom-SecureString -AsPlainText)) | ConvertFrom-Json
    return $out
}
