# Sync-MoodleResources.ps1
# Synchronizes local course folders with Moodle resources based on the local index.

param (
    [string]$RootPath = "$HOME/Documents/BBB Moodle Material",
    [string]$MoodleBaseUrl = "https://moodle.bbbaden.ch"
)

# Dot-source the gatherer to use its functions
. .\MoodleInfoGather.ps1

function Get-MoodleSessionHeader {
    param ([psobject]$Credentials)
    $sessionValue = $Credentials.session | ConvertFrom-SecureString -AsPlainText
    return @{"Cookie" = "MoodleSession=$sessionValue"}
}

function Sanitize-FileName {
    param ([string]$FileName)
    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    foreach ($char in $invalidChars) {
        $FileName = $FileName.Replace($char, '_')
    }
    return $FileName
}

function Sync-MoodleResource {
    param (
        [psobject]$Resource,
        [string]$BaseUrl,
        [hashtable]$SessionHeader,
        [string]$TopicPath
    )

    $url = "$BaseUrl/mod/resource/view.php?id=$($Resource.Id)"

    try {
        $webResourceHeaders = Invoke-WebRequest -Uri $url -Headers $SessionHeader -Method Head -ErrorAction Stop

        if ($webResourceHeaders.StatusCode -ne 200) {
            Write-Host "Resource gave unexpected status code: $($webResourceHeaders.StatusCode)" -ForegroundColor Yellow
            return
        }

        $contentType = $webResourceHeaders.Headers["Content-Type"]
        $contentDisp = $webResourceHeaders.Headers["Content-Disposition"]

        if ($contentType -notlike "*text/html*" -and $contentDisp) {
            # It's a download redirect
            if ([string]$contentDisp -match 'filename="?([^";]*)?"?') {
                $resourceName = [uri]::UnescapeDataString($matches[1])
            } else {
                $resourceName = $Resource.Name
            }

            $resourceName = Sanitize-FileName $resourceName
            $destPath = Join-Path $TopicPath $resourceName

            if (Test-Path $destPath) {
                Write-Host "Resource already exists: $resourceName. Skipping." -ForegroundColor Gray
                return
            }

            Write-Host "Downloading Resource: $resourceName" -ForegroundColor White
            Invoke-WebRequest -Uri $url -Headers $SessionHeader -OutFile $destPath -ErrorAction Stop
        } else {
            # It's a webpage
            $linkPath = Join-Path $TopicPath "$($Resource.Name).url"

            if (Test-Path $linkPath) {
                Write-Host "URL link already exists: $($Resource.Name). Skipping." -ForegroundColor Gray
                return
            }

            Write-Host "Resource $($Resource.Name) is a Webpage, creating .url link." -ForegroundColor White
            Set-Content -LiteralPath $linkPath -Value "[InternetShortcut]`r`nURL=$url"
        }
    } catch {
        Write-Host "Failed to process resource $($Resource.Name): $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Write-Host "Starting Moodle synchronization..." -ForegroundColor Cyan

# 1. Authentication and Session Management
$credFile = "MoodleCredentials.xml"
if (-not (Test-Path $credFile)) {
    Write-Error "Credentials file $credFile not found. Please run Set-MoodleCredentials first."
    exit 1
}

$credentials = Get-MoodleCredentials
$needsAuth = $false

# Pre-fetch indexed courses to avoid repeated calls
$indexedCourses = Get-IndexedCourses

# Check if credentials file is older than 24 hours
$lastUpdate = (Get-Item $credFile).LastWriteTime
if ((Get-Date) - $lastUpdate -gt (New-TimeSpan -Days 1)) {
    Write-Host "Credentials are older than 24 hours. Updating session..." -ForegroundColor Yellow
    $needsAuth = $true
}

# Check for folders that are not yet indexed
if (Test-Path $RootPath) {
    $folders = Get-ChildItem -Path $RootPath -Directory
    foreach ($f in $folders) {
        if ($f.Name -match '^(\d+)') {
            $courseNum = [int]$matches[1]
            if (-not ($indexedCourses | Where-Object { $_.CourseNumber -eq $courseNum })) {
                Write-Host "New unindexed course folder detected: $($f.Name). Updating index..." -ForegroundColor Yellow
                Sync-IndexedCourses -Credentials $credentials
                $indexedCourses = Get-IndexedCourses # Since we're indexing new Courses anyways
                break
            }
        }
    }
}

# Final session check
if (-not (Test-MoodleSession -Credentials $credentials)) {
    Write-Host "Session is invalid. Updating..." -ForegroundColor Yellow
    $needsAuth = $true
}

if ($needsAuth) {
    Write-Host "Authenticating and updating credentials..." -ForegroundColor Magenta
    Update-MoodleCredentials -Credentials $credentials
    $credentials = Get-MoodleCredentials
    # Refresh index after authentication in case new courses were added/updated
    $indexedCourses = Get-IndexedCourses
} else {
    Write-Host "Session is valid and recent. Skipping login." -ForegroundColor Green
}

# 2. Synchronization Loop
if (-not (Test-Path $RootPath)) {
    Write-Error "Root path $RootPath does not exist."
    exit 1
}

$sessionHeader = Get-MoodleSessionHeader -Credentials $credentials
$folders = Get-ChildItem -Path $RootPath -Directory

foreach ($folder in $folders) {
    if ($folder.Name -notmatch '^(\d+)') { continue }

    # Extract course number
    if ($folder.Name -match '^(\d+)') {
        $courseNum = [int]$matches[1]
    } else { continue }

    $course = $indexedCourses | Where-Object { $_.CourseNumber -eq $courseNum }

    if ($null -eq $course) {
        Write-Host "Course $courseNum not found in index. Skipping folder $($folder.Name)." -ForegroundColor Gray
        continue
    }

    # Ensure folder name is correct: "Number - Title"
    $expectedName = "$($course.CourseNumber) - $($course.Title)"
    $currentCoursePath = $folder.FullName

    if ($folder.Name -ne $expectedName) {
        Write-Host "Updating folder name: $($folder.Name) -> $expectedName" -ForegroundColor Yellow
        try {
            Rename-Item -Path $currentCoursePath -NewName $expectedName -Force -ErrorAction Stop
            $currentCoursePath = Join-Path $folder.Parent.FullName $expectedName
        } catch {
            Write-Host "Failed to rename folder $($folder.Name): $($_.Exception.Message)" -ForegroundColor Yellow
            # Continue with original path if rename fails
        }
    }

    Write-Host "Synchronizing Course: $($course.Title) (ID: $($course.Id))" -ForegroundColor White

    foreach ($topic in $course.Topics) {
        if ($null -eq $topic) { continue }

        $topicPath = Join-Path $currentCoursePath ($topic.Title -replace ':$', '')
        if (-not (Test-Path $topicPath)) {
            New-Item -ItemType Directory -Path $topicPath -Force | Out-Null
        }

        foreach ($resource in $topic.Resources) {
            if ($null -eq $resource) { continue }
            if ($resource.Type -ne 'resource') { continue }

            Sync-MoodleResource -Resource $resource -BaseUrl $MoodleBaseUrl -SessionHeader $sessionHeader -TopicPath $topicPath
        }
    }
}

Write-Host "Synchronization complete." -ForegroundColor Cyan
