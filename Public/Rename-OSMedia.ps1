function Rename-OSMedia {
    <#
    .SYNOPSIS
    Renames OSMedia directories to the name Import-OSMedia and Update-OSMedia use

    .DESCRIPTION
    Builds the name of every OSMedia in the OSMedia directory from info\xml\Get-WindowsImage.xml and info\xml\CurrentVersion.xml:
    <ImageName> <Arch> <DisplayVersion or ReleaseId> <UBR> <Languages>, Windows 7 and 8.1 without the ReleaseId.
    OSMedia with a different name are listed in Out-GridView, the selected OSMedia are renamed.
    OSMedia without an OSMGuid get one.

    .EXAMPLE
    Rename-OSMedia
    #>
    [CmdletBinding()]
    param ()

    Begin {
        Get-OSDBuilder -CreatePaths -HideDetails
        $AllOSMedia = @(Get-ChildItem -Path "$SetOSDBuilderPathOSMedia" -Directory | Where-Object {Test-Path $(Join-Path $_.FullName "info\xml\Get-WindowsImage.xml")})
    }

    Process {
        $RenameOSMedia = foreach ($Item in $AllOSMedia) {
            $RenameOSMediaPath = $($Item.FullName)
            Write-Verbose "OSMedia Full Path: $RenameOSMediaPath"
            $OSMWindowsImage = Import-Clixml -Path "$RenameOSMediaPath\info\xml\Get-WindowsImage.xml"

            $OSMArch = $OSMWindowsImage.Architecture
            if ($OSMArch -eq '0') {$OSMArch = 'x86'}
            if ($OSMArch -eq '6') {$OSMArch = 'ia64'}
            if ($OSMArch -eq '9') {$OSMArch = 'x64'}
            if ($OSMArch -eq '12') {$OSMArch = 'x64 ARM'}
            $OSMBuild = $OSMWindowsImage.Build

            #=================================================
            #   OSMGuid
            #=================================================
            $OSMGuid = $($OSMWindowsImage.OSMGuid)
            if (-not ($OSMGuid)) {
                $OSMGuid = $(New-Guid)
                $OSMWindowsImage | Add-Member -Type NoteProperty -Name "OSMGuid" -Value $OSMGuid
                $OSMWindowsImage | Out-File "$RenameOSMediaPath\WindowsImage.txt"
                $OSMWindowsImage | Out-File "$RenameOSMediaPath\info\logs\$((Get-Date).ToString('yyyy-MM-dd-HHmmss'))-Get-WindowsImage.txt"
                $OSMWindowsImage | Export-Clixml -Path "$RenameOSMediaPath\info\xml\Get-WindowsImage.xml"
                $OSMWindowsImage | Export-Clixml -Path "$RenameOSMediaPath\info\xml\$((Get-Date).ToString('yyyy-MM-dd-HHmmss'))-Get-WindowsImage.xml"
                $OSMWindowsImage | ConvertTo-Json | Out-File "$RenameOSMediaPath\info\json\Get-WindowsImage.json"
                $OSMWindowsImage | ConvertTo-Json | Out-File "$RenameOSMediaPath\info\json\$((Get-Date).ToString('yyyy-MM-dd-HHmmss'))-Get-WindowsImage.json"
                (Get-Content "$RenameOSMediaPath\WindowsImage.txt") | Where-Object {$_.Trim(" `t")} | Set-Content "$RenameOSMediaPath\WindowsImage.txt"
                Write-Verbose "Guid (New): $OSMGuid"
            }
            else {
                Write-Verbose "Guid: $OSMGuid"
            }
            #=================================================
            #   ReleaseId like Import-OSMedia and Update-OSMedia: DisplayVersion, ReleaseId, Build
            #=================================================
            [string]$OSMReleaseId = ''
            if (Test-Path "$RenameOSMediaPath\info\xml\CurrentVersion.xml") {
                $OSMRegistry = Import-Clixml -Path "$RenameOSMediaPath\info\xml\CurrentVersion.xml"
                [string]$OSMReleaseId = $OSMRegistry.ReleaseId
                if ($OSMRegistry.DisplayVersion) {[string]$OSMReleaseId = $OSMRegistry.DisplayVersion}
            }
            if ($OSMBuild -eq 10240) {$OSMReleaseId = 1507}
            if ($OSMBuild -eq 14393) {$OSMReleaseId = 1607}
            if ($OSMBuild -eq 15063) {$OSMReleaseId = 1703}
            if ($OSMBuild -eq 16299) {$OSMReleaseId = 1709}
            if ($OSMBuild -eq 17134) {$OSMReleaseId = 1803}
            if ($OSMBuild -eq 17763) {$OSMReleaseId = 1809}
            Write-Verbose "ReleaseId: $OSMReleaseId"
            #=================================================
            #   Name
            #=================================================
            if ($OSMWindowsImage.MajorVersion -eq 10) {
                $FullNameFormat = "$($OSMWindowsImage.ImageName) $OSMArch $OSMReleaseId $($OSMWindowsImage.UBR) $($OSMWindowsImage.Languages)"
            }
            else {
                $FullNameFormat = "$($OSMWindowsImage.ImageName) $OSMArch $($OSMWindowsImage.UBR) $($OSMWindowsImage.Languages)"
            }
            $FullNameFormat = $FullNameFormat -replace '\(', ''
            $FullNameFormat = $FullNameFormat -replace '\)', ''
            if ($($($OSMWindowsImage.Languages).count) -eq 1) {$FullNameFormat = $FullNameFormat.replace(' en-US','')}
            $FullNameFormat = $FullNameFormat.Trim()

            if (!($Item.Name -eq $FullNameFormat)) {
                [PSCustomObject]@{
                    FullNameFormat  = $FullNameFormat
                    Name            = $Item.Name
                    FullName        = $Item.FullName
                }
            }
        }

        $RenameOSMedia = $RenameOSMedia | Select-Object FullNameFormat,Name,FullName | Out-GridView -PassThru -Title 'Rename-OSMedia: Select one or more OSMedia to Rename and press OK'
        foreach ($Item in $RenameOSMedia) {
            if (Test-Path -Path (Join-Path "$SetOSDBuilderPathOSMedia" "$($Item.FullNameFormat)")) {
                Write-Warning "Skipping $($Item.FullName), an OSMedia $($Item.FullNameFormat) already exists"
                Continue
            }
            Write-Warning "Renaming $($Item.FullName) to $($Item.FullNameFormat)"
            Rename-Item -Path "$($Item.FullName)" -NewName "$($Item.FullNameFormat)" -Force
        }
    }

    End {}
}
