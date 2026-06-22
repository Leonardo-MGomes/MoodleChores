@echo off
echo Starting Moodle Resource Synchronization...
pwsh -ExecutionPolicy Bypass -File ".\Sync-MoodleResources.ps1"
echo Sync process finished.
pause
