[CmdletBinding()]
Param(
  [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
  [String] $ApiToken,
  [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
  [String] $ConfigPath,
  [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
  [String] $AppName
)

#TODO:
# Try out dot sourcing and move helpers to separate PS1 file
# Remove main code from function
# Ensure I properly pull values out of JSON object
# Delete IoTC-Config directory in the root in GitHub
# Figure out error handling
# Test failure states ensuring the pipeline stops
# Look for other TODOs in files
# Move this script out of the root

$Header = @{"authorization" = $ApiToken}
$BaseUrl = "https://" + $AppName + ".azureiotcentral.com/api/"

Write-Host "Header: " $Header
Write-Host "BaseUrl: " $BaseUrl

$Location = Get-Location
$ConfigPath = "$Location/$ConfigPath"
Write-Host "Location: $ConfigPath"

. "$location\DeploymentScripts\IoTC-Helper.ps1"




Write-Host "`n`nChecking the specified directory"
#Ensure the expected directories exist
if((test-path "$ConfigPath/IoTC Configuration") -eq $False){
Write-Host "`nDirectory not found: $ConfigPath/IoTC Configuration"
Exit
}

if((test-path "$ConfigPath/IoTC Configuration/Device Models") -eq $False){
Write-Host "`nDirectory not found: $ConfigPath/IoTC Configuration/Device Models"
Exit
}

#Load the desired config
$ConfigObj = Get-Content -path "$ConfigPath/IoTC Configuration/IoTC-Config.json" | ConvertFrom-Json -ErrorAction stop

Write-Host "`nChecking device models and applying updates"
#Compare Device Models
$Files = Get-ChildItem "$ConfigPath/IoTC Configuration/Device Models" -Filter *.json 
$Files | Foreach-Object {
    $Model = Get-Content -Raw $_.FullName
    $JObject = $model | ConvertFrom-Json
    $JObject | ForEach-Object {
        $id = $_."@id"
        $Name = $_.displayName
        
        #Get the model if it exists
        $CloudModel = Get-CleanDeviceModel -DeviceTemplateId $id -ErrorAction stop

        Write-Host $CloudModel
        
        if($CloudModel -eq "404"){
            #It doesn't exist so we need to add it
            Write-Host "     Uploading model $Name to IoT Central"
            $Model = Add-DeviceModel -DeviceTemplateId $id -Model $Model
        }
        else{
            $SourceObject = $Model | ConvertFrom-Json
            $CloudObject = $CloudModel | ConvertFrom-Json
            
            $ContentEqual = ($SourceObject | ConvertTo-Json -Compress -Depth 100) -eq ($CloudObject | ConvertTo-Json -Compress -Depth 100)
            
            if($ContentEqual){
                #They are the same so we don't need to do anything
                Write-Host "     Model $Name already exists and is current "
                
            }
            else{
                #We need to update the model
                Write-Host "     Updating model $Name in IoT Central "
                $ETag = Get-DeviceModelETag -DeviceTemplateId $id
                $SourceObject | add-member -Name "etag" -Value "$ETag" -MemberType NoteProperty
                $NewJson = $SourceObject | ConvertTo-Json -Depth 100 -Compress
                $ETag = Update-DeviceModel -DeviceTemplateId $id -Model $NewJson -ErrorAction stop
            }
        }                                          
    }
}


Write-Host "`nChecking Configs and applying updates......"

#Compare Device Groups to Config
$ConfigGroups = $ConfigObj."device groups"
$CloudGroups = Get-DeviceGroups -ErrorAction stop
$CloudGroups = $CloudGroups | ConvertFrom-Json
if($ConfigGroups.length -eq 0){
Write-Host "     Device groups not in config file."
Write-Host " Skipping"
}
else{
$ContentEqual = ($CloudGroups | ConvertTo-Json -Compress -Depth 100) -eq ($ConfigGroups | ConvertTo-Json -Compress -Depth 100)

if($ContentEqual){
    Write-Host "     Device groups match config "
    
}
else{
    Write-Host  "##vso[task.LogIssue type=warning;] Device groups do not match config file. Device groups will need to be manually updated in the target app."
}
}

#TODO: Need to figure out how 
#Compare Data Exports to Config
$ConfigExportsObj = $ConfigObj."data exports"
if($ConfigExportsObj.length -eq 0){
Write-Host "     Data exports not in config file."
Write-Host " Skipping"
}
else{
$CloudExportsObj = Get-DataExports -ErrorAction stop
$CloudExportsObj = $CloudExportsObj | ConvertFrom-Json

#Remove status from the JSON so we can accurately compare the config to the app
$CloudExportsObj."value" | ForEach-Object {
    $_.PSObject.Properties.Remove("status")
}
$CloudExportsObj = $CloudExportsObj."value"

#Remove status from the Config so we can accurately compare the config to the app
$ConfigExportsObj."value" | ForEach-Object {
    $_.PSObject.Properties.Remove("status")
}
$ConfigExportsObj = $ConfigExportsObj."value"

$ConfigExports = $ConfigExportsObj | ConvertTo-Json -Depth 100 -Compress
$CloudExports = $CloudExportsObj | ConvertTo-Json -Depth 100 -Compress
$ConfigExportsObj = $ConfigExports | ConvertFrom-Json


$ContentEqual = ($CloudExports -eq $ConfigExports)
if($ContentEqual){
    Write-Host "     Data exports match config "
}
    else{
        #Iterate through data exports in config file to find the missing exports
        $ConfigExportsObj | ForEach-Object {
            $id = $_.id
            $name = $_.displayName
            $record = $_ | ConvertTo-Json -Depth 100 -Compress

            if(($CloudExports.Length -eq 0) -or ($CloudExports -inotmatch $id)) #We need to add this data export
            {
                Write-Host "     Adding missing data export $name "
                $Config = $_ | ConvertTo-Json -Depth 100 -Compress
                $Config = Add-DataExport -Config $Config -DataExportId $id
                
            }
            elseif(($CloudExports.Length -gt 0) -and (!$cloudExports.Contains($Record))) #We need to update this data export
            {
                Write-Host "     Updating existing data export $name "
                $Config = Add-DataExport -Config $Record -DataExportId $id
                
            }
            else{
                Write-Host "     Processing data export $name "
                Write-Host "Missed"
            }
        }
    }
}

#Compare Organizations to Config
$CloudOrgsObj = Get-Orgs -ErrorAction stop
$CloudOrgsObj = $CloudOrgsObj | ConvertFrom-Json
$CloudOrgs = $CloudOrgsObj | ConvertTo-Json -Depth 100 -Compress
$ConfigOrgsObj = $ConfigObj."organizations"
$ConfigOrgs = $ConfigOrgsObj | ConvertTo-Json -Depth 100 -Compress
$ContentEqual = ($CloudOrgs -eq $ConfigOrgs)
if($ContentEqual){
Write-Host "     Organizations match config "

}
else{
    #Iterate through orgs in config file to find the missing orgs
    $ConfigOrgsObj."value" | ForEach-Object {
        $id = $_.id
        $name = $_.displayName
        if($CloudOrgs -inotmatch $id) #We need to add this org
        {
            Write-Host "     Adding missing organization $name "
            $Config = $_ | ConvertTo-Json -Depth 100 -Compress
            $Config = Add-Org -Config $Config -OrgId $_.id
            
        }
        elseif($CloudOrgs -inotmatch $_) #We need to update this org
        {
            Write-Host "     Updating existing org $name"
            $Config = $_ | ConvertTo-Json -Depth 100 -Compress
            $Config = Add-Org -Config $Config -OrgId $id
            
        }    
    }
}


#Compare Roles to Config
$CloudRoles = Get-Roles -ErrorAction stop
$CloudRoles = $CloudRoles | ConvertFrom-Json
$RolesConfig = $ConfigObj."roles"

$ContentEqual = ($CloudRoles | ConvertTo-Json -Compress -Depth 100) -eq ($RolesConfig | ConvertTo-Json -Compress -Depth 100)

if($ContentEqual){
Write-Host "     Roles match config "

}
else{
Write-Host  "##vso[task.LogIssue type=warning;] Roles do not match the config file. Roles will need to be manually updated in the target app."
}

#Compare File Uploads to Config
$CloudUploads = Get-FileUploads -ErrorAction stop
$CloudUploadsObj = $CloudUploads | ConvertFrom-Json
$UploadsConfig = $ConfigObj."file uploads"

if($UploadsConfig.length -eq 0){
Write-Host "     File uploads not in config file. Skipping."
}
else{
#Remove state and etag from the JSON so we can accurately compare the config to the app
$CloudUploadsObj | ForEach-Object {
    $_.PSObject.Properties.Remove("state")
    $_.PSObject.Properties.Remove("etag")
}
$ContentEqual = ($CloudUploadsObj | ConvertTo-Json -Compress -Depth 100) -eq ($UploadsConfig | ConvertTo-Json -Compress -Depth 100)

if($ContentEqual){
    Write-Host "     File uploads match config "
    
}
else{
    if($CloudUploads -eq "404"){ #There is no file upload configured currently
        Write-Host "     Adding file uploads config to IoT Central "
        $UploadsConfig = $UploadsConfig | ConvertTo-Json -Compress -Depth 100
        $UploadsConfig = Add-FileUploads -Config  $UploadsConfig
        
    }
    else{ #We need to update the existing config
        Write-Host "     Updating file uploads config in IoT Central "
        $UploadsConfig = $UploadsConfig | ConvertTo-Json -Compress -Depth 100
        $UploadsConfig = Add-FileUploads -Config  $UploadsConfig
    }
}
}

Write-Host "`nNot Yet Supported:"
Write-Host "     Dashboards" 
Write-Host "     Custom device template settings" 
Write-Host "     Views" 
Write-Host "     UX customizations" 
Write-Host "     Rules" 
Write-Host "     Saved and scheduled jobs" 
Write-Host "     Enrollment groups" 
