BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    foreach ($Script in (Get-OSDBuilderPrivateScript)) {. $Script}
    . (Join-Path (Join-Path $RepoRoot 'Public') 'Repair-OSBuildTask.ps1')

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

Describe 'Repair-OSBuildTask' {
    BeforeAll {
        $SavedGetOSDBuilder = $global:GetOSDBuilder
        $global:GetOSDBuilder = [PSCustomObject]@{VersionOSDBuilder = '26.10.14.1'}
    }
    AfterAll {
        $global:GetOSDBuilder = $SavedGetOSDBuilder
    }
    BeforeEach {
        $TaskDirectory = Join-Path $TestDrive "Tasks$([guid]::NewGuid().Guid)"
        New-Item -Path $TaskDirectory -ItemType Directory -Force | Out-Null
        $TaskPath = Join-Path $TaskDirectory 'OSBuild Win10 x64 1809.json'
        $TaskJson = [ordered]@{
            TaskName = 'Win10 x64 1809'; TaskVersion = '19.1.1.0'; MediaName = 'Windows 10 Enterprise x64 1809 17763.253'; BuildName = 'Win10 Custom'
            EnableNetFX3 = 'True'; ImportStartLayout = 'StartLayout\Layout.xml'; UseWindowsUnattend = 'Unattend\Unattend.xml'; WinPEAddDaRT = 'DaRT\DaRT 10'
            RobocopyExtraFiles = @('ExtraFiles\Wallpaper'); InvokeScript = @('Scripts\Cleanup.ps1'); AddWindowsDriver = @('Drivers\Dell')
            RemoveAppxProvisionedPackage = @('Microsoft.BingNews'); RemoveWindowsCapability = @('App.StepsRecorder~~~~0.0.1.0')
            WinPEInvokeScriptSetup = @('WinPE\Scripts\Setup.ps1'); LangSetUILang = 'de-DE'; AddLanguagePack = @('LanguagePacks\de-DE.cab')
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
        $NewTaskPath = Join-Path $TaskDirectory 'OSBuild Current.json'
        Set-Content -Path $NewTaskPath -Value ([ordered]@{TaskType = 'OSBuild'; TaskName = 'Current'; TaskVersion = '26.10.14.1'; OSMGuid = [guid]::NewGuid().Guid} | ConvertTo-Json)
        Mock Get-OSMedia {$script:Media}
        Mock Out-GridView {if ($InputObject) {$script:GridItems.Add($InputObject.Name); if ($InputObject.Name -eq $script:Select) {$InputObject}}}
    }

    It 'rewrites the task with the selected OSMedia and the renamed properties' {
        Repair-OSBuildTask 6>$null 3>$null
        $Task = Get-Content -Path $TaskPath -Raw | ConvertFrom-Json
        $Selected = $script:Media | Where-Object {$_.Name -eq $script:Select}
        $Task.TaskType | Should -Be 'OSBuild'
        $Task.TaskName | Should -Be 'Win10 x64 1809'
        $Task.TaskVersion | Should -Be '26.10.14.1'
        $Task.CustomName | Should -Be 'Win10 Custom'
        $Task.OSMGuid | Should -Be $Selected.OSMGuid
        $Task.OSMFamily | Should -Be $Selected.OSMFamily
        $Task.ReleaseId | Should -Be '1809'
        $Task.StartLayoutXML | Should -Be 'StartLayout\Layout.xml'
        $Task.UnattendXML | Should -Be 'Unattend\Unattend.xml'
        $Task.WinPEAutoExtraFiles | Should -Be 'False'
        $Task.WinPEDaRT | Should -Be 'DaRT\DaRT 10'
        $Task.ExtraFiles | Should -Be 'ExtraFiles\Wallpaper'
        $Task.Scripts | Should -Be 'Scripts\Cleanup.ps1'
        $Task.Drivers | Should -Be 'Drivers\Dell'
        $Task.RemoveAppxProvisionedPackage | Should -Be 'Microsoft.BingNews'
        $Task.WinPEScriptsSE | Should -Be 'WinPE\Scripts\Setup.ps1'
        $Task.LangSetUILang | Should -Be 'de-DE'
        $Task.LanguagePack | Should -Be 'LanguagePacks\de-DE.cab'
        {[guid]$Task.TaskGuid} | Should -Not -Throw
        Should -Invoke Get-OSDBuilder -Times 1 -Exactly -ParameterFilter {$CreatePaths -and $HideDetails}
    }

    It 'saves a backup of the original task in Repair' {
        $Original = Get-Content -Path $TaskPath -Raw
        $Warnings = (Repair-OSBuildTask 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike "*Repair Required: $TaskPath*"
        Get-Content -Path (Join-Path (Join-Path $TaskDirectory 'Repair') (Split-Path $TaskPath -Leaf)) -Raw | Should -Be $Original
    }

    It 'keeps an existing backup' {
        New-TestFile -Path (Join-Path (Join-Path $TaskDirectory 'Repair') (Split-Path $TaskPath -Leaf)) -Value 'first backup' | Out-Null
        Repair-OSBuildTask 6>$null 3>$null
        Get-Content -Path (Join-Path (Join-Path $TaskDirectory 'Repair') (Split-Path $TaskPath -Leaf)) | Should -Be 'first backup'
        (Get-Content -Path $TaskPath -Raw | ConvertFrom-Json).TaskType | Should -Be 'OSBuild'
    }

    It 'offers only the OSMedia that match <MediaName>' -TestCases @(
        @{MediaName = 'Windows 10 Enterprise x64 1511'; Expected = @('Windows 10 Enterprise x64 1511')}
        @{MediaName = 'Windows 10 Enterprise x64 1607'; Expected = @('Windows 10 Enterprise x64 1607')}
        @{MediaName = 'Windows 10 Enterprise x64 1703'; Expected = @('Windows 10 Enterprise x64 1703')}
        @{MediaName = 'Windows 10 Enterprise x64 1709'; Expected = @('Windows 10 Enterprise x64 1709')}
        @{MediaName = 'Windows 10 Enterprise x64 1803'; Expected = @('Windows 10 Enterprise x64 1803')}
        @{MediaName = 'Windows 10 Enterprise x86 1809'; Expected = @('Windows 10 Enterprise x86 1809')}
        @{MediaName = 'Windows 10 Enterprise 1809'; Expected = @('Windows 10 Enterprise x64 1809', 'Windows 10 Enterprise x86 1809')}
    ) {
        $Task = Get-Content -Path $TaskPath -Raw | ConvertFrom-Json
        $Task.MediaName = $MediaName
        $Task | ConvertTo-Json | Set-Content -Path $TaskPath
        $script:Select = $Expected[0]
        Repair-OSBuildTask 6>$null 3>$null
        @($script:GridItems) | Should -Be $Expected
        (Get-Content -Path $TaskPath -Raw | ConvertFrom-Json).Name | Should -Be $Expected[0]
    }

    It 'does not change a Task newer than 19.1.3.0' {
        $Task = Get-Content -Path $TaskPath -Raw | ConvertFrom-Json
        $Task.TaskVersion = '19.1.4.0'
        $Task | ConvertTo-Json | Set-Content -Path $TaskPath
        $Before = Get-Content -Path $TaskPath -Raw
        $Current = Get-Content -Path $NewTaskPath -Raw
        $Warnings = (Repair-OSBuildTask 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*No OSBuild Task needs a Repair*'
        Get-Content -Path $TaskPath -Raw | Should -Be $Before
        Get-Content -Path $NewTaskPath -Raw | Should -Be $Current
        Should -Invoke Get-OSMedia -Times 0 -Exactly
    }

    It 'repairs a Task of version 19.1.3.0' {
        $Task = Get-Content -Path $TaskPath -Raw | ConvertFrom-Json
        $Task.TaskVersion = '19.1.3.0'
        $Task | ConvertTo-Json | Set-Content -Path $TaskPath
        Repair-OSBuildTask 6>$null 3>$null
        (Get-Content -Path $TaskPath -Raw | ConvertFrom-Json).TaskVersion | Should -Be '26.10.14.1'
    }

    It 'repairs the next Task when no OSMedia is selected for a Task' {
        $Task = Get-Content -Path $TaskPath -Raw | ConvertFrom-Json
        $Task.MediaName = 'Windows 10 Enterprise x86 1809'
        $Task | ConvertTo-Json | Set-Content -Path $TaskPath
        $Task.TaskName = 'Second'
        $Task.MediaName = 'Windows 10 Enterprise x64 1809'
        $SecondPath = Join-Path $TaskDirectory 'OSBuild Second.json'
        $Task | ConvertTo-Json | Set-Content -Path $SecondPath
        $Before = Get-Content -Path $TaskPath -Raw
        Repair-OSBuildTask 6>$null 3>$null
        Get-Content -Path $TaskPath -Raw | Should -Be $Before
        (Get-Content -Path $SecondPath -Raw | ConvertFrom-Json).OSMGuid | Should -Be ($script:Media | Where-Object {$_.Name -eq $script:Select}).OSMGuid
    }

    It 'writes the Languages of the OSMedia and keeps a TaskName with umlauts' {
        $Task = Get-Content -Path $TaskPath -Raw | ConvertFrom-Json
        #[char]0x00D6 is an O with umlaut, the test file stays ASCII for Windows PowerShell 5.1
        $TaskName = "Win10 OS $([char]0x00D6)sterreich"
        $Task.TaskName = $TaskName
        $Task | ConvertTo-Json | Set-Content -Path $TaskPath -Encoding UTF8
        Repair-OSBuildTask 6>$null 3>$null
        $Repaired = Get-Content -Path $TaskPath -Raw | ConvertFrom-Json
        $Repaired.TaskName | Should -BeExactly $TaskName
        @($Repaired.Languages) | Should -Be @('en-US', 'de-DE')
    }

    It 'does not change the task when no OSMedia is selected' {
        $script:Select = 'None'
        $Before = Get-Content -Path $TaskPath -Raw
        $Warnings = (Repair-OSBuildTask 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*OSMedia was not selected*'
        Get-Content -Path $TaskPath -Raw | Should -Be $Before
        Test-Path -Path (Join-Path $TaskDirectory 'Repair') | Should -BeFalse
    }
}
