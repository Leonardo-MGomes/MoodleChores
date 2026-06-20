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
    $out = python ./powershell-connector.py get-course ($Credentials.session | ConvertFrom-SecureString -AsPlainText) $CourseId
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
    Get-IndexedCourses | Where-Object { $_.Id -eq $CourseId }
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
