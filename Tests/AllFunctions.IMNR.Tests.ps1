#Tests for the AllFunctions.ps1 functions Import-*, Invoke-*, Mount-*, New-* and Remove-*
BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    foreach ($Script in (Get-OSDBuilderPrivateScript)) {. $Script}
    $IMNRSFixtures = Join-Path $FixturesPath 'AllFunctionsIMNRS'

    #Public functions that are not dot-sourced with the Private scripts
    function Get-OSDBuilder {
        [CmdletBinding()]
        param ([switch]$CreatePaths, [switch]$HideDetails)
    }
    function Get-OSMedia {
        [CmdletBinding()]
        param ($Revision)
    }
    #Remove-ItemProperty -Name is mandatory, Import-RegistryXmlOS calls it without -Name to remove a key
    #a mock of the cmdlet would prompt for the Name, the placeholder has no mandatory parameter
    function Remove-ItemProperty {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Test placeholder without the mandatory Name')]
        [CmdletBinding()]
        param ($LiteralPath, $Name, [switch]$Force)
    }

    function New-MountedHives {
        <#
        .SYNOPSIS
        Creates the offline registry hive files of a mounted install.wim
        #>
        param ([string]$MountDirectory, [string[]]$Hive = @('NTUser.dat', 'DEFAULT', 'SOFTWARE', 'SYSTEM'))
        foreach ($Item in $Hive) {
            if ($Item -eq 'NTUser.dat') {
                New-TestFile -Path (Join-Path (Join-Path (Join-Path $MountDirectory 'Users') 'Default') 'NTUser.dat') | Out-Null
            }
            else {
                New-TestFile -Path (Join-Path (Join-Path (Join-Path (Join-Path $MountDirectory 'Windows') 'System32') 'Config') $Item) | Out-Null
            }
        }
    }

    function Register-RegMock {
        <#
        .SYNOPSIS
        Mocks reg.exe LOAD / IMPORT / UNLOAD through Start-Process and simulates the loaded hives in HKLM:
        #>
        param ([switch]$StuckHives)
        $script:RegCalls = [System.Collections.Generic.List[string]]::new()
        $script:LoadedHives = @{}
        $script:StuckHives = [bool]$StuckHives
        Mock Start-Process {
            $Arguments = @($ArgumentList) -join ' '
            $script:RegCalls.Add($Arguments)
            if ($Arguments -match '^load HKLM\\(\S+)') {$script:LoadedHives[$Matches[1]] = $true}
            if (($Arguments -match '^unload HKLM\\(\S+)') -and -not $script:StuckHives) {$script:LoadedHives.Remove($Matches[1])}
        } -ParameterFilter {$FilePath -eq 'reg'}
        Mock Test-Path {$script:LoadedHives.ContainsKey(("$Path" -replace '^HKLM:\\', ''))} -ParameterFilter {"$Path" -like 'HKLM:\*'}
        Mock Pause {}
    }


}

Describe 'Import-AutoExtraFilesPE' {
    BeforeEach {
        $ScriptName = 'New-OSBuild'; $WinPEAutoExtraFiles = $true
        $WinPE = 'C:\OSMedia\WinPE'; $PEInfo = 'C:\OSMedia\WinPE\info'
        $MountWinPE = 'C:\Mount\WinPE'; $MountWinRE = 'C:\Mount\WinRE'; $MountWinSE = 'C:\Mount\WinSE'
        $script:Robocopy = [System.Collections.Generic.List[string]]::new()
        Mock robocopy {$script:Robocopy.Add((@($InputObject) + @($RemainingArguments)) -join ' ')}
    }

    It 'copies the AutoExtraFiles into WinPE, WinRE and WinSE without the bcp47 dlls' {
        Import-AutoExtraFilesPE 6>$null
        $script:Robocopy.Count | Should -Be 3
        $script:Robocopy[0] | Should -BeLike 'C:\OSMedia\WinPE\AutoExtraFiles C:\Mount\WinPE `*.`* /s *'
        $script:Robocopy[1] | Should -BeLike 'C:\OSMedia\WinPE\AutoExtraFiles C:\Mount\WinRE *'
        $script:Robocopy[2] | Should -BeLike 'C:\OSMedia\WinPE\AutoExtraFiles C:\Mount\WinSE *'
        foreach ($Call in $script:Robocopy) {
            $Call | Should -BeLike '*/xf bcp47`*.dll*'
            $Call | Should -BeLike '*/Log+:C:\OSMedia\WinPE\info\logs\*-Import-AutoExtraFilesPE.log'
        }
    }

    It 'runs for New-OSDCloudOSMedia and writes the header' {
        $ScriptName = 'New-OSDCloudOSMedia'
        $Output = (Import-AutoExtraFilesPE 6>&1) -join "`n"
        $Output | Should -BeLike '*WinPE: Import AutoExtraFiles*'
        $Output | Should -BeLike '*C:\OSMedia\WinPE\AutoExtraFiles*'
        $script:Robocopy.Count | Should -Be 3
    }

    It 'does nothing for <TestScriptName> with WinPEAutoExtraFiles <TestAutoExtraFiles>' -TestCases @(
        @{TestScriptName = 'New-PEBuild'; TestAutoExtraFiles = $true}
        @{TestScriptName = 'New-OSBuild'; TestAutoExtraFiles = $false}
    ) {
        $ScriptName = $TestScriptName; $WinPEAutoExtraFiles = $TestAutoExtraFiles
        Import-AutoExtraFilesPE 6>$null
        Should -Invoke robocopy -Times 0 -Exactly
    }
}

Describe 'Import-RegistryRegOS' {
    BeforeEach {
        $MountDirectory = Join-Path $TestDrive "Mount$([guid]::NewGuid().Guid)"
        New-MountedHives -MountDirectory $MountDirectory
        $RegistryTemplatesReg = @(Get-Item -Path (Join-Path $IMNRSFixtures 'Template.reg'))
        Register-RegMock
    }

    It 'loads the offline hives, imports the .reg and unloads the hives' {
        Import-RegistryRegOS 6>$null
        $script:RegCalls[0] | Should -BeLike 'load HKLM\OfflineDefaultUser *Users\Default\NTUser.dat'
        $script:RegCalls[1] | Should -BeLike 'load HKLM\OfflineDefault *Windows\System32\Config\DEFAULT'
        $script:RegCalls[2] | Should -BeLike 'load HKLM\OfflineSoftware *Windows\System32\Config\SOFTWARE'
        $script:RegCalls[3] | Should -BeLike 'load HKLM\OfflineSystem *Windows\System32\Config\SYSTEM'
        $script:RegCalls[4] | Should -Be "import `"$($RegistryTemplatesReg[0].FullName)`""
        $script:RegCalls[5..8] | Should -Be @('unload HKLM\OfflineDefaultUser', 'unload HKLM\OfflineDefault', 'unload HKLM\OfflineSoftware', 'unload HKLM\OfflineSystem')
        $script:RegCalls.Count | Should -Be 9
        $script:LoadedHives.Count | Should -Be 0
        Should -Invoke Pause -Times 0 -Exactly
    }

    It 'shows the content of every .reg file' {
        $Second = New-TestFile -Path (Join-Path $TestDrive 'Second.reg') -Value "Windows Registry Editor Version 5.00`r`n[HKEY_LOCAL_MACHINE\OfflineSystem\Setup]"
        $RegistryTemplatesReg = @($RegistryTemplatesReg[0], $Second)
        $Output = (Import-RegistryRegOS 6>&1) -join "`n"
        $Output | Should -BeLike '*OS: Template Registry REG*'
        $Output | Should -BeLike "*Processing $($Second.FullName)*"
        $Output | Should -BeLike '*"DisableWindowsConsumerFeatures"=dword:00000001*'
        $Output | Should -BeLike '*`[HKEY_LOCAL_MACHINE\OfflineSystem\Setup`]*'
        @($script:RegCalls | Where-Object {$_ -like 'import *'}).Count | Should -Be 2
    }

    It 'loads only the hives that exist in the mounted image' {
        $MountDirectory = Join-Path $TestDrive "Mount$([guid]::NewGuid().Guid)"
        New-MountedHives -MountDirectory $MountDirectory -Hive 'SOFTWARE'
        Import-RegistryRegOS 6>$null
        @($script:RegCalls | Where-Object {$_ -like 'load *'}) | Should -BeLike 'load HKLM\OfflineSoftware *'
        @($script:RegCalls | Where-Object {$_ -like 'unload *'}) | Should -Be 'unload HKLM\OfflineSoftware'
    }

    It 'unloads twice and warns when a hive cannot be unloaded' {
        Register-RegMock -StuckHives
        $Warnings = (Import-RegistryRegOS 6>$null 3>&1) -join "`n"
        @($script:RegCalls | Where-Object {$_ -like 'unload *'}).Count | Should -Be 8
        foreach ($Hive in 'OfflineDefaultUser', 'OfflineDefault', 'OfflineSoftware', 'OfflineSystem') {
            $Warnings | Should -BeLike "*HKLM:\$Hive could not be dismounted*"
        }
        Should -Invoke Pause -Times 4 -Exactly
    }

    It 'does nothing without .reg templates' {
        $RegistryTemplatesReg = @()
        Import-RegistryRegOS 6>$null
        Should -Invoke Start-Process -Times 0 -Exactly
    }
}

Describe 'Import-RegistryXmlOS' {
    BeforeEach {
        $MountDirectory = Join-Path $TestDrive "Mount$([guid]::NewGuid().Guid)"
        New-MountedHives -MountDirectory $MountDirectory
        $RegistryTemplatesXml = @(Get-Item -Path (Join-Path $IMNRSFixtures 'Registry.xml'))
        Register-RegMock
        $script:RegistryKeys = @{}
        Mock Test-Path {$script:RegistryKeys.ContainsKey("$LiteralPath")} -ParameterFilter {"$LiteralPath" -like 'Registry::*'}
        Mock New-Item {$script:RegistryKeys["$Path"] = $true} -ParameterFilter {"$Path" -like 'Registry::*'}
        Mock New-ItemProperty {}
        Mock Remove-ItemProperty {}
        #$Path can come from the scope of the caller (Invoke-OSDBuilderTests.ps1 -Path) when Remove-Item is called with -LiteralPath
        Mock Remove-Item {} -ParameterFilter {("$LiteralPath" -like 'Registry::*') -or ("$Path" -like 'Registry::*')}
    }

    It 'maps the hives of the XML to the loaded offline hives' {
        Import-RegistryXmlOS 6>$null
        Should -Invoke New-ItemProperty -Times 1 -Exactly -ParameterFilter {
            ($LiteralPath -eq 'Registry::HKEY_LOCAL_MACHINE\OfflineSoftware\Policies\Microsoft\Windows\CloudContent') -and ($Name -eq 'DisableWindowsConsumerFeatures') -and ($PropertyType -eq 'DWord') -and ($Value -eq '00000001') -and $Force
        }
        Should -Invoke New-ItemProperty -Times 1 -Exactly -ParameterFilter {
            ($LiteralPath -eq 'Registry::HKEY_LOCAL_MACHINE\OfflineDefaultUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced') -and ($Name -eq 'TaskbarAl')
        }
        Should -Invoke New-ItemProperty -Times 1 -Exactly -ParameterFilter {
            ($LiteralPath -eq 'Registry::HKEY_LOCAL_MACHINE\OfflineDefault\Control Panel\Colors') -and ($Name -eq 'Background') -and ($PropertyType -eq 'String') -and ($Value -eq '0 0 0')
        }
        Should -Invoke New-ItemProperty -Times 1 -Exactly -ParameterFilter {
            ($LiteralPath -eq 'Registry::HKEY_LOCAL_MACHINE\OfflineSystem\CurrentControlSet\Control\TimeZoneInformation') -and ($PropertyType -eq 'QWord')
        }
    }

    It 'converts the registry types and the binary value' {
        Import-RegistryXmlOS 6>$null
        Should -Invoke New-ItemProperty -Times 1 -Exactly -ParameterFilter {
            ($Name -eq 'Settings') -and ($PropertyType -eq 'Binary') -and ((@($Value) -join ',') -eq '0x0a,0x0b,0x0c')
        }
        Should -Invoke New-ItemProperty -Times 1 -Exactly -ParameterFilter {($Name -eq 'Languages') -and ($PropertyType -eq 'MultiString')}
        Should -Invoke New-ItemProperty -Times 1 -Exactly -ParameterFilter {
            ($Name -eq '(Default)') -and ($PropertyType -eq 'ExpandString') -and ($Value -eq '%SystemRoot%\OSDBuilder')
        }
    }

    It 'creates every missing key once and no value for an entry without a type' {
        Import-RegistryXmlOS 6>$null
        Should -Invoke New-Item -Times 1 -Exactly -ParameterFilter {"$Path" -eq 'Registry::HKEY_LOCAL_MACHINE\OfflineSoftware\OSDBuilder\Empty'}
        Should -Invoke New-Item -Times 1 -Exactly -ParameterFilter {"$Path" -eq 'Registry::HKEY_LOCAL_MACHINE\OfflineSoftware\OSDBuilder'}
        Should -Invoke New-Item -Times 6 -Exactly -ParameterFilter {"$Path" -like 'Registry::*'}
        Should -Invoke New-ItemProperty -Times 7 -Exactly
    }

    It 'loads and unloads the offline hives and shows the commands' {
        $Output = (Import-RegistryXmlOS 6>&1) -join "`n"
        @($script:RegCalls | Where-Object {$_ -like 'load *'}).Count | Should -Be 4
        @($script:RegCalls | Where-Object {$_ -like 'unload *'}).Count | Should -Be 4
        $script:LoadedHives.Count | Should -Be 0
        $Output | Should -BeLike '*OS: Template Registry XML*'
        $Output | Should -BeLike "*Processing $($RegistryTemplatesXml[0].FullName)*"
        $Output | Should -BeLike '*-Name DisableWindowsConsumerFeatures -PropertyType DWord -Value 1*'
    }

    It 'removes the values of entries with the action D' {
        $RegistryTemplatesXml = @(Get-Item -Path (Join-Path $IMNRSFixtures 'RegistryDelete.xml'))
        Import-RegistryXmlOS 6>$null
        Should -Invoke Remove-ItemProperty -Times 1 -Exactly -ParameterFilter {
            ($LiteralPath -eq 'Registry::HKEY_LOCAL_MACHINE\OfflineSoftware\Microsoft\Windows\CurrentVersion\Run') -and ($Name -eq 'SecurityHealth')
        }
        Should -Invoke Remove-ItemProperty -Times 1 -Exactly -ParameterFilter {
            ($LiteralPath -eq 'Registry::HKEY_LOCAL_MACHINE\OfflineSoftware\OSDBuilder') -and ($Name -eq '(Default)')
        }
        Should -Invoke New-ItemProperty -Times 0 -Exactly
    }

    It 'does not create a key that the XML removes' {
        $RegistryTemplatesXml = @(Get-Item -Path (Join-Path $IMNRSFixtures 'RegistryDeleteKey.xml'))
        Import-RegistryXmlOS 6>$null
        Should -Invoke New-Item -Times 0 -Exactly -ParameterFilter {"$Path" -like 'Registry::*'}
        Should -Invoke New-ItemProperty -Times 0 -Exactly
    }

    It 'removes the key of an entry with the action D without a name' {
        $RegistryTemplatesXml = @(Get-Item -Path (Join-Path $IMNRSFixtures 'RegistryDeleteKey.xml'))
        Import-RegistryXmlOS 6>$null
        Should -Invoke Remove-Item -Times 1 -Exactly -ParameterFilter {$LiteralPath -eq 'Registry::HKEY_LOCAL_MACHINE\OfflineSoftware\OSDBuilder\Obsolete'}
    }

    It 'converts the hexadecimal REG_DWORD value to a number' {
        $Xml = (Get-Content -Path (Join-Path $IMNRSFixtures 'Registry.xml') -Raw) -replace 'value="00000001"', 'value="0000001e"'
        $RegistryTemplatesXml = @(New-TestFile -Path (Join-Path $TestDrive 'RegistryHex.xml') -Value $Xml)
        Import-RegistryXmlOS 6>$null
        Should -Invoke New-ItemProperty -Times 1 -Exactly -ParameterFilter {($Name -eq 'DisableWindowsConsumerFeatures') -and (($Value -as [long]) -eq 30)}
    }

    It 'skips an existing key' {
        $script:RegistryKeys['Registry::HKEY_LOCAL_MACHINE\OfflineSoftware\Policies\Microsoft\Windows\CloudContent'] = $true
        Import-RegistryXmlOS 6>$null
        Should -Invoke New-Item -Times 0 -Exactly -ParameterFilter {"$Path" -like '*CloudContent'}
    }

    It 'unloads twice and warns when a hive cannot be unloaded' {
        Register-RegMock -StuckHives
        $Warnings = (Import-RegistryXmlOS 6>$null 3>&1) -join "`n"
        @($script:RegCalls | Where-Object {$_ -like 'unload *'}).Count | Should -Be 8
        foreach ($Hive in 'OfflineDefaultUser', 'OfflineDefault', 'OfflineSoftware', 'OfflineSystem') {
            $Warnings | Should -BeLike "*HKLM:\$Hive could not be dismounted*"
        }
        Should -Invoke Pause -Times 4 -Exactly
    }

    It 'does nothing without XML templates' {
        $RegistryTemplatesXml = $null
        (Import-RegistryXmlOS 6>&1) | Should -BeNullOrEmpty
        Should -Invoke Start-Process -Times 0 -Exactly
    }
}

Describe 'Invoke-DismCleanupImage' {
    BeforeEach {
        $SkipUpdates = $false; $SkipComponentCleanup = $false; $OSVersion = '10.0.26100.6899'; $OSMajorVersion = 10
        $MountDirectory = 'C:\Mount'; $Info = 'C:\OSBuild\info'
        $script:Dism = [System.Collections.Generic.List[string]]::new()
        Mock dism {$script:Dism.Add((@($InputObject) + @($RemainingArguments)) -join ' '); 'Deployment Image Servicing and Management tool'}
        Mock Get-WindowsCapability {[PSCustomObject]@{Name = 'Language.Basic~~~de-DE~0.0.1.0'; State = 'Installed'}}
    }

    It 'runs StartComponentCleanup ResetBase and returns the DISM output' {
        $Output = Invoke-DismCleanupImage 6>$null
        $Output | Should -Be 'Deployment Image Servicing and Management tool'
        $script:Dism[0] | Should -BeLike '/Image:C:\Mount /Cleanup-Image /StartComponentCleanup /ResetBase /LogPath:C:\OSBuild\info\logs\*-Invoke-DismCleanupImage.log'
        Should -Invoke Get-WindowsCapability -Times 1 -Exactly -ParameterFilter {$Path -eq 'C:\Mount'}
    }

    It 'hides the DISM output and warns about the duration with -HideCleanupProgress' {
        $Result = Invoke-DismCleanupImage -HideCleanupProgress 6>$null 3>&1
        ($Result -join "`n") | Should -BeLike '*This process will take between 5 - 200 minutes*'
        $Result | Should -Not -Contain 'Deployment Image Servicing and Management tool'
        $script:Dism.Count | Should -Be 1
    }

    It 'does not check pending capabilities on Windows 8.1' {
        $OSMajorVersion = 6; $OSVersion = '6.3.9600'
        Invoke-DismCleanupImage 6>$null | Out-Null
        Should -Invoke Get-WindowsCapability -Times 0 -Exactly
        $script:Dism.Count | Should -Be 1
    }

    It 'does not clean up an image with pending capabilities' {
        Mock Get-WindowsCapability {[PSCustomObject]@{Name = 'Language.Basic~~~de-DE~0.0.1.0'; State = 'InstallPending'}}
        $Warnings = (Invoke-DismCleanupImage 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Cannot run WindowsImage Cleanup on a WIM with Pending Installations*'
        $script:Dism.Count | Should -Be 0
    }

    It 'does nothing with <Case>' -TestCases @(
        @{Case = 'SkipUpdates'; TestSkipUpdates = $true; TestSkipComponentCleanup = $false; TestOSVersion = '10.0.26100.1'}
        @{Case = 'SkipComponentCleanup'; TestSkipUpdates = $false; TestSkipComponentCleanup = $true; TestOSVersion = '10.0.26100.1'}
        @{Case = 'Windows 7'; TestSkipUpdates = $false; TestSkipComponentCleanup = $false; TestOSVersion = '6.1.7601'}
    ) {
        $SkipUpdates = $TestSkipUpdates; $SkipComponentCleanup = $TestSkipComponentCleanup; $OSVersion = $TestOSVersion
        Invoke-DismCleanupImage 6>$null | Out-Null
        $script:Dism.Count | Should -Be 0
    }
}

Describe 'Mount-ImportOSMediaWim' {
    BeforeEach {
        $MountDirectory = Join-Path $TestDrive "Mount$([guid]::NewGuid().Guid)"
        $SourceImagePath = 'D:\sources\install.wim'; $SourceImageIndex = 6; $SourceTempWim = 'C:\Temp\install.wim'
        Mock Mount-WindowsImage {}
    }

    It 'creates the mount directory and mounts the index of the install.wim read only' {
        $OSMediaGetItem = [PSCustomObject]@{Extension = '.wim'}
        $Output = (Mount-ImportOSMediaWim 6>&1) -join "`n"
        Test-Path $MountDirectory | Should -BeTrue
        Should -Invoke Mount-WindowsImage -Times 1 -Exactly -ParameterFilter {($ImagePath -eq 'D:\sources\install.wim') -and ($Index -eq 6) -and ($Path -eq $MountDirectory) -and $ReadOnly}
        $Output | Should -BeLike '*Index: 6*'
    }

    It 'mounts index 1 of the temporary wim for an install.esd' {
        $OSMediaGetItem = [PSCustomObject]@{Extension = '.esd'}
        New-Item -Path $MountDirectory -ItemType Directory -Force | Out-Null
        Mount-ImportOSMediaWim 6>$null
        Should -Invoke Mount-WindowsImage -Times 1 -Exactly -ParameterFilter {($ImagePath -eq 'C:\Temp\install.wim') -and ($Index -eq '1') -and $ReadOnly}
    }
}

Describe 'Mount-InstallwimOS' {
    It 'mounts index 1 of WimTemp\install.wim with a log' {
        $MountDirectory = 'C:\Mount'; $Info = 'C:\OSBuild\info'; $WimTemp = 'C:\OSBuild\WimTemp'
        Mock Mount-WindowsImage {}
        (Mount-InstallwimOS 6>&1) -join "`n" | Should -BeLike '*OS: Mount to C:\Mount*'
        Should -Invoke Mount-WindowsImage -Times 1 -Exactly -ParameterFilter {
            ($ImagePath -eq 'C:\OSBuild\WimTemp\install.wim') -and ($Index -eq 1) -and ($Path -eq 'C:\Mount') -and ($LogPath -like 'C:\OSBuild\info\logs\*-Mount-WindowsImage.log')
        }
    }
}

Describe 'Mount-OSDOfflineRegistryPE' {
    BeforeEach {
        Register-RegMock
        $MountPath = Join-Path $TestDrive "WinPE$([guid]::NewGuid().Guid)"
    }

    It 'loads the system profile, DEFAULT, SOFTWARE and SYSTEM hives of WinPE' {
        New-TestFile -Path (Join-Path (Join-Path (Join-Path (Join-Path (Join-Path $MountPath 'Windows') 'ServiceProfiles') 'LocalService') '.') 'NTUser.dat') | Out-Null
        New-MountedHives -MountDirectory $MountPath -Hive 'DEFAULT', 'SOFTWARE', 'SYSTEM'
        Mount-OSDOfflineRegistryPE -MountPath $MountPath
        $script:RegCalls[0] | Should -BeLike 'load HKLM\OfflineDefaultUser *Windows\ServiceProfiles\LocalService\NTUser.dat'
        $script:RegCalls[1] | Should -BeLike 'load HKLM\OfflineDefault *Windows\System32\Config\DEFAULT'
        $script:RegCalls[2] | Should -BeLike 'load HKLM\OfflineSoftware *Windows\System32\Config\SOFTWARE'
        $script:RegCalls[3] | Should -BeLike 'load HKLM\OfflineSystem *Windows\System32\Config\SYSTEM'
    }

    It 'loads only the hives that exist' {
        New-MountedHives -MountDirectory $MountPath -Hive 'SYSTEM'
        Mount-OSDOfflineRegistryPE -MountPath $MountPath
        $script:RegCalls | Should -BeLike 'load HKLM\OfflineSystem *'
    }

    It 'does nothing when the mount path does not exist' {
        Mount-OSDOfflineRegistryPE -MountPath (Join-Path $TestDrive 'Missing')
        Should -Invoke Start-Process -Times 0 -Exactly
    }
}

Describe 'Mount-PEBuild' {
    It 'mounts index 1 of the working wim' {
        $Info = 'C:\PEBuild\info'
        Mock Mount-WindowsImage {}
        Mount-PEBuild -MountDirectory 'C:\Mount\PE' -WorkingWim 'C:\PEBuild\WinPE.wim' 6>$null
        Should -Invoke Mount-WindowsImage -Times 1 -Exactly -ParameterFilter {
            ($ImagePath -eq 'C:\PEBuild\WinPE.wim') -and ($Index -eq 1) -and ($Path -eq 'C:\Mount\PE') -and ($LogPath -like 'C:\PEBuild\info\logs\*-Mount-PEBuild.log')
        }
    }
}

Describe 'Mount-WinPEwim' {
    It 'mounts WimTemp\winpe.wim to MountWinPE' {
        $MountWinPE = 'C:\Mount\WinPE'
        Mock Mount-WindowsImage {}
        (Mount-WinPEwim -OSMediaPath 'C:\OSMedia' 6>&1) -join "`n" | Should -BeLike '*Mount WinPE.wim to C:\Mount\WinPE*'
        Should -Invoke Mount-WindowsImage -Times 1 -Exactly -ParameterFilter {
            ($ImagePath -eq 'C:\OSMedia\WimTemp\winpe.wim') -and ($Path -eq 'C:\Mount\WinPE') -and ($LogPath -like 'C:\OSMedia\WinPE\info\logs\*-Mount-WindowsImage-WinPE.log')
        }
    }
}

Describe 'Mount-WinREwim' {
    It 'mounts WimTemp\winre.wim to MountWinRE' {
        $MountWinRE = 'C:\Mount\WinRE'
        Mock Mount-WindowsImage {}
        (Mount-WinREwim -OSMediaPath 'C:\OSMedia' 6>&1) -join "`n" | Should -BeLike '*Mount WinRE.wim to C:\Mount\WinRE*'
        Should -Invoke Mount-WindowsImage -Times 1 -Exactly -ParameterFilter {
            ($ImagePath -eq 'C:\OSMedia\WimTemp\winre.wim') -and ($Path -eq 'C:\Mount\WinRE') -and ($LogPath -like 'C:\OSMedia\WinPE\info\logs\*-Mount-WindowsImage-WinRE.log')
        }
    }
}

Describe 'Mount-WinSEwim' {
    It 'mounts WimTemp\winse.wim to MountWinSE' {
        $MountWinSE = 'C:\Mount\WinSE'
        Mock Mount-WindowsImage {}
        (Mount-WinSEwim -OSMediaPath 'C:\OSMedia' 6>&1) -join "`n" | Should -BeLike '*Mount WinSE.wim to C:\Mount\WinSE*'
        Should -Invoke Mount-WindowsImage -Times 1 -Exactly -ParameterFilter {
            ($ImagePath -eq 'C:\OSMedia\WimTemp\winse.wim') -and ($Path -eq 'C:\Mount\WinSE') -and ($LogPath -like 'C:\OSMedia\WinPE\info\logs\*-Mount-WindowsImage-WinSE.log')
        }
    }
}

Describe 'New-DirectoriesOSMedia' {
    It 'creates the OSMedia, info, WinPE and mount directories' {
        $Root = Join-Path $TestDrive 'OSMedia'
        $Info = Join-Path $Root 'info'; $OS = Join-Path $Root 'OS'; $WinPE = Join-Path $Root 'WinPE'; $PEInfo = Join-Path $WinPE 'info'
        $WimTemp = Join-Path $Root 'WimTemp'; $MountDirectory = Join-Path $Root 'Mount'
        $MountWinPE = Join-Path $Root 'MountWinPE'; $MountWinSE = Join-Path $Root 'MountWinSE'; $MountWinRE = Join-Path $Root 'MountWinRE'
        New-DirectoriesOSMedia
        foreach ($Path in @($Info, $OS, $WinPE, $PEInfo, $WimTemp, $MountDirectory, $MountWinPE, $MountWinSE, $MountWinRE)) {
            Test-Path -Path $Path -PathType Container | Should -BeTrue
        }
        foreach ($Folder in 'json', 'logs', 'xml') {
            Test-Path -Path (Join-Path $Info $Folder) -PathType Container | Should -BeTrue
            Test-Path -Path (Join-Path $PEInfo $Folder) -PathType Container | Should -BeTrue
        }
    }

    It 'keeps existing directories and their content' {
        $Root = Join-Path $TestDrive 'OSMediaExisting'
        $Info = Join-Path $Root 'info'; $OS = Join-Path $Root 'OS'; $WinPE = Join-Path $Root 'WinPE'; $PEInfo = Join-Path $WinPE 'info'
        $WimTemp = Join-Path $Root 'WimTemp'; $MountDirectory = Join-Path $Root 'Mount'
        $MountWinPE = Join-Path $Root 'MountWinPE'; $MountWinSE = Join-Path $Root 'MountWinSE'; $MountWinRE = Join-Path $Root 'MountWinRE'
        $Existing = New-TestFile -Path (Join-Path (Join-Path $Info 'logs') 'Import-OSMedia.log') -Value 'existing log'
        New-DirectoriesOSMedia
        Get-Content -Path $Existing.FullName | Should -Be 'existing log'
        Test-Path -Path (Join-Path $Info 'json') -PathType Container | Should -BeTrue
    }
}

Describe 'New-ItemDirectoryGetOSDBuilderHome' {
    It 'creates the missing OSDBuilder home directories' {
        $GetOSDBuilderHome = Join-Path $TestDrive 'OSDBuilder'
        $Names = 'Content', 'ContentPacks', 'FeatureUpdates', 'OSBuilds', 'OSImport', 'OSMedia', 'PEBuilds', 'Tasks', 'Templates', 'Mount', 'Updates'
        foreach ($Name in $Names) {Set-Variable -Name "SetOSDBuilderPath$Name" -Value (Join-Path $GetOSDBuilderHome $Name)}
        New-Item -Path $SetOSDBuilderPathOSMedia -ItemType Directory -Force | Out-Null
        New-TestFile -Path (Join-Path $SetOSDBuilderPathOSMedia 'keep.txt') | Out-Null
        New-ItemDirectoryGetOSDBuilderHome
        foreach ($Name in $Names) {Test-Path -Path (Join-Path $GetOSDBuilderHome $Name) -PathType Container | Should -BeTrue}
        Test-Path -Path (Join-Path $SetOSDBuilderPathOSMedia 'keep.txt') | Should -BeTrue
    }
}

Describe 'New-ItemDirectorySetOSDBuilderPathContent' {
    It 'creates the Content directories with the ADK, DaRT and IsoExtract folders' {
        $SetOSDBuilderPathContent = Join-Path $TestDrive 'Content'
        $GetOSDBuilderPathContentADK = Join-Path $SetOSDBuilderPathContent 'ADK'
        $GetOSDBuilderPathContentDaRT = Join-Path $SetOSDBuilderPathContent 'DaRT'
        $GetOSDBuilderPathContentDrivers = Join-Path $SetOSDBuilderPathContent 'Drivers'
        $GetOSDBuilderPathContentIsoExtract = Join-Path $SetOSDBuilderPathContent 'IsoExtract'
        $SetOSDBuilderPathMount = Join-Path $TestDrive 'Mount'
        $GetOSDBuilderPathContentOneDrive = Join-Path $SetOSDBuilderPathContent 'OneDrive'
        $SetOSDBuilderPathUpdates = Join-Path $TestDrive 'Updates'
        $GetOSDBuilderPathContentPackages = Join-Path $SetOSDBuilderPathContent 'Packages'
        $GetOSDBuilderPathContentScripts = Join-Path $SetOSDBuilderPathContent 'Scripts'
        $GetOSDBuilderPathContentStartLayout = Join-Path $SetOSDBuilderPathContent 'StartLayout'
        $GetOSDBuilderPathContentUnattend = Join-Path $SetOSDBuilderPathContent 'Unattend'
        New-Item -Path $SetOSDBuilderPathMount -ItemType Directory -Force | Out-Null
        New-ItemDirectorySetOSDBuilderPathContent
        foreach ($Path in @($GetOSDBuilderPathContentDrivers, $SetOSDBuilderPathMount, $GetOSDBuilderPathContentOneDrive, $SetOSDBuilderPathUpdates,
            $GetOSDBuilderPathContentPackages, $GetOSDBuilderPathContentScripts, $GetOSDBuilderPathContentStartLayout, $GetOSDBuilderPathContentUnattend,
            (Join-Path $SetOSDBuilderPathContent 'ExtraFiles'), (Join-Path $GetOSDBuilderPathContentDaRT 'DaRT 10'),
            (Join-Path (Join-Path $GetOSDBuilderPathContentADK 'Windows 10 2004') 'Windows Preinstallation Environment'),
            (Join-Path $GetOSDBuilderPathContentIsoExtract 'Windows 10 2004 FOD x64'),
            (Join-Path $GetOSDBuilderPathContentIsoExtract 'Windows Server 2019 1809 Language'))) {
            Test-Path -Path $Path -PathType Container | Should -BeTrue
        }
    }
}

Describe 'Remove-AppxProvisionedPackageOS' {
    BeforeEach {
        $ScriptName = 'New-OSBuild'; $OSMajorVersion = 10; $MountDirectory = 'C:\Mount'; $Info = 'C:\OSBuild\info'
        $RemoveAppx = @('Microsoft.BingNews_4.55.62231.0_neutral_~_8wekyb3d8bbwe', 'Microsoft.GetHelp_10.2409.22951.0_neutral_~_8wekyb3d8bbwe')
        Mock Remove-AppxProvisionedPackage {}
    }

    It 'removes every Appx package of the task' {
        Remove-AppxProvisionedPackageOS 6>$null
        foreach ($Item in $RemoveAppx) {
            Should -Invoke Remove-AppxProvisionedPackage -Times 1 -Exactly -ParameterFilter {
                ($Path -eq 'C:\Mount') -and ($PackageName -eq $Item) -and ($LogPath -like 'C:\OSBuild\info\logs\*-Remove-AppxProvisionedPackage.log')
            }
        }
    }

    It 'warns and continues when a package cannot be removed' {
        Mock Remove-AppxProvisionedPackage {throw 'The package is not provisioned'} -ParameterFilter {$PackageName -like 'Microsoft.BingNews*'}
        $Warnings = (Remove-AppxProvisionedPackageOS 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*The package is not provisioned*'
        Should -Invoke Remove-AppxProvisionedPackage -Times 1 -Exactly -ParameterFilter {$PackageName -like 'Microsoft.GetHelp*'}
    }

    It 'does nothing for <Case>' -TestCases @(
        @{Case = 'New-PEBuild'; TestScriptName = 'New-PEBuild'; TestOSMajorVersion = 10; TestRemove = @('Microsoft.BingNews')}
        @{Case = 'Windows 7'; TestScriptName = 'New-OSBuild'; TestOSMajorVersion = 6; TestRemove = @('Microsoft.BingNews')}
        @{Case = 'no packages'; TestScriptName = 'New-OSBuild'; TestOSMajorVersion = 10; TestRemove = @()}
    ) {
        $ScriptName = $TestScriptName; $OSMajorVersion = $TestOSMajorVersion; $RemoveAppx = $TestRemove
        Remove-AppxProvisionedPackageOS 6>$null
        Should -Invoke Remove-AppxProvisionedPackage -Times 0 -Exactly
    }
}

Describe 'Remove-WindowsCapabilityOS' {
    BeforeEach {
        $ScriptName = 'New-OSBuild'; $MountDirectory = 'C:\Mount'; $Info = 'C:\OSBuild\info'
        $RemoveCapability = @('App.StepsRecorder~~~~0.0.1.0', 'Browser.InternetExplorer~~~~0.0.11.0')
        Mock Remove-WindowsCapability {}
    }

    It 'removes every capability of the task' {
        Remove-WindowsCapabilityOS 6>$null
        Should -Invoke Remove-WindowsCapability -Times 2 -Exactly
        Should -Invoke Remove-WindowsCapability -Times 1 -Exactly -ParameterFilter {
            ($Path -eq 'C:\Mount') -and ($Name -eq 'App.StepsRecorder~~~~0.0.1.0') -and ($LogPath -like 'C:\OSBuild\info\logs\*-Remove-WindowsCapability.log')
        }
    }

    It 'warns and continues when a capability cannot be removed' {
        Mock Remove-WindowsCapability {throw 'Capability not present'} -ParameterFilter {$Name -like 'App.*'}
        $Warnings = (Remove-WindowsCapabilityOS 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Capability not present*'
        Should -Invoke Remove-WindowsCapability -Times 1 -Exactly -ParameterFilter {$Name -like 'Browser.*'}
    }

    It 'does nothing for <Case>' -TestCases @(
        @{Case = 'New-PEBuild'; TestScriptName = 'New-PEBuild'; TestRemove = @('App.StepsRecorder~~~~0.0.1.0')}
        @{Case = 'no capabilities'; TestScriptName = 'New-OSBuild'; TestRemove = $null}
    ) {
        $ScriptName = $TestScriptName; $RemoveCapability = $TestRemove
        Remove-WindowsCapabilityOS 6>$null
        Should -Invoke Remove-WindowsCapability -Times 0 -Exactly
    }
}

Describe 'Remove-WindowsPackageOS' {
    BeforeEach {
        $ScriptName = 'New-OSBuild'; $MountDirectory = 'C:\Mount'; $Info = 'C:\OSBuild\info'
        $RemovePackage = @('Microsoft-Windows-Hello-Face-Package~31bf3856ad364e35~amd64~~10.0.26100.1', 'Microsoft-Windows-QuickAssist-Package~31bf3856ad364e35~amd64~~10.0.26100.1')
        Mock Remove-WindowsPackage {}
    }

    It 'removes every package of the task' {
        Remove-WindowsPackageOS 6>$null
        Should -Invoke Remove-WindowsPackage -Times 2 -Exactly
        Should -Invoke Remove-WindowsPackage -Times 1 -Exactly -ParameterFilter {
            ($Path -eq 'C:\Mount') -and ($PackageName -like 'Microsoft-Windows-Hello-Face*') -and ($LogPath -like 'C:\OSBuild\info\logs\*-Remove-WindowsPackage.log')
        }
    }

    It 'warns and continues when a package cannot be removed' {
        Mock Remove-WindowsPackage {throw 'The specified package is not valid'} -ParameterFilter {$PackageName -like '*Hello-Face*'}
        $Warnings = (Remove-WindowsPackageOS 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*The specified package is not valid*'
        Should -Invoke Remove-WindowsPackage -Times 1 -Exactly -ParameterFilter {$PackageName -like '*QuickAssist*'}
    }

    It 'does nothing for <Case>' -TestCases @(
        @{Case = 'New-PEBuild'; TestScriptName = 'New-PEBuild'; TestRemove = @('Package')}
        @{Case = 'no packages'; TestScriptName = 'New-OSBuild'; TestRemove = ''}
    ) {
        $ScriptName = $TestScriptName; $RemovePackage = $TestRemove
        Remove-WindowsPackageOS 6>$null
        Should -Invoke Remove-WindowsPackage -Times 0 -Exactly
    }
}
