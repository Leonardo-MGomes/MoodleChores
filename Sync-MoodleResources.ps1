# Sync-MoodleResources.ps1
# Synchronizes local course folders with Moodle resources based on the local index.

# --- Configuration ---
$rootPath = "$HOME/Documents/BBB Moodle Material" # Change this to your desired root path
$moodleBaseUrl = "https://moodle.bbbaden.ch"
# -----------------------

# Dot-source the gatherer to use its functions
. .\MoodleInfoGather.ps1

Write-Host "Starting Moodle synchronization..." -ForegroundColor Cyan

# 1. Authentication and Session Management
$credFile = "MoodleCredentials.xml"
if (-not (Test-Path $credFile)) {
    Write-Error "Credentials file $credFile not found. Please run Set-MoodleCredentials first."
    exit 1
}

$credentials = Get-MoodleCredentials
$needsAuth = $false

# Check if credentials file is older than 24 hours
$lastUpdate = (Get-Item $credFile).LastWriteTime
if ((Get-Date) - $lastUpdate -gt (New-TimeSpan -Days 1)) {
    Write-Host "Credentials are older than 24 hours. Updating session..." -ForegroundColor Yellow
    $needsAuth = $true
}

# Check for folders that are not yet indexed
if (Test-Path $rootPath) {
    $folders = Get-ChildItem -Path $rootPath -Directory
    foreach ($f in $folders) {
        # Expecting folder name: "CourseNumber - Title"
        if ($f.Name -match '^(\d+)\s*-') {
            $courseNum = [int]$matches[1]
            # We check if this course number is in the indexed courses
            $indexedCourses = Get-IndexedCourses
            if (-not ($indexedCourses | Where-Object { $_.CourseNumber -eq $courseNum })) {
                Write-Host "New unindexed course folder detected: $($f.Name). Updating index..." -ForegroundColor Yellow
                $needsAuth = $true
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
    $credentials = Get-MoodleCredentials # Refresh local object
} else {
    Write-Host "Session is valid and recent. Skipping login." -ForegroundColor Green
}

# 2. Synchronization Loop
if (-not (Test-Path $rootPath)) {
    Write-Error "Root path $rootPath does not exist."
    exit 1
}

$folders = Get-ChildItem -Path $rootPath -Directory
foreach ($folder in $folders) {
    # Match "CourseNumber - Title"
    if ($folder.Name -match '^(\d+)\s*-') {
        $courseNum = [int]$matches[1]
        $courses = Get-IndexedCourses
        $course = $courses | Where-Object { $_.CourseNumber -eq $courseNum }

        if ($null -eq $course) {
            Write-Host "Course $courseNum not found in index. Skipping folder $($folder.Name)." -ForegroundColor Gray
            continue
        }

        Write-Host "Synchronizing Course: $($course.Title) (ID: $($course.Id))" -ForegroundColor White

        # Iterate through topics and resources
        foreach ($topic in $course.Topics) {
            if ($null -eq $topic) { continue }

            # Ensure topic folder exists
            $topicPath = Join-Path $folder.FullName ($topic.Title -replace ':$', '') # The replace is here for special characters like ':' which are in Moodle Topics but not allowed as folder names
            if (-not (Test-Path $topicPath)) {
                New-Item -ItemType Directory -Path $topicPath -Force | Out-Null
            }

            foreach ($resource in $topic.Resources) {
                if ($null -eq $resource) { continue }
                if ($resource.Type -ne 'resource') { continue }

                $url = "$moodleBaseUrl/mod/resource/view.php?id=$($resource.Id)"
                $sessionValue = $credentials.session | ConvertFrom-SecureString -AsPlainText
                $sessionHeader = @{"Cookie" = "MoodleSession=$sessionValue"}

                try {
                    $webResourceHeaders = Invoke-WebRequest -Uri $url -Headers $sessionHeader -Method Head -ErrorAction Stop

                    if ($webResourceHeaders.StatusCode -eq 200) {
                        $contentType = $webResourceHeaders.Headers["Content-Type"]
                        $contentDisp = $webResourceHeaders.Headers["Content-Disposition"]

                        if ($contentType -notlike "*text/html*" -and $contentDisp) {
                            # It's a download redirect
                            if ([string]$contentDisp -match 'filename="?([^";]*)?"?') {
                                $resourceName = [uri]::UnescapeDataString($matches[1])
                            } else {
                                $resourceName = $resource.Name
                            }

                            # Sanitize filename for Windows
                            $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
                            foreach ($char in $invalidChars) {
                                $resourceName = $resourceName.Replace($char, '_')
                            }

                            Write-Host "Downloading Resource: $resourceName" -ForegroundColor White
                            Invoke-WebRequest -Uri $url -Headers $sessionHeader -OutFile (Join-Path $topicPath $resourceName) -ErrorAction Stop
                        }
                        else {
                            # It's a webpage
                            Write-Host "Resource is a Webpage, creating .url link." -ForegroundColor White
                            $linkPath = Join-Path $topicPath "$($resource.Name).url"
                            Set-Content -LiteralPath $linkPath -Value "[InternetShortcut]`r`nURL=$url"
                        }
                    } else {
                        Write-Host "Resource gave unexpected status code: $($webResourceHeaders.StatusCode)" -ForegroundColor Yellow
                    }
                } catch {
                    Write-Host "Failed to process resource $($resource.Name): $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
        }
    }
}

Write-Host "Synchronization complete." -ForegroundColor Cyan
