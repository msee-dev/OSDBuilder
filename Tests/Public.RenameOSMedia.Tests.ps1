BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    foreach ($Script in (Get-OSDBuilderPrivateScript)) {. $Script}
    . (Join-Path (Join-Path $RepoRoot 'Public') 'Rename-OSMedia.ps1')

    #Public functions that are not dot-sourced with the Private scripts
    function Get-OSDBuilder {
        [CmdletBinding()]
        param ([switch]$CreatePaths, [switch]$HideDetails)
    }
    function New-OSMediaFixture {
        <#
        .SYNOPSIS
        Creates an OSMedia directory with info\xml\Get-WindowsImage.xml and optional CurrentVersion.xml
        #>
        param (
            [string]$Root, [string]$Name, [string]$ImageName, $Architecture = 9, $Build = 26200, $UBR = 6899,
            [string[]]$Languages = @('en-US'), [string]$InstallationType = 'Client', $MajorVersion = 10,
            [string]$EditionId = 'Enterprise', [string]$ReleaseId, [string]$OSMGuid = [guid]::NewGuid().Guid
        )
        $Path = Join-Path $Root $Name
        foreach ($Folder in 'xml', 'logs', 'json') {New-Item -Path (Join-Path (Join-Path $Path 'info') $Folder) -ItemType Directory -Force | Out-Null}
        $Image = [PSCustomObject]@{
            ImageName = $ImageName; Version = "$MajorVersion.0.$Build.$UBR"; Architecture = $Architecture; EditionId = $EditionId
            InstallationType = $InstallationType; MajorVersion = $MajorVersion; MinorVersion = 0; Build = $Build; UBR = $UBR
            Languages = $Languages; CreatedTime = [datetime]'2026-10-14 10:00:00'
        }
        if ($OSMGuid) {$Image | Add-Member -NotePropertyName OSMGuid -NotePropertyValue $OSMGuid}
        $Image | Export-Clixml -Path (Join-Path (Join-Path (Join-Path $Path 'info') 'xml') 'Get-WindowsImage.xml')
        if ($ReleaseId) {
            [PSCustomObject]@{ReleaseId = $ReleaseId} | Export-Clixml -Path (Join-Path (Join-Path (Join-Path $Path 'info') 'xml') 'CurrentVersion.xml')
        }
        Get-Item -Path $Path
    }
}

Describe 'Rename-OSMedia' {
    BeforeEach {
        $SetOSDBuilderPathOSMedia = Join-Path $TestDrive "OSMedia$([guid]::NewGuid().Guid)"
        New-Item -Path $SetOSDBuilderPathOSMedia -ItemType Directory -Force | Out-Null
        $script:GridItems = [System.Collections.Generic.List[object]]::new()
        Mock Get-OSDBuilder {}
        Mock Out-GridView {if ($InputObject) {$script:GridItems.Add($InputObject); $InputObject}}
    }

    It 'renames <ImageName> build <Build> to <Expected>' -TestCases @(
        @{ImageName = 'Windows 11 Enterprise'; Architecture = 9; Build = 26200; UBR = 6899; Languages = @('en-US'); InstallationType = 'Client'; MajorVersion = 10; ReleaseId = '25H2'; Expected = 'Windows 11 Enterprise x64 25H2 6899'}
        @{ImageName = 'Windows 10 Enterprise'; Architecture = 0; Build = 17763; UBR = 6893; Languages = @('en-US', 'de-DE'); InstallationType = 'Client'; MajorVersion = 10; ReleaseId = $null; Expected = 'Windows 10 Enterprise x86 1809 6893 en-US de-DE'}
        @{ImageName = 'Windows 7 Professional'; Architecture = 9; Build = 7601; UBR = 24544; Languages = @('de-DE'); InstallationType = 'Client'; MajorVersion = 6; ReleaseId = $null; Expected = 'Windows 7 Professional x64 SP1 24544 de-DE'}
        @{ImageName = 'Windows 7 Starter'; Architecture = 0; Build = 7600; UBR = 16385; Languages = @('en-US'); InstallationType = 'Client'; MajorVersion = 6; ReleaseId = $null; Expected = 'Windows 7 Starter x86 7600 16385'}
        @{ImageName = 'Windows Server 2012 R2 SERVERSTANDARD'; Architecture = 6; Build = 9600; UBR = 21620; Languages = @('en-US'); InstallationType = 'Server'; MajorVersion = 6; ReleaseId = $null; Expected = 'Windows Server 2012 R2 SERVERSTANDARD ia64 9600 21620'}
        @{ImageName = 'Windows 10 Enterprise 2015 LTSB'; Architecture = 9; Build = 10240; UBR = 20796; Languages = @('en-US'); InstallationType = 'Client'; MajorVersion = 10; ReleaseId = $null; Expected = 'Windows 10 Enterprise 2015 LTSB x64 1507 20796'}
        @{ImageName = 'Windows Server 2016 SERVERDATACENTER (Desktop Experience)'; Architecture = 9; Build = 14393; UBR = 7428; Languages = @('en-US'); InstallationType = 'Server'; MajorVersion = 10; ReleaseId = $null; Expected = 'Windows Server 2016 SERVERDATACENTER Desktop Experience x64 1607 7428'}
        @{ImageName = 'Windows 10 Pro'; Architecture = 12; Build = 15063; UBR = 2679; Languages = @('en-US'); InstallationType = 'Client'; MajorVersion = 10; ReleaseId = $null; Expected = 'Windows 10 Pro x64 ARM 1703 2679'}
        @{ImageName = 'Windows 10 Education'; Architecture = 9; Build = 16299; UBR = 2166; Languages = @('en-US'); InstallationType = 'Client'; MajorVersion = 10; ReleaseId = $null; Expected = 'Windows 10 Education x64 1709 2166'}
        @{ImageName = 'Windows Server 2019 SERVERSTANDARD'; Architecture = 9; Build = 17134; UBR = 2208; Languages = @('en-US'); InstallationType = 'Server'; MajorVersion = 10; ReleaseId = $null; Expected = 'Windows Server 2019 SERVERSTANDARD x64 1803 2208'}
        @{ImageName = 'Windows Server 2022 SERVERSTANDARD'; Architecture = 9; Build = 20348; UBR = 4171; Languages = @('en-US'); InstallationType = 'Server'; MajorVersion = 10; ReleaseId = '2009'; Expected = 'Windows Server 2022 SERVERSTANDARD x64 2009 4171'}
    ) {
        $Media = New-OSMediaFixture -Root $SetOSDBuilderPathOSMedia -Name 'Imported OSMedia' -ImageName $ImageName -Architecture $Architecture -Build $Build -UBR $UBR -Languages $Languages -InstallationType $InstallationType -MajorVersion $MajorVersion -ReleaseId $ReleaseId
        Rename-OSMedia 3>$null
        Test-Path -Path (Join-Path $SetOSDBuilderPathOSMedia $Expected) -PathType Container | Should -BeTrue
        Test-Path -Path $Media.FullName | Should -BeFalse
        $script:GridItems[0].FullNameFormat | Should -Be $Expected
        $script:GridItems[0].Name | Should -Be 'Imported OSMedia'
        Should -Invoke Get-OSDBuilder -Times 1 -Exactly -ParameterFilter {$CreatePaths -and $HideDetails}
    }

    It 'warns about every rename' {
        New-OSMediaFixture -Root $SetOSDBuilderPathOSMedia -Name 'Old' -ImageName 'Windows 11 Pro' -ReleaseId '25H2' | Out-Null
        $Warnings = (Rename-OSMedia 3>&1) -join "`n"
        $Warnings | Should -BeLike "*Renaming *Old to Windows 11 Pro x64 25H2 6899*"
    }

    It 'adds an OSMGuid and writes the WindowsImage files when the OSMedia has none' {
        $Media = New-OSMediaFixture -Root $SetOSDBuilderPathOSMedia -Name 'Windows 11 Pro x64 25H2 6899' -ImageName 'Windows 11 Pro' -ReleaseId '25H2' -OSMGuid ''
        Rename-OSMedia 3>$null
        $Image = Import-Clixml -Path (Join-Path (Join-Path (Join-Path $Media.FullName 'info') 'xml') 'Get-WindowsImage.xml')
        {[guid]$Image.OSMGuid} | Should -Not -Throw
        Get-Content -Path (Join-Path (Join-Path (Join-Path $Media.FullName 'info') 'json') 'Get-WindowsImage.json') -Raw | Should -BeLike "*$($Image.OSMGuid)*"
        $Text = Get-Content -Path (Join-Path $Media.FullName 'WindowsImage.txt')
        $Text | Where-Object {-not $_.Trim()} | Should -BeNullOrEmpty
        ($Text -join "`n") | Should -BeLike '*OSMGuid*'
        @(Get-ChildItem -Path (Join-Path (Join-Path $Media.FullName 'info') 'logs') -Filter '*-Get-WindowsImage.txt').Count | Should -Be 1
    }

    It 'does not offer OSMedia that already have the right name and ignores directories without Get-WindowsImage.xml' {
        New-OSMediaFixture -Root $SetOSDBuilderPathOSMedia -Name 'Windows 11 Pro x64 25H2 6899' -ImageName 'Windows 11 Pro' -ReleaseId '25H2' | Out-Null
        New-Item -Path (Join-Path $SetOSDBuilderPathOSMedia 'Not an OSMedia') -ItemType Directory | Out-Null
        Rename-OSMedia 3>$null
        $script:GridItems.Count | Should -Be 0
        Test-Path -Path (Join-Path $SetOSDBuilderPathOSMedia 'Not an OSMedia') | Should -BeTrue
    }

    It 'renames nothing when no OSMedia is selected' {
        Mock Out-GridView {}
        $Media = New-OSMediaFixture -Root $SetOSDBuilderPathOSMedia -Name 'Old' -ImageName 'Windows 11 Pro' -ReleaseId '25H2'
        Rename-OSMedia 3>$null
        Test-Path -Path $Media.FullName | Should -BeTrue
    }
}
