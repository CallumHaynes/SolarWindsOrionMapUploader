## SolarWinds Map Uploader
## Pre-Requisites
- SolarWinds Instance
- SolarWinds SDK installed
- SWIS Credentials
- OrionMap files / JPG Images to upload
- Powershell Terminal pointing to the folder containing this script
- Images MUST have the same name as the OrionMap file they link to
- Map files MUST be of type OrionMap, and thier associated images MUST be jpg (.jpg for background .thumb.jpg for thumbnail)
- There MUST NOT be duplicate maps (2 or more maps with the same FileName) already in the SolarWinds database

## Usage
- Place your OrionMap and associated jpg files in the `./MapFilesToUpload/` folder
- Navigate your Powershell Terminal to the folder containing `Upload-MapFilesToSolarWinds.ps1`
- Edit the `$SolarWindsHostName` variable in `Upload-MapFilesToSolarWinds.ps1` with the URL of your SolarWinds Instance
- Run `./Upload-MapFilesToSolarWinds.ps1`
- Select a map on the WebUI to view it
- Modify the script at will! Incorporate it into other scripts to automate map creation!


## Why Upload-MapFilesToSolarWinds was created
- I needed a way of uploading map files quickly (Uploading every hour to reflect changes to servers)
- The only way to import map files was using Network Atlas or ImportMapBatch, which were both very slow GUI applications and a manual process, there was no official way to script the creation and upload process
- I have another script generating the specific OrionMap files automatically based on which servers are being used. This feeds into (a modified version of) this script to create and upload the map files every hour
- This also combats the map update issue of ImportMapBatch, if you overwrite a map with ImportMapBatch, the UI elements dont point to the new map, they still point to the old deleted map, which breaks the WebUI view

## How Upload-MapFilesToSolarWinds works
- The upload process works by converting the Map or Image to a byte array, then creating a new entry for it in the Orion.MapStudioFiles table
- If a map / image already exists with that name, it is removed, but its ID is used for the new entry, so the Web UI elements all point to the new Map, keeping the database clean and WebUI elements automatically up-to-date
- The images are uploaded first. This is because the OrionMap files need a reference to the images FileId (which is obtained from the SolarWinds database), this is to link the background / thumbnail images to the maps (if the map uses images)