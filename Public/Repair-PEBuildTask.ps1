function Repair-PEBuildTask {
    <#
    .SYNOPSIS
    Converts PEBuild Tasks of OSDBuilder 19.1.3.0 and older to the current Task format

    .DESCRIPTION
    New-PEBuild needs Tasks of version 19.1.4.0 or newer. Repair-PEBuildTask selects the OSMedia of every old Task in Out-GridView,
    saves the original Task in Tasks\Repair and writes the Task in the current format.

    .EXAMPLE
    Repair-PEBuildTask
    #>
    [CmdletBinding()]
    param ()
    Begin {
        #=================================================
        #   Header
        #=================================================
        #   Write-Host '========================================================================================' -ForegroundColor DarkGray
        #   Write-Host -ForegroundColor Green "$($MyInvocation.MyCommand.Name) BEGIN"
        #=================================================
        #   Get-OSDBuilder
        #=================================================
        Get-OSDBuilder -CreatePaths -HideDetails
        #=================================================
        Write-Verbose '19.1.6 Gather All PEBuildTask'
        #=================================================
        #Tasks up to 19.1.3.0 use the old format (MediaName, AddWindowsDriver ...) that New-PEBuild cannot read
        $PEBuildTask = @(Get-ChildItem -Path "$SetOSDBuilderPathTasks" -Filter 'PEBuild*.json' -File -ErrorAction SilentlyContinue | Where-Object {
            $TaskVersion = (Get-Content -Path $_.FullName -Raw | ConvertFrom-Json).TaskVersion -as [System.Version]
            $TaskVersion -and ($TaskVersion -le [System.Version]'19.1.3.0')
        })
        if ($PEBuildTask.Count -eq 0) {Write-Warning "No PEBuild Task needs a Repair"}
    }
    
    Process {
        #Write-Host '========================================================================================' -ForegroundColor DarkGray
        Write-Host "$($MyInvocation.MyCommand.Name) PROCESS"

        foreach ($Item in $PEBuildTask) {
            $TaskFile = Get-Item -Path "$($Item.FullName)" | Select-Object -Property *
            Write-Warning "Repair Required: $($Item.FullName)"

            #=================================================
            Write-Verbose 'Read Task'
            #=================================================
            $Task = @()
            $Task = Get-Content "$($Item.FullName)" -Raw | ConvertFrom-Json
    
            Write-Host "Select the OSMedia that will be used with this PEBuild Task"
            Write-Host "Previous OSMedia: $($Task.MediaName)"
            $OSMedia = Get-OSMedia
            
            if ($Task.MediaName -like "*x64*") {$OSMedia = $OSMedia | Where-Object {$_.Arch -eq 'x64'}}
            if ($Task.MediaName -like "*x86*") {$OSMedia = $OSMedia | Where-Object {$_.Arch -eq 'x86'}}
            if ($Task.MediaName -like "*1511*") {$OSMedia = $OSMedia | Where-Object {$_.ReleaseId -eq '1511'}}
            if ($Task.MediaName -like "*1607*") {$OSMedia = $OSMedia | Where-Object {$_.ReleaseId -eq '1607'}}
            if ($Task.MediaName -like "*1703*") {$OSMedia = $OSMedia | Where-Object {$_.ReleaseId -eq '1703'}}
            if ($Task.MediaName -like "*1709*") {$OSMedia = $OSMedia | Where-Object {$_.ReleaseId -eq '1709'}}
            if ($Task.MediaName -like "*1803*") {$OSMedia = $OSMedia | Where-Object {$_.ReleaseId -eq '1803'}}
            if ($Task.MediaName -like "*1809*") {$OSMedia = $OSMedia | Where-Object {$_.ReleaseId -eq '1809'}}

            $OSMedia = $OSMedia | Out-GridView -OutputMode Single -Title "$($Task.TaskName): Select the OSMedia used with this PEBuild Task"
    
            if ($null -eq $OSMedia) {
                Write-Warning "OSMedia was not selected, skipping $($Item.FullName)"
                Continue
            }

            Write-Host "Selected $($OSMedia.Name)"

            #=================================================
            Write-Verbose '19.1.5 Create PEBuild Task'
            #=================================================
            $NewTask = [ordered]@{
                "TaskType" = 'PEBuild'
                "TaskName" = [string]$Task.TaskName;
                "TaskVersion" = [string]$global:GetOSDBuilder.VersionOSDBuilder;
                "TaskGuid" = [string]$(New-Guid);
    
                "OSMFamily" = [string]$OSMedia.OSMFamily;
                "OSMGuid" = [string]$OSMedia.OSMGuid;
                "Name" = [string]$OSMedia.Name;
                "ImageName" = [string]$OSMedia.ImageName;
                "Arch" = [string]$OSMedia.Arch;
                "ReleaseId" = [string]$($OSMedia.ReleaseId);
                "UBR" = [string]$OSMedia.UBR;
                "Languages" = [string[]]$OSMedia.Languages;
                "EditionId" = [string]$OSMedia.EditionId;
                "InstallationType" = [string]$OSMedia.InstallationType;
                "MajorVersion" = [string]$OSMedia.MajorVersion;
                "Build" = [string]$OSMedia.Build;
                "CreatedTime" = [datetime]$OSMedia.CreatedTime;
                "ModifiedTime" = [datetime]$OSMedia.ModifiedTime;

                "WinPEOutput" = [string]$Task.PEOutput;
                "CustomName" = [string]'';
                "MDTDeploymentShare" = [string]$Task.DeploymentShare;
                "ScratchSpace" = [string]$Task.ScratchSpace;
                "SourceWim" = [string]$Task.SourceWim;
                "WinPEAutoExtraFiles" = [string]$Task.AutoExtraFiles;
                "WinPEDaRT" = [string]$Task.WinPEAddDaRT;
                "WinPEDrivers" = [string[]]$Task.WinPEAddWindowsDriver;
                "WinPEExtraFiles" = [string[]]$Task.WinPERobocopyExtraFiles;
                "WinPEScripts" = [string[]]$Task.WinPEInvokeScript;
                "WinPEADK" = [string[]]$Task.WinPEAddADK;
            }
    
            #=================================================
            Write-Verbose '19.1.7 Create Backup'
            #=================================================
            if (!(Test-Path "$($TaskFile.Directory)\Repair")) {
                New-Item -Path "$($TaskFile.Directory)\Repair"-ItemType Directory -Force | Out-Null
            }

            if (!(Test-Path "$($TaskFile.Directory)\Repair\$($TaskFile.Name)")) {
                Write-Host "Creating Backup $($TaskFile.Directory)\Repair\$($TaskFile.Name)"
                Copy-Item -Path "$($TaskFile.FullName)" -Destination "$($TaskFile.Directory)\Repair\$($TaskFile.Name)" -Force
            }
            
            #=================================================
            Write-Verbose '19.1.7 New-PEBuildTask Complete'
            #=================================================
            $NewTask | ConvertTo-Json | Out-File "$($Item.FullName)"
            Write-Host "Update Complete: $($Task.TaskName)"
            Write-Host '========================================================================================' -ForegroundColor DarkGray
        }
    }

    End {
        #Write-Host '========================================================================================' -ForegroundColor DarkGray
        #Write-Host "$($MyInvocation.MyCommand.Name) END"
    }
}
