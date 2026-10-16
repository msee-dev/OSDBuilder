BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    foreach ($Script in (Get-OSDBuilderPrivateScript)) {. $Script}
    . (Join-Path (Join-Path $RepoRoot 'Public') 'Repair-PEBuildTask.ps1')

    #Public functions that are not dot-sourced with the Private scripts
    function Get-OSDBuilder {
        [CmdletBinding()]
        param ([switch]$CreatePaths, [switch]$HideDetails)
    }
    function Get-OSMedia {
        [CmdletBinding()]
        param ($Revision)
    }
    function New-RepairMedia ($Arch, $ReleaseId) {
        [PSCustomObject]@{
            Name = "Windows 10 Enterprise $Arch $ReleaseId"; Arch = $Arch; ReleaseId = $ReleaseId; OSMGuid = [guid]::NewGuid().Guid
            OSMFamily = "Client Enterprise $Arch 17763 en-US"; ImageName = 'Windows 10 Enterprise'; UBR = '6893'; EditionId = 'Enterprise'
            InstallationType = 'Client'; MajorVersion = '10'; Build = '17763'; Languages = @('en-US', 'de-DE')
            CreatedTime = [datetime]'2026-10-14 10:00:00'; ModifiedTime = [datetime]'2026-10-14 11:00:00'
        }
    }
}

Describe 'Repair-PEBuildTask' {
    BeforeAll {
        $SavedGetOSDBuilder = $global:GetOSDBuilder
        $global:GetOSDBuilder = [PSCustomObject]@{VersionOSDBuilder = '26.10.14.1'}
    }
    AfterAll {
        $global:GetOSDBuilder = $SavedGetOSDBuilder
    }
    BeforeEach {
        $TaskDirectory = Join-Path $TestDrive "PETasks$([guid]::NewGuid().Guid)"
        New-Item -Path (Join-Path $TaskDirectory 'Repair') -ItemType Directory -Force | Out-Null
        $TaskPath = Join-Path $TaskDirectory 'PEBuild WinPE x64 1809.json'
        $TaskJson = [ordered]@{
            TaskName = 'WinPE x64 1809'; TaskVersion = '19.1.1.0'; MediaName = 'Windows 10 Enterprise x64 1809 17763.253'
            PEOutput = 'MDT'; DeploymentShare = '\\server\DeploymentShare$'; ScratchSpace = '512'; SourceWim = 'WinPE'; AutoExtraFiles = 'True'
            WinPEAddDaRT = 'DaRT\DaRT 10'; WinPEAddWindowsDriver = @('WinPE\Drivers\Intel'); WinPERobocopyExtraFiles = @('WinPE\ExtraFiles\Tools')
            WinPEInvokeScript = @('WinPE\Scripts\Start.ps1'); WinPEAddADK = @('ADK\WinPE-PowerShell.cab', 'ADK\WinPE-WMI.cab')
        } | ConvertTo-Json
        Set-Content -Path $TaskPath -Value $TaskJson
        $script:Media = @(
            New-RepairMedia 'x64' '1511'; New-RepairMedia 'x64' '1607'; New-RepairMedia 'x64' '1703'; New-RepairMedia 'x64' '1709'
            New-RepairMedia 'x64' '1803'; New-RepairMedia 'x64' '1809'; New-RepairMedia 'x86' '1809'
        )
        $script:Select = 'Windows 10 Enterprise x64 1809'
        $script:GridItems = [System.Collections.Generic.List[string]]::new()
        Mock Get-OSDBuilder {}
        $SetOSDBuilderPathTasks = $TaskDirectory
        #a Task of the current format does not need a Repair
        $NewTaskPath = Join-Path $TaskDirectory 'PEBuild Current.json'
        Set-Content -Path $NewTaskPath -Value ([ordered]@{TaskType = 'PEBuild'; TaskName = 'Current'; TaskVersion = '26.10.14.1'; OSMGuid = [guid]::NewGuid().Guid} | ConvertTo-Json)
        Mock Get-OSMedia {$script:Media}
        Mock Out-GridView {if ($InputObject) {$script:GridItems.Add($InputObject.Name); if ($InputObject.Name -eq $script:Select) {$InputObject}}}
    }

    It 'rewrites the task with the selected OSMedia and the renamed properties' {
        $Original = Get-Content -Path $TaskPath -Raw
        $Output = (Repair-PEBuildTask 6>&1 3>$null) -join "`n"
        $Task = Get-Content -Path $TaskPath -Raw | ConvertFrom-Json
        $Selected = $script:Media | Where-Object {$_.Name -eq $script:Select}
        $Task.TaskType | Should -Be 'PEBuild'
        $Task.TaskVersion | Should -Be '26.10.14.1'
        $Task.OSMGuid | Should -Be $Selected.OSMGuid
        $Task.Arch | Should -Be 'x64'
        $Task.WinPEOutput | Should -Be 'MDT'
        $Task.MDTDeploymentShare | Should -Be '\\server\DeploymentShare$'
        $Task.ScratchSpace | Should -Be '512'
        $Task.SourceWim | Should -Be 'WinPE'
        $Task.WinPEAutoExtraFiles | Should -Be 'True'
        $Task.WinPEDrivers | Should -Be 'WinPE\Drivers\Intel'
        $Task.WinPEExtraFiles | Should -Be 'WinPE\ExtraFiles\Tools'
        $Task.WinPEScripts | Should -Be 'WinPE\Scripts\Start.ps1'
        $Task.WinPEADK | Should -Be @('ADK\WinPE-PowerShell.cab', 'ADK\WinPE-WMI.cab')
        $Task.CustomName | Should -Be ''
        Get-Content -Path (Join-Path (Join-Path $TaskDirectory 'Repair') (Split-Path $TaskPath -Leaf)) -Raw | Should -Be $Original
        $Output | Should -BeLike '*Update Complete: WinPE x64 1809*'
    }

    It 'offers only the OSMedia that match <MediaName>' -TestCases @(
        @{MediaName = 'Windows 10 Enterprise x64 1511'; Expected = @('Windows 10 Enterprise x64 1511')}
        @{MediaName = 'Windows 10 Enterprise x64 1607'; Expected = @('Windows 10 Enterprise x64 1607')}
        @{MediaName = 'Windows 10 Enterprise x64 1703'; Expected = @('Windows 10 Enterprise x64 1703')}
        @{MediaName = 'Windows 10 Enterprise x64 1709'; Expected = @('Windows 10 Enterprise x64 1709')}
        @{MediaName = 'Windows 10 Enterprise x64 1803'; Expected = @('Windows 10 Enterprise x64 1803')}
        @{MediaName = 'Windows 10 Enterprise x86 1809'; Expected = @('Windows 10 Enterprise x86 1809')}
    ) {
        $Task = Get-Content -Path $TaskPath -Raw | ConvertFrom-Json
        $Task.MediaName = $MediaName
        $Task | ConvertTo-Json | Set-Content -Path $TaskPath
        $script:Select = $Expected[0]
        Repair-PEBuildTask 6>$null 3>$null
        @($script:GridItems) | Should -Be $Expected
        (Get-Content -Path $TaskPath -Raw | ConvertFrom-Json).Name | Should -Be $Expected[0]
    }

    It 'creates the Repair directory for the backup' {
        Remove-Item -Path (Join-Path $TaskDirectory 'Repair') -Recurse -Force
        Repair-PEBuildTask 6>$null 3>$null
        Test-Path -Path (Join-Path (Join-Path $TaskDirectory 'Repair') (Split-Path $TaskPath -Leaf)) -PathType Leaf | Should -BeTrue
    }

    It 'keeps an existing backup' {
        New-TestFile -Path (Join-Path (Join-Path $TaskDirectory 'Repair') (Split-Path $TaskPath -Leaf)) -Value 'first backup' | Out-Null
        Repair-PEBuildTask 6>$null 3>$null
        Get-Content -Path (Join-Path (Join-Path $TaskDirectory 'Repair') (Split-Path $TaskPath -Leaf)) | Should -Be 'first backup'
        (Get-Content -Path $TaskPath -Raw | ConvertFrom-Json).TaskType | Should -Be 'PEBuild'
    }

    It 'does not change a Task newer than 19.1.3.0' {
        $Task = Get-Content -Path $TaskPath -Raw | ConvertFrom-Json
        $Task.TaskVersion = '20.1.1.0'
        $Task | ConvertTo-Json | Set-Content -Path $TaskPath
        $Before = Get-Content -Path $TaskPath -Raw
        $Current = Get-Content -Path $NewTaskPath -Raw
        $Warnings = (Repair-PEBuildTask 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*No PEBuild Task needs a Repair*'
        Get-Content -Path $TaskPath -Raw | Should -Be $Before
        Get-Content -Path $NewTaskPath -Raw | Should -Be $Current
        Should -Invoke Get-OSMedia -Times 0 -Exactly
    }

    It 'repairs a Task of version 19.1.3.0' {
        $Task = Get-Content -Path $TaskPath -Raw | ConvertFrom-Json
        $Task.TaskVersion = '19.1.3.0'
        $Task | ConvertTo-Json | Set-Content -Path $TaskPath
        Repair-PEBuildTask 6>$null 3>$null
        (Get-Content -Path $TaskPath -Raw | ConvertFrom-Json).TaskVersion | Should -Be '26.10.14.1'
    }

    It 'repairs the next Task when no OSMedia is selected for a Task' {
        $Task = Get-Content -Path $TaskPath -Raw | ConvertFrom-Json
        $Task.MediaName = 'Windows 10 Enterprise x86 1809'
        $Task | ConvertTo-Json | Set-Content -Path $TaskPath
        $Task.TaskName = 'Second'
        $Task.MediaName = 'Windows 10 Enterprise x64 1809'
        $SecondPath = Join-Path $TaskDirectory 'PEBuild Second.json'
        $Task | ConvertTo-Json | Set-Content -Path $SecondPath
        $Before = Get-Content -Path $TaskPath -Raw
        Repair-PEBuildTask 6>$null 3>$null
        Get-Content -Path $TaskPath -Raw | Should -Be $Before
        (Get-Content -Path $SecondPath -Raw | ConvertFrom-Json).OSMGuid | Should -Be ($script:Media | Where-Object {$_.Name -eq $script:Select}).OSMGuid
    }

    It 'writes the Languages of the OSMedia and keeps a TaskName with umlauts' {
        $Task = Get-Content -Path $TaskPath -Raw | ConvertFrom-Json
        $Task.TaskName = 'Win10 PE Österreich'
        $Task | ConvertTo-Json | Set-Content -Path $TaskPath -Encoding UTF8
        Repair-PEBuildTask 6>$null 3>$null
        $Repaired = Get-Content -Path $TaskPath -Raw | ConvertFrom-Json
        $Repaired.TaskName | Should -BeExactly 'Win10 PE Österreich'
        @($Repaired.Languages) | Should -Be @('en-US', 'de-DE')
    }

    It 'does not change the task when no OSMedia is selected' {
        $script:Select = 'None'
        $Before = Get-Content -Path $TaskPath -Raw
        $Warnings = (Repair-PEBuildTask 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*OSMedia was not selected*'
        Get-Content -Path $TaskPath -Raw | Should -Be $Before
    }
}
