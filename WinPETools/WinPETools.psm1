function Get-WinPESupportedArchitecture {
<#
.SYNOPSIS

Returns supported Assessment and Deployment Kit (ADK) architectures.

Author: Matthew Graeber (@mattifestation)
License: BSD 3-Clause

.DESCRIPTION

Get-WinPESupportedArchitecture returns the supported Assessment and Deployment Kit (ADK) architectures for a WinPE image. Get-ADKSupportedArchitecture must be run from within the Deployment and Imaging Tools Environment.

.OUTPUTS

PSObject

Outputs a custom object consisting of the supported architecture and its respective path.
#>
    if (-not $Env:WinPERoot) {
        throw "$($MyInvocation.InvocationName) must execute from within the Deployment and Imaging Tools Environment."
    }

    Get-ChildItem -Path $Env:WinPERoot -Directory | ForEach-Object {
        [PSCustomObject] @{
            Architecture = $_.Name
            Path = $_.FullName
        }
    }
}

function Get-WinPEPackagePath {
<#
.SYNOPSIS

Returns the path to standard ADK WinPE packages for the specified architecture.

Author: Matthew Graeber (@mattifestation)
License: BSD 3-Clause

.EXAMPLE

Get-WinPEWinPEPackagePath -Architecture amd64

.OUTPUTS

String

Outputs the path to ADK WinPE packages.
#>

    [OutputType([String])]
    param (
        [Parameter(Mandatory = $True)]
        [String]
        [ValidateSet('amd64', 'x86', 'arm', 'arm64')]
        $Architecture
    )

    if (-not $Env:WinPERoot) {
        throw "$($MyInvocation.InvocationName) must execute from within the Deployment and Imaging Tools Environment."
    }

    $CabRootPath = Join-Path $Env:WinPERoot "$Architecture\WinPE_OCs"

    if (-not (Test-Path $CabRootPath)) {
        throw "WinPE package directory not found: $CabRootPath"
    }

    $CabRootPath
}

function Get-WinPEPackageCab {
<#
.SYNOPSIS

Returns the a list of CAB files that can be added as packages to a mounted WinPE image.

Author: Matthew Graeber (@mattifestation)
License: BSD 3-Clause

.EXAMPLE

Get-WinPEPackageCab -Architecture amd64

.OUTPUTS

System.IO.FileInfo

Outputs file information for each available WinPE Windows package.
#>

    [OutputType([System.IO.FileInfo])]
    param (
        [Parameter(Mandatory = $True)]
        [String]
        [ValidateSet('amd64', 'x86', 'arm', 'arm64')]
        $Architecture
    )

    if (-not $Env:WinPERoot) {
        throw "$($MyInvocation.InvocationName) must execute from within the Deployment and Imaging Tools Environment."
    }

    $CabRootPath = Join-Path $Env:WinPERoot "$Architecture\WinPE_OCs"

    if (-not (Test-Path $CabRootPath)) {
        throw "WinPE package directory not found: $CabRootPath"
    }

    $CabEnglishPath = Join-Path $CabRootPath 'en-us'

    Get-ChildItem -Path $CabRootPath -Filter WinPE-*.cab
    Get-ChildItem -Path $CabEnglishPath -Filter WinPE-*.cab
}

function New-WinPEWorkingDirectory {
<#
.SYNOPSIS

Creates working directories for WinPE image customization and media creation.

Author: Matthew Graeber (@mattifestation)
License: BSD 3-Clause

.DESCRIPTION

New-WinPEWorkingDirectory creates working directories for WinPE image customization and media creation. New-WinPEWorkingDirectory is a PowerShell implementation of copype.cmd.

.PARAMETER Architecture

Specifies the desired WinPE image architecture.

.PARAMETER WorkingDirectory

Specifies the path to the image working directory. This directory must not exist prior to running New-WinPEWorkingDirectory. If no working directory is specified, New-WinPEImageWorkingDirectory will default to creating a 'WinPE_WorkingDir' directory in the current working directory.

.PARAMETER Mount

Specifies that the WinPE image should be mounted. Mounted images are present in the 'mount' directory within the working directory. If -Mount is no specified, use the Mount-WindowsImage cmdlet to mount <WORKDING_DIR>\media\sources\boot.wim.

.EXAMPLE

$NewWinPEMountedImage = New-WinPEWorkingDirectory -Architecture amd64 -WorkingDirectory C:\WinPE_amd64 -Mount

Creates an amd64 WinPE image in C:\WinPE_amd64 and mounts the image.

.EXAMPLE

$NewWinPEDirectory = New-WinPEWorkingDirectory -Architecture x86

Creates an x86 WinPE image in %CWD%\WinPE_WorkingDir. The image is not mounted.

.OUTPUTS

System.IO.DirectoryInfo

Outputs the directory containing the new WinPE image working directory. A DirectoryInfo object is only returned if -Mount is not specified.

Microsoft.Dism.Commands.ImageObject

If -Mount is specified, an object representing the mounted image is returned.
#>

    [OutputType([System.IO.DirectoryInfo])]
    [CmdletBinding(SupportsShouldProcess = $True)]
    param (
        [Parameter(Mandatory = $True)]
        [String]
        [ValidateSet('amd64', 'x86', 'arm', 'arm64')]
        $Architecture,

        [String]
        [ValidateNotNullOrEmpty()]
        $WorkingDirectory = (Join-Path $PWD WinPE_WorkingDir),

        [Switch]
        $Mount
    )

    if ((-not $Env:OSCDImgRoot) -or (-not $Env:WinPERoot)) {
        throw "$($MyInvocation.InvocationName) must execute from within the Deployment and Imaging Tools Environment."
    }

    $SourcePath = Resolve-Path (Join-Path $Env:WinPERoot $Architecture)

    if (-not (Test-Path $SourcePath)) {
        throw "The following processor architecture was not found: $Architecture"
    }

    $FWFilesRoot = Resolve-Path (Join-Path $Env:OSCDImgRoot "..\..\$Architecture\Oscdimg")

    if (-not (Test-Path $FWFilesRoot)) {
        throw "The following path for firmware files was not found: $FWFilesRoot"
    }

    $WIMSourcePath = Resolve-Path (Join-Path $SourcePath 'en-us\winpe.wim')

    if (-not (Test-Path $WIMSourcePath)) {
        throw "WinPE WIM file does not exist: $WIMSourcePath"
    }

    if (Test-Path $WorkingDirectory) {
        throw "Destination directory exists: $WorkingDirectory"
    }

    Write-Verbose 'Creating working directory...'
    $null = New-Item -ItemType Directory -Path $WorkingDirectory -ErrorAction Stop
    Write-Verbose "Working directory created: $WorkingDirectory"

    $MediaDirPath = Join-Path $WorkingDirectory 'media'

    Write-Verbose 'Creating media directory...'
    $null = New-Item -ItemType Directory -Path $MediaDirPath -ErrorAction Stop
    Write-Verbose "Media directory created: $MediaDirPath"

    $MountDirPath = Join-Path $WorkingDirectory 'mount'

    Write-Verbose 'Creating mount directory...'
    $null = New-Item -ItemType Directory -Path $MountDirPath -ErrorAction Stop
    Write-Verbose "Mount directory created: $MountDirPath"

    $FWFilesPath = Join-Path $WorkingDirectory 'fwfiles'

    Write-Verbose 'Creating firmware files directory...'
    $null = New-Item -ItemType Directory -Path $FWFilesPath -ErrorAction Stop
    Write-Verbose "Firmware files directory created: $FWFilesPath"

    Write-Verbose 'Copying the boot files and WinPE WIM to the destination location...'
    Get-ChildItem -Path (Join-Path $SourcePath 'Media') | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination (Join-Path $MediaDirPath $_) -Recurse -Force -ErrorAction Stop
    }

    $DestSourcesPath = Join-Path $MediaDirPath 'sources'
    $null = New-Item -ItemType Directory -Path $DestSourcesPath -ErrorAction Stop

    $WIMDestPath = Join-Path $DestSourcesPath 'boot.wim'

    Copy-Item -Path $WIMSourcePath -Destination $WIMDestPath -ErrorAction Stop
    Write-Verbose 'Copying of boot files and WinPE WIM to the destination location complete.'

    Write-Verbose 'Copying the boot sector files to enable ISO creation and boot...'
    # UEFI boot uses efisys.bin
    # BIOS boot uses etfsboot.com
    Copy-Item -Path (Join-Path $FWFilesRoot 'efisys.bin') -Destination $FWFilesPath -ErrorAction Stop

    $EtfsbootPath = Join-Path $FWFilesRoot 'etfsboot.com'
    if (Test-Path $EtfsbootPath) {
        Copy-Item -Path $EtfsbootPath -Destination $FWFilesPath -ErrorAction Stop
    }
    Write-Verbose 'Copying of boot sector files to enable ISO creation and boot complete.'

    Write-Verbose 'WinPE working directory successfully created.'

    if (-not $PSBoundParameters.ContainsKey('WhatIf') -and (-not $PSBoundParameters.ContainsKey('Mount'))) {
        # Return the newly created working directory
        [IO.DirectoryInfo] $WorkingDirectory
    }

    if ($PSBoundParameters.ContainsKey('Mount')) {
        $BootWimPath = Join-Path $WorkingDirectory 'media\sources\boot.wim'
        $MountPath = Join-Path $WorkingDirectory 'mount'

        # Mount-WindowsImage doesn't support -WhatIf so the following will handle it.
        if ($PSCmdlet.ShouldProcess("$MountPath", "Mount WinPE Image: $BootWimPath")) {
            Mount-WindowsImage -ImagePath $BootWimPath -Index 1 -Path $MountPath
        }
    }
}

function Test-WinPEWorkingDirectory {
<#
.SYNOPSIS

Validates a WinPE working directory.

Author: Matthew Graeber (@mattifestation)
License: BSD 3-Clause

.PARAMETER WorkingDirectory

Specifies the path to the WinPE working directory.

.EXAMPLE

'C:\WinPE_amd64' | Test-WinPEWorkingDirectory

.EXAMPLE

Test-WinPEWorkingDirectory -WorkingDirectory 'C:\WinPE_x86'

.EXAMPLE

$WorkingDir = New-WinPEWorkingDirectory -Architecture amd64
$WorkingDir | Test-WinPEWorkingDirectory

.EXAMPLE

$MountedImage = New-WinPEWorkingDirectory -Architecture amd64 -Mount
$MountedImage | Test-WinPEWorkingDirectory

.INPUTS

Test-WinPEWorkingDirectory accepts the output of New-WinPEWorkingDirectory, Get-ChildItem, and Get-WindowsImage.

.OUTPUTS

PSCustomObject

Outputs a custom object indicating whether or not the working directory is valid and if the WinPE image is mounted.
#>

    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $True, ValueFromPipelineByPropertyName = $True, Mandatory = $True)]
        [String]
        [Alias('FullName')] # Alias to capture pipeline output of Get-ChildItem
        [Alias('Path')] # Alias to capture pieline output of a mounted Windows image
        [ValidateNotNullOrEmpty()]
        $WorkingDirectory
    )

    # This won't be a perfect test since I can't validate the presence
    # of all conceivable file and folder configurations for all present and
    # future ADK versions but this is close enough.

    $InvalidWinPEWorkingDir = ([PSCustomObject] @{ Valid = $False; Mounted = $False })

    $FullWorkingDirPath = Resolve-Path $WorkingDirectory

    if ((Split-Path $FullWorkingDirPath -Leaf) -eq 'mount') {
        $FullWorkingDirPath = Split-Path $FullWorkingDirPath -Parent
    }

    if (-not ([IO.Directory]::Exists($FullWorkingDirPath))) {
        Write-Verbose "The provided working directory is not a directory: $FullWorkingDirPath"
        return $InvalidWinPEWorkingDir
    }

    $BootWim = 'media\sources\boot.wim'

    $Required = @(
        'fwfiles',
        'media',
        'mount',
        'fwfiles\efisys.bin',
        'media\bootmgr',
        'media\bootmgr.efi',
        $BootWim,
        'media\Boot\BCD'
    )

    foreach ($Item in $Required) {
        $FullPath = Join-Path $FullWorkingDirPath $Item

        if (-not (Test-Path $FullPath)) {
            Write-Verbose "Required file or directory does not exist in the working directory: $FullPath"
            return $InvalidWinPEWorkingDir
        }
    }

    $BootWimPath = Join-Path $FullWorkingDirPath $BootWim
    $WinPEImage = Get-WindowsImage -ImagePath $BootWimPath -ErrorAction Ignore

    if ($WinPEImage) {
        $MountedImages = Get-WindowsImage -Mounted

        foreach ($MountedImage in $MountedImages) {
            if ($MountedImage.ImagePath -eq $BootWimPath) {
                return ([PSCustomObject] @{ Valid = $True; Mounted = $True })
            }
        }

        return ([PSCustomObject] @{ Valid = $True; Mounted = $False })
    } else {
        Write-Verbose "The working directory does not contain a valid boot.wim image: $BootWimPath"
        return $InvalidWinPEWorkingDir
    }
}

function Add-WinPEPowerShell {
<#
.SYNOPSIS

Add a standard set of packages needed to run PowerShell in the WinPE image.

Author: Matthew Graeber (@mattifestation)
License: BSD 3-Clause

.PARAMETER WorkingDirectory

Specifies the path to the WinPE working directory.

.EXAMPLE

$MountedImage = New-WinPEWorkingDirectory -Architecture amd64 -Mount
$MountedImage | Add-WinPEPowerShell

.INPUTS

Add-WinPEPowerShell accepts the output of New-WinPEWorkingDirectory, Get-ChildItem, and Get-WindowsImage.
#>

    [CmdletBinding(SupportsShouldProcess = $True)]
    param (
        [Parameter(ValueFromPipeline = $True, ValueFromPipelineByPropertyName = $True, Mandatory = $True)]
        [String]
        [Alias('FullName')] # Alias to capture pipeline output of Get-ChildItem
        [Alias('Path')] # Alias to capture pieline output of a mounted Windows image
        [ValidateNotNullOrEmpty()]
        $WorkingDirectory
    )

    $CommonArg = @{}
    if ($PSBoundParameters['Verbose']) { $CommonArg['Verbose'] = $True }

    $FullWorkingDirPath = Resolve-Path $WorkingDirectory

    if ((Split-Path $FullWorkingDirPath -Leaf) -eq 'mount') {
        $FullWorkingDirPath = Split-Path $FullWorkingDirPath -Parent
    }

    $Result = Test-WinPEWorkingDirectory -WorkingDirectory $FullWorkingDirPath

    if (-not $Result.Valid) {
        throw "An invalid WinPE working directory was provided: $FullWorkingDirPath"
    }

    $BootWimPath = Join-Path $FullWorkingDirPath 'media\sources\boot.wim'

    if (-not $Result.Mounted) {
        $MountPath = Join-Path $FullWorkingDirPath 'mount'

        $MountCommand = "Mount-WindowsImage -ImagePath $BootWimPath -Index 1 -Path $MountPath"

        throw "The working directory provided does not contain a mounted image: $FullWorkingDirPath. You can mount the working image within the working directory with the following command: $MountCommand"
    }

    # Obtain the image architecture without requiring the user to specify it.
    $Architecture = $null
    $ImageInfo = Get-WindowsImage -ImagePath $BootWimPath -ErrorAction Stop

    switch ($ImageInfo.ImageName) {
        'Microsoft Windows PE (x86)' { $Architecture = 'x86' }
        'Microsoft Windows PE (x64)' { $Architecture = 'amd64' }
    }

    if (-not $Architecture) {
        throw 'Unable to obtain a WinPE image architecture.'
    }

    Write-Verbose "WinPE image architecture: $Architecture"

    # Get the base WinPE package directory for the specified arch
    $CabPath = Get-WinPEPackagePath -Architecture $Architecture -ErrorAction Stop @CommonArg

    # All of the packages we're going to want for the base image
    $PackagesToInstall = @(
        'WinPE-WMI.cab',
        'en-us\WinPE-WMI_en-us.cab',
        'WinPE-NetFx.cab',
        'en-us\WinPE-NetFx_en-us.cab',
        'WinPE-Scripting.cab',
        'en-us\WinPE-Scripting_en-us.cab',
        'WinPE-PowerShell.cab',
        'en-us\WinPE-PowerShell_en-us.cab',
        'WinPE-DismCmdlets.cab',
        'en-us\WinPE-DismCmdlets_en-us.cab',
        'WinPE-EnhancedStorage.cab',
        'en-us\WinPE-EnhancedStorage_en-us.cab',
        'WinPE-StorageWMI.cab',
        'en-us\WinPE-StorageWMI_en-us.cab',
        'WinPE-SecureStartup.cab',
        'en-us\WinPE-SecureStartup_en-us.cab'
    )

    $MountPath = Join-Path $FullWorkingDirPath 'mount'

    # This will take a couple minutes
    $CurrentPackage = 0
    foreach ($Package in $PackagesToInstall) {
        $FullPackagePath = Join-Path $CabPath $Package

        Write-Progress -Activity 'Adding PowerShell packages' -Id 1 -PercentComplete (($CurrentPackage / $PackagesToInstall.Count) * 100) -Status "($($CurrentPackage+1)/$($PackagesToInstall.Count)) Current package: $Package"
        $CurrentPackage++

        if ($PSCmdlet.ShouldProcess("$MountPath", "Add Windows Package: $Package")) {
            $null = Add-WindowsPackage -Path $MountPath -PackagePath $FullPackagePath @CommonArg
        }
    }
}

function Add-WinPEPowerShellModule {
<#
.SYNOPSIS

Adds a PowerShell module to a mounted WinPE image.

Author: Matthew Graeber (@mattifestation)
License: BSD 3-Clause

.PARAMETER WorkingDirectory

Specifies the path to a mounted WinPE working directory. It must be mounted in order to add PowerShell modules.

.PARAMETER ModulePath

Specifies one or more PowerShell module directories to be added to the mounted WinPE image.

.PARAMETER Force

Indicates that files that already exist in the mounted WinPE image can be overwritten.

.EXAMPLE

$WorkingDir = New-WinPEWorkingDirectory -Architecture amd64 -Mount
$WorkingDir | Add-WinPEPowerShellModule -ModulePath .\PowerForensics

.EXAMPLE

$WorkingDir = New-WinPEWorkingDirectory -Architecture x86
$BootWimPath = Join-Path $WorkingDir 'media\sources\boot.wim'
$MountPath = Join-Path $WorkingDir 'mount'
$MountedImage = Mount-WindowsImage -ImagePath $BootWimPath -Index 1 -Path $MountPath
$MountedImage | Add-WinPEPowerShellModule -ModulePath .\PowerForensics, .\PowerShellArsenal -Force
$MountedImage | Dismount-WindowsImage -Save

.INPUTS

Add-WinPEPowerShellModule accepts the output of New-WinPEWorkingDirectory, Get-ChildItem, and Get-WindowsImage.

.OUTPUTS

System.IO.DirectoryInfo

Outputs the newly created module directories in the mounted WinPE image.
#>

    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $True, ValueFromPipelineByPropertyName = $True, Mandatory = $True)]
        [String]
        [Alias('FullName')] # Alias to capture pipeline output of Get-ChildItem
        [Alias('Path')] # Alias to capture pieline output of a mounted Windows image
        [ValidateNotNullOrEmpty()]
        $WorkingDirectory,

        [Parameter(Mandatory = $True)]
        [String[]]
        [ValidateNotNullOrEmpty()]
        $ModulePath,

        [Switch]
        $Force
    )

    $CommonArg = @{}
    if ($PSBoundParameters['Verbose']) { $CommonArg['Verbose'] = $True }
    if ($PSBoundParameters['Force']) { $CommonArg['Force'] = $True }

    $FullWorkingDirPath = Resolve-Path $WorkingDirectory

    if ((Split-Path $FullWorkingDirPath -Leaf) -eq 'mount') {
        $FullWorkingDirPath = Split-Path $FullWorkingDirPath -Parent
    }

    $Result = Test-WinPEWorkingDirectory -WorkingDirectory $FullWorkingDirPath

    if (-not $Result.Valid) {
        throw "An invalid WinPE working directory was provided: $FullWorkingDirPath"
    }

    if (-not $Result.Mounted) {
        $BootWimPath = Join-Path $FullWorkingDirPath 'media\sources\boot.wim'
        $MountPath = Join-Path $FullWorkingDirPath 'mount'

        $MountCommand = "Mount-WindowsImage -ImagePath $BootWimPath -Index 1 -Path $MountPath"

        throw "The working directory provided does not contain a mounted image: $FullWorkingDirPath. You can mount the working image within the working directory with the following command: $MountCommand"
    }

    foreach ($Module in $ModulePath) {
        $SourceModulePath = Resolve-Path $Module

        if ([IO.Directory]::Exists($SourceModulePath)) {
            $ModuleInfo = Get-Module -ListAvailable $SourceModulePath

            if ($ModuleInfo) {
                $MountPath = Join-Path $FullWorkingDirPath 'mount'
                $ModuleName = Split-Path $SourceModulePath -Leaf

                $DestinationModulePath = Join-Path $MountPath 'Windows\System32\WindowsPowerShell\v1.0\Modules'
                Copy-Item -Path $SourceModulePath -Destination $DestinationModulePath -Recurse @CommonArg

                [IO.DirectoryInfo] (Join-Path $DestinationModulePath $ModuleName)
            } else {
                Write-Error "The module path specified is not a valid PowerShell module: $SourceModulePath"
            }
        } else {
            Write-Error "The module path specified is not a directory: $SourceModulePath. Add-WinPEPowerShellModule only accepts PowerShell modules contained within directories."
        }
    }
}

function Expand-WinPEImage {
<#
.SYNOPSIS

Applies a WinPE image to the specified type of media.

Currently, only removable USB media is supported. ISO and external fixed disk media will be supported is requested.

Author: Matthew Graeber (@mattifestation)
License: BSD 3-Clause

.PARAMETER WorkingDirectory

Specifies the path to a mounted WinPE working directory. It must be mounted in order to add PowerShell modules.

.PARAMETER USBDriveLetter

Specifies the removable media drive letter where the WinPE will be applied.

.PARAMETER Force

Indicates that files that already exist in the mounted WinPE image can be overwritten.

.EXAMPLE

$WorkingDir = New-WinPEWorkingDirectory -Architecture amd64 -Mount
$WorkingDir | Add-WinPEPowerShell
$WorkingDir | Add-WinPEPowerShellModule -ModulePath .\PowerForensics
$WorkingDir | Dismount-WindowsImage -Save
$WorkingDir | Expand-WinPEImage -USBDriveLetter D: -Force

.INPUTS

Expand-WinPEImage accepts the output of New-WinPEWorkingDirectory, Get-ChildItem, and Get-WindowsImage.

.OUTPUTS

Microsoft.Management.Infrastructure.CimInstance

If -USBDriveLetter is specified, New-PowerForensicsBootableImage outputs the newly created bootable volume as a ROOT/Microsoft/Windows/Storage/MSFT_Volume WMI object instance.
#>

    [CmdletBinding(SupportsShouldProcess = $True, DefaultParameterSetName = 'USB')]
    param (
        [Parameter(ValueFromPipeline = $True, ValueFromPipelineByPropertyName = $True, Mandatory = $True)]
        [String]
        [Alias('FullName')] # Alias to capture pipeline output of Get-ChildItem
        [Alias('Path')] # Alias to capture pieline output of a mounted Windows image
        [ValidateNotNullOrEmpty()]
        $WorkingDirectory,

        [Parameter(Mandatory = $True, ParameterSetName = 'USB')]
        [String]
        [ValidatePattern('^[A-Za-z]:$')]
        $USBDriveLetter,

        [Parameter(ParameterSetName = 'USB')]
        [Switch]
        $Force
    )

    # Validate that you are running in the Deployment and Imaging Tools Environment
    if (-not $Env:WinPERoot) {
        throw "$($MyInvocation.InvocationName) must execute from within the Deployment and Imaging Tools Environment."
    }

    $CommonArg = @{}
    if ($PSBoundParameters['Verbose']) { $CommonArg['Verbose'] = $True }
    $ConfirmArg = @{}
    if ($PSBoundParameters['Force']) { $ConfirmArg['Confirm'] = $False }
    $Completed = @{}
    if ($PSBoundParameters['WhatIf']) { $Completed['Completed'] = $True }

    $FullWorkingDirPath = Resolve-Path $WorkingDirectory

    $WriteToUsb = $False
    if ($PSCmdlet.ParameterSetName -eq 'USB') { $WriteToUsb = $True }

    if ($WriteToUsb) {
        # Validate that you are working with a removable volume
        $Removable = 2
        $VolumeInfo = Get-CimInstance -ClassName Win32_Volume -Filter "DriveLetter = '$USBDriveLetter' and DriveType = $Removable"
        if (-not $VolumeInfo) {
            throw "The drive letter provided either does not exist or it is not a removable drive: $USBDriveLetter"
        }

        $DriveLetter = $USBDriveLetter.Split(':')[0]
    }

    if ((Split-Path $FullWorkingDirPath -Leaf) -eq 'mount') {
        $FullWorkingDirPath = Split-Path $FullWorkingDirPath -Parent
    }

    $Result = Test-WinPEWorkingDirectory -WorkingDirectory $FullWorkingDirPath

    if (-not $Result.Valid) {
        throw "An invalid WinPE working directory was provided: $FullWorkingDirPath"
    }

    if ($Result.Mounted) {
        $MountPath = Join-Path $FullWorkingDirPath 'mount'

        $DismountCommand = "Dismount-WindowsImage -Path $MountPath -Save"

        throw "The working directory provided contains a mounted image: $FullWorkingDirPath. You can dismount the image within the working directory with the following command: $DismountCommand"
    }

    if ($WriteToUsb) {
        $TotalSteps = 4
        $ActivityMessage = "Writing the WinPE image to $USBDriveLetter"

        # Burn the image to a USB stick
        $Step = 0
        Write-Progress -Activity $ActivityMessage -Id 1 -PercentComplete (($Step / $TotalSteps) * 100) -Status "($($Step+1)/$($TotalSteps)) Removing all partitions and clearing the following drive: $USBDriveLetter" @Completed

        <# 
          Select the disk associated with the removable media,
          remove all partitions, and un-initialize the disk 

          diskpart:
            select volume <DRIVE_LETTER>
            clean
        #>
        $Volume = Get-Volume -DriveLetter $DriveLetter -ErrorAction Stop
        $Partition = $Volume | Get-Partition -ErrorAction Stop
        $Disk = $Partition | Get-Disk -ErrorAction Stop

        if ($PSCmdlet.ShouldProcess("$USBDriveLetter", 'Remove Partition')) {
            $Partition | Remove-Partition -ErrorAction Stop @CommonArg @ConfirmArg
        }

        if ($PSCmdlet.ShouldProcess("Disk $($Disk.Number) '$($Disk.FriendlyName)'", 'Erase Data and Remove Volumes')) {
            $null = Clear-Disk -InputObject $Disk -RemoveOEM -RemoveData -ErrorAction Stop @CommonArg @ConfirmArg
        }

        $Step++
        Write-Progress -Activity $ActivityMessage -Id 1 -PercentComplete (($Step / $TotalSteps) * 100) -Status "($($Step+1)/$($TotalSteps)) Creating a clean bootable FAT32 partition." @Completed

        <#
          diskpart:
            format fs=fat32 label="WinPE" quick
            active
        #>
        if ($PSCmdlet.ShouldProcess("Disk $($Disk.Number) '$($Disk.FriendlyName)'", 'Create a new active partition on disk')) {
            $NewPartition = $Disk | New-Partition -AssignDriveLetter -UseMaximumSize -IsActive -MbrType FAT32
        }

        if ($PSCmdlet.ShouldProcess($USBDriveLetter, "Format FAT32 volume named 'WinPE'")) {
            $null = Format-Volume -Partition $NewPartition -FileSystem FAT32 -NewFileSystemLabel 'WinPE' -ErrorAction Stop @CommonArg
        }

        $Step++
        Write-Progress -Activity $ActivityMessage -Id 1 -PercentComplete (($Step / $TotalSteps) * 100) -Status "($($Step+1)/$($TotalSteps)) Copying boot files to $USBDriveLetter" @Completed

        if ($PSCmdlet.ShouldProcess("Item: $FullWorkingDirPath\media\*", 'Copy Directory')) {
            Copy-Item -Path "$FullWorkingDirPath\media\*" -Destination "$($NewPartition.DriveLetter):\" -Recurse -Force
        }

        $Step++
        Write-Progress -Activity $ActivityMessage -Id 1 -PercentComplete (($Step / $TotalSteps) * 100) -Status "($($Step+1)/$($TotalSteps)) Writing MBR boot code to $USBDriveLetter" @Completed

        $NewDriveLetter = "$($NewPartition.DriveLetter):"

        if ($PSCmdlet.ShouldProcess($USBDriveLetter, 'Write MBR boot code')) {
            if ($Force -or $psCmdlet.ShouldContinue("$($NewPartition.DriveLetter):", "Writing MBR boot code")) {
                & bootsect /nt60 $NewDriveLetter /force /mbr > $null
            }
        }

        if ($LASTEXITCODE -ne 0) {
            throw "Unable to set the boot code on $($NewPartition.DriveLetter)"
        }
    }

    switch ($PSCmdlet.ParameterSetName) {
        'USB' {
            if (-not $PSBoundParameters['WhatIf']) {
                # Return volume information for the new bootable WinPE removable media.
                Get-Volume -DriveLetter $NewPartition.DriveLetter
            }
        }
    }
}