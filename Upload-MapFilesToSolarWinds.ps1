<#
    .SYNOPSIS
        Uploads OrionMaps (also works with images if supplied!) to the SolarWinds Orion Database (into Orion.MapStudioFiles table)

    .DESCRIPTION

        PREREQUISITES
            SolarWinds Instance
            SolarWinds SDK installed
            SWIS Credentials
            OrionMap files / JPG Images to upload
            Powershell Terminal pointing to the folder containing this script
            Images MUST have the same name as the OrionMap file they link to
            Map files MUST be of type OrionMap, and thier associated images MUST be jpg (.jpg for background .thumb.jpg for thumbnail)
            There MUST NOT be duplicate maps (2 or more maps with the same FileName) already in the SolarWinds database

        Checks for exisitng maps on SolarWinds, gets thier information
        Reads everything from MapFilesToUpload folder
        If images exist, convert the images to byte arrays and upload them first, this is because we need thier FileId to link back into the OrionMap file (which is assigned when imported into Orion DB)
        Update the information we stored about maps from SolarWinds
        Modify required OrionMap files with the FileId of the BackgroundImage and ThumbnailImage to link them
        Convert the map files to byte arrays and upload them as they now have a correct link to the images (if they use an image)
        Conversion to bytes is because maps are stored in the SolarWinds database in the FileData column of Orion.MapStudioFiles, which is of type varbinary
        
        The script checks if each map / image already exists in the database
        If the map / image exists, delete it, and create a new map / image with the same FileId (so all UI elements will point to the new map / image automatically)
        If the map / image does not exist, just create the new map / image

        Resulting in updated maps! Without the need to manually add the updated map in the Web UI

        Created to avoid the use of Network Atlas or ImportMapBatch.exe, and automate the upload process
        I needed a way of uploading from powershell quickly, rather than using the slow GUI applciations, so modify this script as needed to suit your needs!

    .EXAMPLE
        ./Upload-MapFilesToSolarWinds.ps1 

    .OUTPUTS
        Map / image files uploaded to SolarWinds

#>

function ConvertAndUploadToSolarWinds
{
    param (
        $FileNames
    )

    <#---------------------------------------------------Convert each file to a byte array, then upload to SolarWinds with the correct file type---------------------------------------------------#>

    Write-Host "Converting Files To Bytes And Uploading To SolarWinds"
    foreach($FileName in $FileNames)
    {
        $MapFilePath = $(Get-Location).Path + $MapFolderPath + $FileName
        $bytes = [io.file]::ReadAllBytes($MapFilePath)
        
        $FileType = $null
        if($FileName -like "*.OrionMap")
        {
            $FileType = $OrionMapFileType
        }
        elseif($FileName -like "*.thumb.jpg") {
            $FileType = $ThumbJpgFileType
        }
        elseif($FileName -like "*.jpg") {
            $FileType = $JpgFileType
        }

        if($FileName -in $ExistingMapInformation.FileName)
        {
            Write-Host "Uploading (Replacing) $FileName..."
            $ExistingMap = $ExistingMapInformation | Where-Object { $_.FileName -eq $FileName }
            Remove-SwisObject -SwisConnection $SwisConnection -Uri $ExistingMap.Uri
            New-SwisObject -SwisConnection $SwisConnection -EntityType 'Orion.MapStudioFiles' -Properties @{FileId=$ExistingMap.FileId; FileName=$FileName; TimeStamp= $(Get-Date).DateTime; FileData=$bytes; Owner=$SwisCredential.UserName; IsDeleted=$false; FileType=$FileType;} > $null
        }
        else
        {
            Write-Host "Uploading $FileName..."
            New-SwisObject -SwisConnection $SwisConnection -EntityType 'Orion.MapStudioFiles' -Properties @{FileName=$FileName; TimeStamp= $(Get-Date).DateTime; FileData=$bytes; Owner=$SwisCredential.UserName; IsDeleted=$false; FileType=$FileType;} > $null
        }      
    }
}

function ModifyOrionMapFilesToLinkImages
{
    param ( 
        $ExistingMapInformation
     )

    <#---------------------------------------------------Take existing image entries from database, modify the relevant OrionMap file to include the image Id so they link together on the Web UI---------------------------------------------------#>

    Write-Host "Modifying Orion Maps To Link Images With Maps"
    $ExistingJpgMapInformation = $ExistingMapInformation | Where-Object { $_.FileName -like "*.jpg" }
    $ExistingJpgMapInformation | ForEach-Object { $_ | Add-Member -MemberType NoteProperty -Name "OrionMapFileName" -Value ($_.FileName.Replace(".jpg", "").Replace(".thumb", "") + ".OrionMap")}

    foreach($JpgInformation in $ExistingJpgMapInformation)
    {
        Write-Host "Modifying: $($JpgInformation.OrionMapFileName) to link: $($JpgInformation.FileName)"
        $FileName = $JpgInformation.OrionMapFileName
        $FileData = (Get-Content "$MapFolderPath\$FileName") -join "`r`n"

        if($JpgInformation.FileType -eq $JpgFileType)
        {
            $FileData = $FileData -replace '"BackgroundImageName=.*?"', ('"BackgroundImageName={0}.jpg"' -f $JpgInformation.FileId)
        }
        elseif($JpgInformation.FileType -eq $ThumbJpgFileType)
        {
            $FileData = $FileData -replace '"ThumbnailImageName=.*?"', ('"ThumbnailImageName={0}.jpg"' -f $JpgInformation.FileId)
        }
        
        Set-Content -Path "$MapFolderPath\$FileName" -Value $FileData
    }
}

<#---------------------------------------------------Set up variables---------------------------------------------------#>

$ErrorActionPreference = 'Stop'

$OrionMapFileType = 0
$JpgFileType = 2
$ThumbJpgFileType = 1024

$MapFolderPath = ".\MapFilesToUpload\"

$SolarWindsHostName = "SOLARWINDS_HOSTNAME_HERE"

$SwqlQuery = @"
SELECT FileId, FileName, FileType, Uri
FROM Orion.MapStudioFiles
WHERE FileType IN ($OrionMapFileType,$JpgFileType,$ThumbJpgFileType) AND IsDeleted = False AND FileName IN ({0})
ORDER BY FileName
"@

$SwisCredential = Get-Credential -Message "Please Enter Your SolarWinds (SWIS) Credentials"

$SwisConnection  = Connect-Swis -Hostname $SolarWindsHostName -Credential $SwisCredential

<#---------------------------------------------------Get map files to upload from MapFileToUpload folder---------------------------------------------------#>

$OrionMapFilesInDirectory = Get-ChildItem -Path $MapFolderPath
$FileNamesForSwql = ($OrionMapFilesInDirectory.Name | ForEach-Object { "'" + $_ + "'" }) -join ","

<#---------------------------------------------------Query existing map information from SolarWinds---------------------------------------------------#>

Write-Host "Getting Existing Map Information From SolarWinds"
$SwqlQuery = $SwqlQuery -f $FileNamesForSwql
$ExistingMapInformation = Get-SwisData -SwisConnection $SwisConnection -Query $SwqlQuery

<#---------------------------------------------------Read in OrionMap and Image files, convert them to a byte array, upload to SolarWinds---------------------------------------------------#>

ConvertAndUploadToSolarWinds ($OrionMapFilesInDirectory.Name | Where-Object { $_ -like "*.jpg"}) # upload images first, as we need to reference thier Ids in the OrionMap file

Write-Host "Updating Information From SolarWinds"
$ExistingMapInformation = Get-SwisData -SwisConnection $SwisConnection -Query $SwqlQuery

ModifyOrionMapFilesToLinkImages $ExistingMapInformation

ConvertAndUploadToSolarWinds ($OrionMapFilesInDirectory.Name | Where-Object { $_ -like "*.OrionMap"})

Write-Host "Upload Complete!"