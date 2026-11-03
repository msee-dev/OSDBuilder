<#
.SYNOPSIS
Applies Adobe, Component, Cumulative, Servicing Stack, and Setup Updates to Windows 10, Windows 11, Windows Server 2019, and Windows Server 2022 using Offline Servicing

.DESCRIPTION
Updates are gathered from the OSDBuilder Update Catalogs

.LINK
https://osdbuilder.osdeploy.com/module/functions/update-osmedia

.EXAMPLE
Update-OSMedia -Name 'Win10 Ent x64 1803 17134.345'

.EXAMPLE
Update-OSMedia -Name 'Win10 Ent x64 1803 17134.345' -Download

.EXAMPLE
Update-OSMedia -Name 'Win10 Ent x64 1803 17134.345' -Download -Execute

.EXAMPLE
Update-OSMedia -Name 'Win10 Ent x64 1803 17134.345' -Download -Execute -ISO

.NOTES
19.10.14 Added HideCleanupProgress
19.10.13 Added SelectUpdates SkipUpdates
#>
function Update-OSMedia {
    [CmdletBinding()]
    param (
        #The name of the OSMedia to Update
        [Parameter(ValueFromPipelineByPropertyName)]
        [string[]]$Name,

        #Creates an ISO of the Updated Media
        #oscdimg.exe from Windows ADK is required
        [Alias('ISO','OSDISO')]
        [switch]$CreateISO = $global:SetOSDBuilder.UpdateOSMediaCreateISO,

        #Automatically download the required updates if they are not present in the Content\OSDUpdate directory
        [Alias('GetDown')]
        [switch]$Download = $global:SetOSDBuilder.UpdateOSMediaDownload,

        #Excludes the specified Update Group
        #Separate multiple items with a comma -Exclude LCU,SSU
        #Enclose Groups with spaces with a single quote -Exclude 'ComponentDU Critical',LCU
        [ValidateSet(`
            'AdobeSU',`
            'ComponentDU',`
            'ComponentDU Critical',`
            'ComponentDU SafeOS',`
            'DotNet',`
            'DotNetCU',`
            'LCU',
            'SetupDU',`
            'SSU'
        )]
        [string[]]$Exclude = $global:SetOSDBuilder.UpdateOSMediaExclude,

        #Executes Update-OSMedia
        #Without this parameter, Update-OSMedia is in Sandbox Mode where changes will not be made
        [Alias('Force')]
        [switch]$Execute = $global:SetOSDBuilder.UpdateOSMediaExecute,

        #Hides the Dism Cleanup-Image Progress
        [switch]$HideCleanupProgress = $global:SetOSDBuilder.UpdateOSMediaHideCleanupProgress,

        #Includes the specified Update Group and excludes everything else
        #Separate multiple items with a comma -Include LCU,SSU
        #Enclose Groups with spaces with a single quote -Include 'ComponentDU Critical',LCU
        [ValidateSet(`
            'AdobeSU',`
            'ComponentDU',`
            'ComponentDU Critical',`
            'ComponentDU SafeOS',`
            'DotNet',`
            'DotNetCU',`
            'LCU',
            'SetupDU',`
            'SSU'
        )]
        [string[]]$Include = $global:SetOSDBuilder.UpdateOSMediaInclude,

        #Pauses the function the Install.wim is dismounted
        #Useful for Testing
        [Alias('PauseOS','PauseDismount')]
        [switch]$PauseDismountOS = $global:SetOSDBuilder.UpdateOSMediaPauseDismountOS,

        #Pauses the function before WinPE is dismounted
        #Useful for Testing
        [Alias('PausePE')]
        [switch]$PauseDismountPE = $global:SetOSDBuilder.UpdateOSMediaPauseDismountPE,

        #Allows you to select Updates to apply in GridView
        #Useful for Testing
        [switch]$SelectUpdates = $global:SetOSDBuilder.UpdateOSMediaSelectUpdates,

        #By default only the OSMedia that needs to be updated is displayed
        #This parameter includes the hidden OSMedia
        [Alias('ShowAllOSMedia','Superseded')]
        [switch]$ShowHiddenOSMedia = $global:SetOSDBuilder.UpdateOSMediaShowHiddenOSMedia,
        
        #Allows you to skip all Updates from being applied
        #Useful for Testing
        [switch]$SkipUpdates = $global:SetOSDBuilder.UpdateOSMediaSkipUpdates,

        #Skip applying updates in WinPE
        #Useful for Testing
        [switch]$SkipUpdatesPE = $global:SetOSDBuilder.UpdateOSMediaSkipUpdatesPE,

        #Skips DISM /Cleanup-Image /StartComponentCleanup /ResetBase
        #Images created for Citrix PVS require this parameter
        #Useful for testing to reduce the time
        [Alias('SkipCleanup','Citrix','PVS')]
        [switch]$SkipComponentCleanup = $global:SetOSDBuilder.UpdateOSMediaSkipComponentCleanup

        #[switch]$OSDInfo
    )

    Begin {
        #=================================================
        #   Get-OSDBuilder
        #=================================================
        Get-OSDBuilder -CreatePaths -HideDetails
        #=================================================
        #   Get-OSDUpdates
        #=================================================
        $AllOSDUpdates = @()
        $AllOSDUpdates = Get-OSDUpdates
        #=================================================
        #   Block
        #=================================================
        Block-StandardUser
        #=================================================
    }

    Process {
        Write-Host '========================================================================================' -ForegroundColor DarkGray
        Write-Host -ForegroundColor Green "$($MyInvocation.MyCommand.Name) PROCESS"
        Write-Verbose "MyInvocation.MyCommand.Name: $($MyInvocation.MyCommand.Name)"
        Write-Verbose "PSCmdlet.ParameterSetName: $($PSCmdlet.ParameterSetName)"
        #=================================================
        #   OSBuild
        #=================================================
        #=================================================
        #   Update-OSMedia
        #=================================================
        if ($Name) {
            $BirdBox = foreach ($Item in $Name) {
                Write-Verbose '========== Checking $Item'
                $ObjectProperties = @{
                    Name = $Item
                }
                New-Object -TypeName PSObject -Property $ObjectProperties
            }
        } else {
            $BirdBox = @()
            if ($ShowHiddenOSMedia.IsPresent) {
                $BirdBox = Get-OSMedia
            } else {
                $BirdBox = Get-OSMedia -Revision OK -Updates Update
            }
            $BirdBox = $BirdBox | Where-Object {($_.MajorVersion -eq 10) -or ($_.InstallationType -like "*Client*" -and $_.Version -like "6.1.7601*") -or ($_.InstallationType -like "*Server*" -and $_.Version -like "6.3*")}
            $BirdBox = $BirdBox | Out-GridView -PassThru -Title "Select one or more OSMedia to Update (Cancel to Exit) and press OK"
        }

        foreach ($Bird in $BirdBox) {
            #=================================================
            Write-Verbose '19.1.1 Set Proper Paths'
            #=================================================
            if (Test-Path "$SetOSDBuilderPathOSImport\$($Bird.Name)") {$OSMediaPath = "$SetOSDBuilderPathOSImport\$($Bird.Name)"}
            if (Test-Path "$SetOSDBuilderPathOSMedia\$($Bird.Name)") {$OSMediaPath = "$SetOSDBuilderPathOSMedia\$($Bird.Name)"}
            $OSImagePath = "$OSMediaPath\OS\sources\install.wim"

            if (!(Test-Path "$OSMediaPath\WindowsImage.txt")) {
                Write-Host '========================================================================================' -ForegroundColor DarkGray
                if ($null -eq $OSMediaPath) {
                    Write-Warning "Unable to find an OSMedia to use"
                } else {
                    Write-Warning "$OSMediaPath is not a valid OSMedia Directory"
                }
                Return
            }

            if (!(Test-Path "$OSImagePath")) {
                Write-Host '========================================================================================' -ForegroundColor DarkGray
                Write-Warning "$OSImagePath is not a valid Windows Image"
                Return
            }

            #=================================================
            Write-Verbose '19.1.1 Get Windows Image Information'
            #=================================================
            $OSImageIndex = 1
            $WindowsImage = Get-WindowsImage -ImagePath "$OSImagePath" -Index $OSImageIndex | Select-Object -Property *

            $OSImageName = $($WindowsImage.ImageName)
            $OSImageName = $OSImageName -replace '\(', ''
            $OSImageName = $OSImageName -replace '\)', ''

            $OSImageDescription = $($WindowsImage.ImageDescription)

            $OSArchitecture = $($WindowsImage.Architecture)
            if ($OSArchitecture -eq '0') {$OSArchitecture = 'x86'}
            if ($OSArchitecture -eq '6') {$OSArchitecture = 'ia64'}
            if ($OSArchitecture -eq '9') {$OSArchitecture = 'x64'}
            if ($OSArchitecture -eq '12') {$OSArchitecture = 'x64 ARM'}

            $OSEditionID =          $($WindowsImage.EditionId)
            $OSInstallationType =   $($WindowsImage.InstallationType)
            $OSLanguages =          $($WindowsImage.Languages)
            $OSVersion =            $($WindowsImage.Version)
            $OSMajorVersion =       $($WindowsImage.MajorVersion)
            $OSMinorVersion =       $($WindowsImage.MinorVersion)
            $OSBuild =              $($WindowsImage.Build)
            $OSSPBuild =            $($WindowsImage.SPBuild)
            $OSSPLevel =            $($WindowsImage.SPLevel)
            $OSImageBootable =      $($WindowsImage.ImageBootable)
            $OSWIMBoot =            $($WindowsImage.WIMBoot)
            $OSCreatedTime =        $($WindowsImage.CreatedTime)
            $OSModifiedTime =       $($WindowsImage.ModifiedTime)

            Show-MediaImageInfoOS
            #=================================================
            Write-Verbose '21.5.21 Validate Registry CurrentVersion.xml'
            #=================================================
            $RegValueCurrentBuild = $null
            if (Test-Path "$OSMediaPath\info\xml\CurrentVersion.xml") {
                $RegKeyCurrentVersion = Import-Clixml -Path "$OSMediaPath\info\xml\CurrentVersion.xml"
                
                [string]$RegValueCurrentBuild = ($RegKeyCurrentVersion).CurrentBuild
                [string]$RegValueDisplayVersion = ($RegKeyCurrentVersion).DisplayVersion
                [string]$ReleaseId = ($RegKeyCurrentVersion).ReleaseId
                if ($RegValueDisplayVersion) {$ReleaseId = $RegValueDisplayVersion}
            }
            #=================================================
            Write-Verbose '19.1.1 Set ReleaseId'
            #=================================================
            if ($null -ne $RegValueCurrentBuild) {$OSBuild = $RegValueCurrentBuild}
            if ($null -eq $ReleaseId) {
                if ($OSBuild -eq 7600) {$ReleaseId = 7600}
                if ($OSBuild -eq 7601) {$ReleaseId = 7601}
                if ($OSBuild -eq 9600) {$ReleaseId = 9600}
                if ($OSBuild -eq 10240) {$ReleaseId = 1507}
                if ($OSBuild -eq 14393) {$ReleaseId = 1607}
                if ($OSBuild -eq 15063) {$ReleaseId = 1703}
                if ($OSBuild -eq 16299) {$ReleaseId = 1709}
                if ($OSBuild -eq 17134) {$ReleaseId = 1803}
                if ($OSBuild -eq 17763) {$ReleaseId = 1809}
                #if ($OSBuild -eq 18362) {$ReleaseId = 1903}
                #if ($OSBuild -eq 18363) {$ReleaseId = 1909}
                #if ($OSBuild -eq 19041) {$ReleaseId = 2004}
                #if ($OSBuild -eq 19042) {$ReleaseId = '20H2'}
                #if ($OSBuild -eq 19043) {$ReleaseId = '21H1'}
                #if ($OSBuild -eq 19044) {$ReleaseId = '21H2'}
            }

            Write-Verbose "ReleaseId: $ReleaseId"
            Write-Verbose "CurrentBuild: $RegValueCurrentBuild"
            #=================================================
            #   Operating System
            #=================================================
            $UpdateOS = ''
            if ($OSMajorVersion -eq 10) {
                if ($OSInstallationType -match 'Server') {
                    $UpdateOS = 'Windows Server'
                }
                else {
                    if ($OSImageName -match ' 11 ') {
                        $UpdateOS = 'Windows 11'
                    }
                    else {
                        $UpdateOS = 'Windows 10'
                    }
                }
            }
            else {
                Write-Warning "$OSMediaPath is not supported"
                Continue
            }
            #=================================================
            Write-Verbose '19.1.1 WorkingName and WorkingPath'
            #=================================================
            $WorkingName = "build$((Get-Date).ToString('yyMMddhhmm'))"
            $WorkingPath = "$SetOSDBuilderPathOSMedia\$WorkingName"
            #=================================================
            Write-Verbose '19.1.1 Remove Existing OSMedia'
            #=================================================
            if (Test-Path $WorkingPath) {
                Write-Host '========================================================================================' -ForegroundColor DarkGray
                Write-Warning "$WorkingPath will be replaced!"
            }
            #=================================================
            #   WSUSXML (Microsoft Updates)
            #=================================================
            #   OSDUpdates
            #=================================================
            $OSDUpdates = $AllOSDUpdates
            if ($SkipUpdates.IsPresent) {$OSDUpdates = @()}
            $OSDUpdates = $OSDUpdates | Where-Object {$_.UpdateArch -eq $OSArchitecture}
            $OSDUpdates = $OSDUpdates | Where-Object {$_.UpdateOS -eq $UpdateOS}
            $OSDUpdates = $OSDUpdates | Where-Object {($_.UpdateBuild -eq $ReleaseId) -or ($_.UpdateBuild -eq '')}
            $OSDUpdates = $OSDUpdates | Sort-Object -Property CreationDate
            #=================================================
            #   Update Filters
            #=================================================
            if ($OSInstallationType -match 'Core'){$OSDUpdates = $OSDUpdates | Where-Object {$_.UpdateGroup -ne 'AdobeSU'}}
            if ($OSMajorVersion -eq 10) {
                $OSDUpdates = $OSDUpdates | Where-Object {$_.UpdateGroup -ne ''}
                $OSDUpdates = $OSDUpdates | Where-Object {$_.UpdateGroup -ne 'Optional'}
            }
            #=================================================
            #   Include Exclude
            #=================================================
            if ($IncludeKB) {
                $OSDUpdates = $OSDUpdates | Where-Object {$_.KBNumber -in $IncludeKB}
            }
            if ($Include) {
                $OSDUpdates = $OSDUpdates | Where-Object {$_.UpdateGroup -in $Include}
            }
            if ($Exclude) {
                $OSDUpdates = $OSDUpdates | Where-Object {$_.UpdateGroup -notin $Exclude}
            }
            if ($ExcludeKB){
                $OSDUpdates = $OSDUpdates | Where-Object {$_.KBNumber -notin $ExcludeKB}
            }
            #=================================================
            #   SelectUpdates
            #=================================================
            if ($SelectUpdates.IsPresent) {$OSDUpdates = $OSDUpdates | Out-GridView -PassThru -Title 'Select Updates to Apply and press OK'}
            $MissingUpdate = $false
            #=================================================
            #   Updates Downloaded and Not Downloaded
            #=================================================
            $UpdatesDownloaded = @()
            $UpdatesDownloaded = $OSDUpdates | Where-Object {$_.OSDStatus -eq 'Downloaded'} | Sort-Object CreationDate
            if ($UpdatesDownloaded) {
                Write-Host '========================================================================================' -ForegroundColor DarkGray
                Write-Host 'Microsoft Update Manifests Downloaded' -ForegroundColor Green
                foreach ($Update in $UpdatesDownloaded) {
                    Write-Host "$($Update.CreationDate) - " -NoNewline
                    Write-Host "$($Update.UpdateGroup)" -NoNewline -ForegroundColor Cyan
                    Write-Host " - $($Update.Title) - " -NoNewline
                    Write-Host "$($Update.FileName)" -ForegroundColor Yellow
                }
            }
            $UpdatesNotDownloaded = @()
            $UpdatesNotDownloaded = $OSDUpdates | Where-Object {$_.OSDStatus -ne 'Downloaded'}

            #OSBuild does not automatically download Optional Updates for Windows 10
            if ($OSMajorVersion -eq 10) {$UpdatesNotDownloaded = $UpdatesNotDownloaded | Where-Object {$_.UpdateGroup -ne ''} | Where-Object {$_.UpdateGroup -ne 'Optional'}}

            $UpdatesNotDownloadedOptional = @()
            $UpdatesNotDownloadedOptional = $OSDUpdates | Where-Object {$_.OSDStatus -ne 'Downloaded'} | Where-Object {$_.UpdateGroup -eq 'Optional'}

            if ($UpdatesNotDownloaded -or $UpdatesNotDownloadedOptional) {
                Write-Host '========================================================================================' -ForegroundColor DarkGray
                Write-Host 'Microsoft Update Manifests Not Downloaded' -ForegroundColor Yellow
                foreach ($Update in $UpdatesNotDownloaded) {
                    Write-Host "$($Update.CreationDate) - " -NoNewline
                    Write-Host "$($Update.UpdateGroup) - " -NoNewline -ForegroundColor Cyan
                    Write-Host "$($Update.Title) $($Update.FileName)"
                }
                foreach ($Update in $UpdatesNotDownloadedOptional) {
                    Write-Host "$($Update.CreationDate) - " -NoNewline
                    Write-Host "$($Update.UpdateGroup) - " -NoNewline -ForegroundColor Cyan
                    Write-Host "$($Update.Title) $($Update.FileName)"
                }
                if ($Download.IsPresent) {
                    Write-Host '========================================================================================' -ForegroundColor DarkGray
                    Write-Host 'Microsoft Update Manifests Download' -ForegroundColor Green
                    if ($UpdatesNotDownloadedOptional){
                        Write-Host "Optional Updates are not automatically downloaded.  Use the following command:" -ForegroundColor Yellow
                        Write-Host "Save-OSDBuilderDownload -UpdateOS '$UpdateOS' -UpdateBuild $ReleaseId -UpdateArch $OSArchitecture -UpdateGroup Optional -Download" -ForegroundColor Yellow
                    }
                    foreach ($Update in $UpdatesNotDownloaded) {
                        Write-Host "$($Update.CreationDate) - $($Update.UpdateGroup) - $($Update.Title)" -ForegroundColor Cyan
                        #Get-OSDUpdateDownloads -OSDGuid $Update.OSDGuid
                        Get-OSDUpdateDownloads -FileName $Update.FileName
                    }
                }
            }
            if ($UpdatesNotDownloaded -and (!($Download.IsPresent))) {
                $Execute = $false
                $MissingUpdate = $true
            }
            #=================================================
            #   SetupDU
            #=================================================
            $OSDUpdateSetupDU = @()
            $OSDUpdateSetupDU = $OSDUpdates | Where-Object {$_.UpdateGroup -eq 'SetupDU'}
            #=================================================
            #   ComponentDU
            #=================================================
            $OSDUpdateComponentDU = @()
            $OSDUpdateComponentDU = $OSDUpdates | Where-Object {$_.UpdateGroup -like "ComponentDU*"}
            #=================================================
            #   SSU
            #=================================================
            $OSDUpdateSSU = @()
            $OSDUpdateSSU = $OSDUpdates | Where-Object {$_.UpdateGroup -eq 'SSU'}
            #=================================================
            #   LCU
            #=================================================
            $OSDUpdateLCU = @()
            $OSDUpdateLCU = $OSDUpdates | Where-Object {$_.UpdateGroup -eq 'LCU'}
            #=================================================
            #   AdobeSU
            #=================================================
            $OSDUpdateAdobeSU = @()
            if ($OSMajorVersion -eq 10) {
                $OSDUpdateAdobeSU = $OSDUpdates | Where-Object {$_.UpdateGroup -eq 'AdobeSU'}
            }
            #=================================================
            #   DotNet
            #=================================================
            $OSDUpdateDotNet = @()
            if ($OSMajorVersion -eq 10) {
                $OSDUpdateDotNet = $OSDUpdates | Where-Object {$_.UpdateGroup -like "DotNet*"}
            }
            #=================================================
            #   OSDBuilder Seven
            #=================================================
            $OSDUpdateWinSeven = @()
            if ($UpdateOS -eq 'Windows 7') {
                $OSDUpdateWinSeven = $OSDUpdates
            }
            #=================================================
            #   OSDBuilder EightOne
            #=================================================
            $OSDUpdateWinEightOne = @()
            if ($UpdateOS -eq 'Windows 8.1') {
                $OSDUpdateWinEightOne = $OSDUpdates
                $OSDUpdateWinEightOne = $OSDUpdateWinEightOne | Where-Object {$_.UpdateGroup -ne 'SetupDU'}
                $OSDUpdateWinEightOne = $OSDUpdateWinEightOne | Where-Object {$_.UpdateGroup -notlike "ComponentDU*"}
            }
            #=================================================
            #   OSDBuilder Twelve
            #=================================================
            $OSDUpdateWinTwelveR2 = @()
            if ($UpdateOS -eq 'Windows Server 2012 R2') {
                $OSDUpdateWinTwelveR2 = $OSDUpdates
                $OSDUpdateWinTwelveR2 = $OSDUpdateWinTwelveR2 | Where-Object {$_.UpdateGroup -ne 'SetupDU'}
                $OSDUpdateWinTwelveR2 = $OSDUpdateWinTwelveR2 | Where-Object {$_.UpdateGroup -notlike "ComponentDU*"}
            }
            #=================================================
            #   Optional
            #=================================================
            $OSDUpdateOptional = @()
            #=================================================
            #   Execution Check
            #=================================================
            if ($MissingUpdate -eq $true) {
                Write-Host '========================================================================================' -ForegroundColor DarkGray
                Write-Warning "Execute is currently disabled as all Updates have not been downloaded"
                Write-Warning "You can automatically download required Updates by adding the -Download parameter"
            } elseif ($Execute -eq $false) {
                Write-Host '========================================================================================' -ForegroundColor DarkGray
                Write-Warning "Use the -Execute parameter to complete this task"
            }
            #=================================================
            if ($Execute.IsPresent) {
                #=================================================
                Write-Verbose '19.1.25 Remove Existing WorkingPath'
                #=================================================
                if (Test-Path $WorkingPath) {
                    Write-Host '========================================================================================' -ForegroundColor DarkGray
                    Remove-Item -Path "$WorkingPath" -Force -Recurse
                }
                #=================================================
                Write-Verbose '19.2.25 Set Variables'
                #=================================================
                $MountDirectory = Join-Path $SetOSDBuilderPathMount "os$((Get-Date).ToString('yyMMddhhmm'))"
                $MountWinPE = Join-Path $SetOSDBuilderPathMount "winpe$((Get-Date).ToString('yyMMddhhmm'))"
                $MountWinRE = Join-Path $SetOSDBuilderPathMount "winre$((Get-Date).ToString('yyMMddhhmm'))"
                $MountWinSE = Join-Path $SetOSDBuilderPathMount "setup$((Get-Date).ToString('yyMMddhhmm'))"
                $Info = Join-Path $WorkingPath 'info'
                    $Logs = Join-Path $Info 'logs'
                $OS = Join-Path $WorkingPath 'OS'
                $WimTemp = Join-Path $WorkingPath "WimTemp"
                $WinPE = Join-Path $WorkingPath 'WinPE'
                    $PEInfo = Join-Path $WinPE 'info'
                    $PELogs = Join-Path $PEInfo 'logs'
                #=================================================
                Write-Verbose '19.1.1 Start Transcript'
                #=================================================
                $ScriptName = $($MyInvocation.MyCommand.Name)
                $LogName = "$((Get-Date).ToString('yyyy-MM-dd-HHmmss'))-$ScriptName.log"
                Start-Transcript -Path (Join-Path "$Info\logs" $LogName) | Out-Null
                #=================================================
                #   Update-OSMedia and New-OSBuild
                #=================================================
                New-DirectoriesOSMedia
                Show-WorkingInfoOS
                Copy-MediaOperatingSystem
                #=================================================
                #   WinPE
                #=================================================
                Mount-WinPEwim -OSMediaPath "$WorkingPath"
                Mount-WinREwim -OSMediaPath "$WorkingPath"
                Mount-WinSEwim -OSMediaPath "$WorkingPath"
                Update-SetupDUMEDIA
                #=================================================
                #   WinPE ADK
                #=================================================
                $global:ReapplyLCU = $false
                $global:UpdateLanguageContent = $false
                Add-ContentADKWinPE
                Add-ContentADKWinRE
                Add-ContentADKWinSE
                Add-ContentPack -PackType PEADK
                Add-ContentPack -PackType PEADKLang
                Add-LanguagePacksWinRE
                Add-LanguagePacksWinSE
                #=================================================
                #   WinPE DaRT
                #=================================================
                Expand-DaRTPE
                Add-ContentPack -PackType PEDaRT
                #=================================================
                #   WinPE Updates
                #=================================================
                Update-ServicingStackPE
                Update-SafeOSPE
                Update-CumulativePE
                #=================================================
                #   WinPE Content
                #=================================================
                Import-AutoExtraFilesPE
                Enable-WinPEOSDCloud
                Enable-WinREWiFi
                Add-ContentExtraFilesPE
                Add-ContentDriversPE
                Add-ContentScriptsPE
                Add-ContentPack -PackType PEDrivers
                Add-ContentPack -PackType PEExtraFiles
                Add-ContentPack -PackType PEPoshMods
                Add-ContentPack -PackType PERegistry
                Add-ContentPack -PackType PEScripts
                #=================================================
                #   Update-OSMedia and New-OSBuild
                #=================================================
                Update-SourcesPE -OSMediaPath "$WorkingPath"
                Save-PackageInventoryPE -OSMediaPath "$WorkingPath"
                if ($PauseDismountPE.IsPresent){[void](Read-Host 'Press Enter to Continue')}
                Dismount-WimsPE -OSMediaPath "$WorkingPath"
                Export-PEWims -OSMediaPath "$WorkingPath"
                Export-PEBootWim -OSMediaPath "$WorkingPath"
                Save-InventoryPE -OSMediaPath "$WorkingPath"
                #=================================================
                #   Install.wim
                #=================================================
                $global:ReapplyLCU = $false
                Mount-InstallwimOS
                Set-WinREWimOS
                #=================================================
                #   Install.wim UBR Pre-Update
                #=================================================
                Show-ActionTime
                Write-Host -ForegroundColor Green "OS: Mount Registry for UBR Information"
                $RegKeyCurrentVersion = Get-RegCurrentVersion -Path $MountDirectory

                $RegValueDisplayVersion = ($RegKeyCurrentVersion).DisplayVersion
                $ReleaseId = ($RegKeyCurrentVersion).ReleaseId
                if ($RegValueDisplayVersion) {$ReleaseId = $RegValueDisplayVersion}

                if ($($RegKeyCurrentVersion.CurrentBuild)) {$RegValueCurrentBuild = $($RegKeyCurrentVersion.CurrentBuild)}
                else {$RegValueCurrentBuild = $OSSPBuild}
                if ($($RegKeyCurrentVersion.UBR)) {$RegValueUbr = $($RegKeyCurrentVersion.UBR)}
                else {$RegValueUbr = $OSSPBuild}
                $UBR = "$RegValueCurrentBuild.$RegValueUbr"
                Save-RegistryCurrentVersionOS
                $UBRPre = $UBR
                #=================================================
                #   Language Content
                #=================================================
                Add-LanguagePacksOS
                Add-ContentPack -PackType OSLanguagePacks
                Add-LanguageInterfacePacksOS
                Add-LanguageFeaturesOnDemandOS
                Add-ContentPack -PackType OSLanguageFeatures
                Add-LocalExperiencePacksOS
                Add-ContentPack -PackType OSLocalExperiencePacks
                Copy-MediaLanguageSources
                Add-ContentPack -PackType MEDIA
                if ($LanguagePacks -or $LanguageInterfacePacks -or $LanguageFeatures -or $LocalExperiencePacks -or ($global:UpdateLanguageContent -eq $true)) {
                    Set-LanguageSettingsOS
                    #Update-CumulativeOS -Force
                    #if ($HideCleanupProgress.IsPresent) {Invoke-DismCleanupImage -HideCleanupProgress} else {Invoke-DismCleanupImage}
                }
                #=================================================
                #   Optional Content
                #=================================================
                Add-ContentPack -PackType OSCapability
                Add-ContentPack -PackType OSPackages
                Add-WindowsPackageOS
                Add-FeaturesOnDemandOS
                Add-WindowsCapabilityOS
                #=================================================
                #   Install.wim Updates
                #=================================================
                Update-ComponentOS
                Update-ServicingStackOS
                #=================================================
                #   Install.wim UBR Post-Update
                #=================================================
                Show-ActionTime; Write-Host -ForegroundColor Green "OS: Update Build Revision $UBRPre (Pre-LCU)"
                if ($global:ReapplyLCU -eq $true) {Update-CumulativeOS -Force} else {Update-CumulativeOS}
                #The LCU now includes the Language and Feature on Demand content added above
                #Only content added after this point requires the LCU to be reapplied again
                $global:ReapplyLCU = $false
                #=================================================
                #   Update-OSMedia
                #=================================================
                Update-WindowsSevenOS
                Update-WindowsServer2012R2OS
                #=================================================
                #   Install.wim UBR Post-Update
                #=================================================
                $RegKeyCurrentVersion = Get-RegCurrentVersion -Path $MountDirectory

                $RegValueDisplayVersion = ($RegKeyCurrentVersion).DisplayVersion
                $ReleaseId = ($RegKeyCurrentVersion).ReleaseId
                if ($RegValueDisplayVersion) {$ReleaseId = $RegValueDisplayVersion}

                if ($($RegKeyCurrentVersion.CurrentBuild)) {$RegValueCurrentBuild = $($RegKeyCurrentVersion.CurrentBuild)}
                else {$RegValueCurrentBuild = $OSSPBuild}
                if ($($RegKeyCurrentVersion.UBR)) {$RegValueUbr = $($RegKeyCurrentVersion.UBR)}
                else {$RegValueUbr = $OSSPBuild}
                $UBR = "$RegValueCurrentBuild.$RegValueUbr"
                Save-RegistryCurrentVersionOS
                Show-ActionTime
                Write-Host -ForegroundColor Green "OS: Update Build Revision $UBR (Post-LCU)"
                #=================================================
                #   Update-OSMedia and New-OSBuild
                #=================================================
                Update-AdobeOS
                Update-DotNetOS
                Update-OptionalOS
                #=================================================
                #   OneDriveSetup
                #=================================================
                $UpdateOneDrive = $true
                if ($OSMajorVersion -ne 10) {$UpdateOneDrive = $false}
                if ($OSInstallationType -ne 'Client') {$UpdateOneDrive = $false}
                if ((!(Test-Path "$MountDirectory\Windows\System32\OneDriveSetup.exe")) -and (!(Test-Path "$MountDirectory\Windows\SysWOW64\OneDriveSetup.exe"))) {$UpdateOneDrive = $false}

                if ($UpdateOneDrive -eq $true) {
                    Show-ActionTime
                    Write-Host -ForegroundColor Green "OS: Update OneDriveSetup.exe"
                    $OneDriveSetupDownload = $false
                    $OneDriveSetup = Join-Path $GetOSDBuilderPathContentOneDrive 'OneDriveSetup.exe'
                    if (!(Test-Path $OneDriveSetup)) {$OneDriveSetupDownload = $true}

                    if (Test-Path $OneDriveSetup) {
                        if (!(([System.Io.fileinfo]$OneDriveSetup).LastWriteTime.Date -ge [datetime]::Today )) {
                            $OneDriveSetupDownload = $true
                        }
                    }
<#                     if ($OneDriveSetupDownload -eq $true) {
                        $WebClient = New-Object System.Net.WebClient
                        Write-Host "Downloading to $OneDriveSetup" -ForegroundColor Gray
                        $WebClient.DownloadFile('https://go.microsoft.com/fwlink/p/?LinkId=248256',"$OneDriveSetup")
                    } #>

                    if ($OSArchitecture -eq 'x86') {
                        if (Test-Path "$MountDirectory\Windows\System32\OneDriveSetup.exe") {
                            $OneDriveSetupInfo = Get-Item -Path "$MountDirectory\Windows\System32\OneDriveSetup.exe" | Select-Object -Property *
                            Write-Host -ForegroundColor Gray "                  Existing Image Version $($($OneDriveSetupInfo).VersionInfo.ProductVersion)"
                            if (Test-Path $OneDriveSetup) {
                                robocopy "$GetOSDBuilderPathContentOneDrive" "$MountDirectory\Windows\System32" OneDriveSetup.exe /ndl /xx /b /np /ts /tee /r:0 /w:0 /Log+:"$Info\logs\$((Get-Date).ToString('yyyy-MM-dd-HHmmss'))-Update-OneDriveSetup.log" | Out-Null
                                $OneDriveSetupInfo = Get-Item -Path "$MountDirectory\Windows\System32\OneDriveSetup.exe" | Select-Object -Property *
                                Write-Host -ForegroundColor Gray "                  Updating with Version $($($OneDriveSetupInfo).VersionInfo.ProductVersion)"
                            }
                        }
                    } else {
                        if (Test-Path "$MountDirectory\Windows\SysWOW64\OneDriveSetup.exe") {
                            $OneDriveSetupInfo = Get-Item -Path "$MountDirectory\Windows\SysWOW64\OneDriveSetup.exe" | Select-Object -Property *
                            Write-Host -ForegroundColor Gray "                  Existing Image Version $($($OneDriveSetupInfo).VersionInfo.ProductVersion)"
                            if (Test-Path $OneDriveSetup) {
                                robocopy "$GetOSDBuilderPathContentOneDrive" "$MountDirectory\Windows\SysWOW64" OneDriveSetup.exe /ndl /xx /b /np /ts /tee /r:0 /w:0 /Log+:"$Info\logs\$((Get-Date).ToString('yyyy-MM-dd-HHmmss'))-Update-OneDriveSetup.log" | Out-Null
                                $OneDriveSetupInfo = Get-Item -Path "$MountDirectory\Windows\SysWOW64\OneDriveSetup.exe" | Select-Object -Property *
                                Write-Host -ForegroundColor Gray "                  Updating with Version $($($OneDriveSetupInfo).VersionInfo.ProductVersion)"
                            }
                        }
                    }
                    Write-Host -ForegroundColor Cyan "                  To update OneDriveSetup.exe use one of the following commands:"
                    Write-Host -ForegroundColor Cyan "                  Save-OSDBuilderDownload -ContentDownload 'OneDriveSetup Enterprise'"
                    Write-Host -ForegroundColor Cyan "                  Save-OSDBuilderDownload -ContentDownload 'OneDriveSetup Production'"
                }
                #=================================================
                #	DismCleanupImage
                #=================================================
                if ($global:ReapplyLCU -eq $true) {Update-CumulativeOS -Force}
                if ($HideCleanupProgress.IsPresent) {Invoke-DismCleanupImage -HideCleanupProgress} else {Invoke-DismCleanupImage}
                #=================================================
                #   Content
                #=================================================
                Enable-WindowsOptionalFeatureOS
                Enable-NetFXOS
                Update-InboxAppsOS
                Remove-AppxProvisionedPackageOS
                Remove-WindowsPackageOS
                Remove-WindowsCapabilityOS
                Disable-WindowsOptionalFeatureOS
                Add-ContentDriversOS
                Add-ContentExtraFilesOS
                Add-ContentStartLayout
                Add-ContentUnattend
                Add-ContentScriptsOS
                Import-RegistryRegOS
                Import-RegistryXmlOS
                Add-ContentPack -PackType OSDrivers
                Add-ContentPack -PackType OSExtraFiles
                Add-ContentPack -PackType OSPoshMods
                Add-ContentPack -PackType OSRegistry
                Add-ContentPack -PackType OSScripts
                Add-ContentPack -PackType OSStartLayout
                #=================================================
                #	Updates
                #=================================================
                #Update-ServicingStackOS -Force
                #=================================================
                #	Mirror OSMedia and OSBuild
                #=================================================
                Save-AutoExtraFilesOS -OSMediaPath "$WorkingPath"
                Save-SessionsXmlOS -OSMediaPath "$WorkingPath"
                Save-InventoryOS -OSMediaPath "$WorkingPath"
                #=================================================
                #   Dismount
                #=================================================
                if ($PauseDismountOS.IsPresent){[void](Read-Host 'Press Enter to Continue')}
                Dismount-InstallwimOS
                Export-InstallwimOS
                #=================================================
                Write-Verbose '19.1.1 OS: Export Configuration'
                #=================================================
                Show-ActionTime
                Write-Host -ForegroundColor Green "OS: Export Configuration to $WorkingPath\WindowsImage.txt"
                $GetWindowsImage = @()
                $GetWindowsImage = Get-WindowsImage -ImagePath "$OS\sources\install.wim" -Index 1 | Select-Object -Property *

                Write-Verbose "========== SPBuild: $($GetWindowsImage.Build).$($GetWindowsImage.SPBuild)"
                if ($OSVersion -like "6.*") {
                    Write-Verbose '========== Windows 6.x'
                    $UBR = "$($GetWindowsImage.Build).$($GetWindowsImage.SPBuild)"
                }
                Write-Verbose "========== UBR: $UBR"

                $GetWindowsImage | Add-Member -Type NoteProperty -Name "UBR" -Value $UBR
                $GetWindowsImage | Out-File "$WorkingPath\WindowsImage.txt"
                $GetWindowsImage | Out-File "$Info\logs\$((Get-Date).ToString('yyyy-MM-dd-HHmmss'))-Get-WindowsImage.txt"
                $GetWindowsImage | Export-Clixml -Path "$Info\xml\Get-WindowsImage.xml"
                $GetWindowsImage | Export-Clixml -Path "$Info\xml\$((Get-Date).ToString('yyyy-MM-dd-HHmmss'))-Get-WindowsImage.xml"
                $GetWindowsImage | ConvertTo-Json | Out-File "$Info\json\Get-WindowsImage.json"
                $GetWindowsImage | ConvertTo-Json | Out-File "$Info\json\$((Get-Date).ToString('yyyy-MM-dd-HHmmss'))-Get-WindowsImage.json"
                (Get-Content "$WorkingPath\WindowsImage.txt") | Where-Object {$_.Trim(" `t")} | Set-Content "$WorkingPath\WindowsImage.txt"
                
                #=================================================
                #    OSD-Export
                #=================================================
                #Save-WindowsImageContentPE

                #=================================================
                Write-Verbose '19.3.17 UBR Validation'
                #=================================================
                if ($UBRPre -eq $UBR) {
                    Write-Host '========================================================================================' -ForegroundColor DarkGray
                    Write-Warning 'The Update Build Revision did not change after Windows Updates'
                    Write-Warning 'There may have been an issue applying the Latest Cumulative Update if this was not expected'
                }
                if (!($UBR)) {
                    Write-Host '========================================================================================' -ForegroundColor DarkGray
                    $UBR = $((Get-Date).ToString('yyMMddhhmm'))
                    Write-Warning 'Could not determine a UBR'
                }

                #=================================================
                Write-Verbose '19.1.1 Remove Temporary Files'
                #=================================================
                if (Test-Path "$WimTemp") {Remove-Item -Path "$WimTemp" -Force -Recurse | Out-Null}
                if (Test-Path "$MountDirectory") {Remove-Item -Path "$MountDirectory" -Force -Recurse | Out-Null}
                if (Test-Path "$MountWinRE") {Remove-Item -Path "$MountWinRE" -Force -Recurse | Out-Null}
                if (Test-Path "$MountWinPE") {Remove-Item -Path "$MountWinPE" -Force -Recurse | Out-Null}
                if (Test-Path "$MountWinSE") {Remove-Item -Path "$MountWinSE" -Force -Recurse | Out-Null}

                #=================================================
                Write-Verbose '19.1.1 Set New Name'
                #=================================================
                $OSImageName = $($GetWindowsImage.ImageName)
                $OSImageName = $OSImageName -replace '\(', ''
                $OSImageName = $OSImageName -replace '\)', ''

                $OSArchitecture = $($GetWindowsImage.Architecture)
                if ($OSArchitecture -eq '0') {$OSArchitecture = 'x86'}
                if ($OSArchitecture -eq '6') {$OSArchitecture = 'ia64'}
                if ($OSArchitecture -eq '9') {$OSArchitecture = 'x64'}
                if ($OSArchitecture -eq '12') {$OSArchitecture = 'x64 ARM'}

                $OSBuild = $($GetWindowsImage.Build)
                $ReleaseId = $null
                if (Test-Path "$Info\xml\CurrentVersion.xml") {
                    $RegKeyCurrentVersion = Import-Clixml -Path "$Info\xml\CurrentVersion.xml"
                    [string]$RegValueDisplayVersion = ($RegKeyCurrentVersion).DisplayVersion
                    [string]$ReleaseId = ($RegKeyCurrentVersion).ReleaseId
                    if ($RegValueDisplayVersion) {$ReleaseId = $RegValueDisplayVersion}
                }
                if ($OSBuild -eq 7600) {$ReleaseId = 7600}
                if ($OSBuild -eq 7601) {$ReleaseId = 7601}
                if ($OSBuild -eq 9600) {$ReleaseId = 9600}
                if ($OSBuild -eq 10240) {$ReleaseId = 1507}
                if ($OSBuild -eq 14393) {$ReleaseId = 1607}
                if ($OSBuild -eq 15063) {$ReleaseId = 1703}
                if ($OSBuild -eq 16299) {$ReleaseId = 1709}
                if ($OSBuild -eq 17134) {$ReleaseId = 1803}
                if ($OSBuild -eq 17763) {$ReleaseId = 1809}
                #if ($OSBuild -eq 18362) {$ReleaseId = 1903}
                #if ($OSBuild -eq 18363) {$ReleaseId = 1909}
                #if ($OSBuild -eq 19041) {$ReleaseId = 2004}
                #if ($OSBuild -eq 19042) {$ReleaseId = '20H2'}
                #if ($OSBuild -eq 19043) {$ReleaseId = '21H1'}
                #if ($OSBuild -eq 19044) {$ReleaseId = '21H2'}

                if ($OSMajorVersion -eq 10) {
                    if ($WorkingName -like "build*") {$NewOSMediaName = "$OSImageName $OSArchitecture $ReleaseId $UBR"}
                } else {
                    if ($WorkingName -like "build*") {$NewOSMediaName = "$OSImageName $OSArchitecture $UBR"}
                }

                $OSLanguages = $($GetWindowsImage.Languages)

                $NewOSMediaName = "$NewOSMediaName $OSLanguages"
                if ($($OSLanguages.count) -eq 1) {$NewOSMediaName = $NewOSMediaName.replace(' en-US','')}

                
                $NewOSMediaPath = "$SetOSDBuilderPathOSMedia\$NewOSMediaName"
                #=================================================
                #   19.1.1 Rename Build Directory
                #=================================================
                if (Test-Path $NewOSMediaPath) {
                    $yyMMddhhmm = $((Get-Date).ToString('yyMMddhhmm'))
                    Write-Host '========================================================================================' -ForegroundColor DarkGray
                    Write-Warning 'Trying to rename the Build directory, but it already exists'
                    Write-Warning "Appending $yyMMddhhmm to the directory Name"
                    Write-Host '========================================================================================' -ForegroundColor DarkGray
                    $NewOSMediaName = "$NewOSMediaName $yyMMddhhmm"

                    $NewOSMediaPath = "$SetOSDBuilderPathOSMedia\$NewOSMediaName"
                }
                #=================================================
                #   OSD-Export
                #=================================================
                Save-WindowsImageContentOS
                Save-VariablesOSD
                #=================================================
                #   OSDBuilder Media'
                #=================================================
                if ($CreateISO.IsPresent) {New-OSDBuilderISO -FullName "$WorkingPath"}
                #=================================================
                #   Complete Update
                #=================================================
				Show-ActionTime
				Write-Host -ForegroundColor Green "Media: Renaming ""$WorkingPath"" to ""$NewOSMediaName"""
                Write-Host '========================================================================================' -ForegroundColor DarkGray
                Stop-Transcript | Out-Null
                try {
                    Rename-Item -Path "$WorkingPath" -NewName "$NewOSMediaName" -Force
                }
                catch {
                    Write-Warning "Could not rename the the Build directory ... Waiting 30 seconds ..."
                    Start-Sleep -Seconds 30
                }
                if (Test-Path "$WorkingPath") {
                    try {
                        Rename-Item -Path "$WorkingPath" -NewName "$NewOSMediaName" -Force
                    }
                    catch {
                        Write-Warning "Could not rename the the Build directory ..."
                    }
                }
<#                 if (Test-Path "$NewOSMediaPath") {
                    Return (Get-OSMedia | Where-Object {$_.FullName -eq $NewOSMediaPath})
                } else {
                    Return (Get-OSMedia | Where-Object {$_.FullName -eq $WorkingPath})
                } #>
            }
        }
    }

    End {
        #Write-Host '========================================================================================' -ForegroundColor DarkGray
        #Write-Host -ForegroundColor Green "$($MyInvocation.MyCommand.Name) END"
    }
}