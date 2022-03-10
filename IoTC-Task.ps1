[CmdletBinding()]
Param(
  [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
  [String] $ApiToken,
  [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
  [String] $ConfigPath,
  [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
  [String] $AppName
)

$Header = @{"authorization" = $ApiToken}
$BaseUrl = "https://" + $AppName + ".azureiotcentral.com/api/"

$Location = Get-Location
$ConfigPath = "$Location\$ConfigPath"
Write-Host "Location: $ConfigPath"

#Set Global Variables that are used in all functions
Function Set-Globals{
Param(
[Parameter(Mandatory=$true,Position=0)] [String]$BaseUrl,
[Parameter(Mandatory=$true,Position=1)] [String]$Token,
[Parameter(Mandatory=$true,Position=2)] [String]$ConfigPath
)

$Script:BaseUrl = $BaseUrl
$Script:Header = $Header = @{"authorization" = $Token}
$Script:ConfigPath = $ConfigPath
}

Function Save-DeviceModels{
$JObject = Get-DeviceModels | ConvertFrom-Json -ErrorAction Stop
    foreach ($element in $JObject."value"){
        foreach ($property in $element.PSObject.Properties){
            if($property.Name -eq "@id"){
                $ModelObject = Get-CleanDeviceModel -DeviceTemplateId $property.value | ConvertFrom-Json
                foreach ($element in $ModelObject.PSObject.Properties) {
                    if($element.Name -eq "displayName"){
                        $DisplayName = $element.Value
                        $ModelObject | ConvertTo-Json -Depth 10  | Set-Content "$ConfigPath/IoTC Configuration/Device Models/$DisplayName.json" -ErrorAction Stop
                    }
                }
            }
        }
    }
}


Function Add-DeviceModel{
Param(
[Parameter(Mandatory=$true,Position=0)] [String]$DeviceTemplateId,
[Parameter(Mandatory=$true,Position=1)] [String]$Model
)
$Uri = $BaseUrl + "deviceTemplates/" + $DeviceTemplateId + "?api-version=1.0"
$Parameters = @{
Method      = "PUT"
Uri         = $Uri
Headers     = $Header
ContentType = "application/json"
Body = $Model
}

try{
$Result = Invoke-WebRequest @parameters
}
catch{
if($_.Exception.Response.StatusCode -eq "422"){
    $Result = "422"
}
else{
    throw
}
}
$Result
}

Function Update-DeviceModel{
Param(
[Parameter(Mandatory=$true,Position=0)] [String]$DeviceTemplateId,
[Parameter(Mandatory=$true,Position=1)] [String]$Model
)
$Uri = $BaseUrl + "deviceTemplates/" + $DeviceTemplateId + "?api-version=1.0"
# $Model = Add-ETagToModel $Etag $Model      
$Parameters = @{
Method      = "PUT"
Uri         = $Uri
Headers     = $Header
ContentType = "application/json"
Body = $Model
}

$Result = Invoke-WebRequest @parameters
$Result.Content
}

#Get list of all device models in an IoT Central application
Function Get-DeviceModels{
$Uri = $BaseUrl + "deviceTemplates?api-version=1.0"
$Body = @{}
$Parameters = @{
Method      = "GET"
Uri         = $Uri
Headers     = $Header
ContentType = "application/json"
Body = $Body
}
$Result = Invoke-WebRequest @parameters

$Result.Content
}

Function Get-DeviceModelETag{
Param(
[Parameter(Mandatory=$true,Position=0)] [String]$DeviceTemplateId
)

$ModelObject = Get-DeviceModel -DeviceTemplateId $DeviceTemplateId | ConvertFrom-Json
foreach ($element in $ModelObject.PSObject.Properties) {
if($element.Name -eq "etag"){
    $ETag = $element.Value
}
}
$ETag
}

#Gets the device model without an etag
Function Get-CleanDeviceModel{
Param(
[Parameter(Mandatory=$true,Position=0)] [String]$DeviceTemplateId
)
try{
    $Model = Get-DeviceModel -DeviceTemplateId $DeviceTemplateId
    if($Model.Length -gt 0){
        # $ModelObject = Get-DeviceModel -DeviceTemplateId $DeviceTemplateId | ConvertFrom-Json
        $ModelObject = $Model | ConvertFrom-Json
        foreach ($element in $ModelObject.PSObject.Properties) {
            if($element.Name -eq "etag"){
                $ModelObject.PSObject.Properties.Remove($element.Name)
            }
        }
        $Result = $ModelObject | ConvertTo-Json -Depth 100
    }
    else{
        $Result="404" #There are no device models
    }
}
catch{
    if($_.Exception.Response.StatusCode -eq "404"){
        $Result = "404"
        
    }
    else{
        throw
    }
}
$Result
}
Function Get-DeviceModel{
Param(
[Parameter(Mandatory=$true,Position=0)] [String]$DeviceTemplateId
)

$Uri = $BaseUrl + "deviceTemplates/" + $DeviceTemplateId + "?api-version=1.0"

$Body = @{}
$Parameters = @{
Method      = "GET"
Uri         = $Uri
Headers     = $Header
ContentType = "application/json"
Body = $Body
}

try{
$Result = Invoke-WebRequest @Parameters
}
catch{
if($_.Exception.Response.StatusCode -eq "404"){
    $Result = "404"
    #TODO: This doesn't actually return 404 because it returns result.content instead.
}
else{
    throw
}
}
$Result.Content
}

Function Get-ETagFromModel{
Param(
[Parameter(Mandatory=$true,Position=0)] [String]$DeviceTemplateId
)
$Model = Get-DeviceModel -DeviceTemplateId $DeviceTemplateId
$ETag = ($Model | ConvertFrom-json).Etag
$ETag = '"\"' + $ETag.Trim('"') + '\""'
$ETag
}

#Get list of data exports
Function Get-DataExports{
$Uri = $BaseUrl + "dataExport/exports?api-version=1.1-preview"
$Body = @{}
$Parameters = @{
Method      = "GET"
Uri         = $Uri
Headers     = $Header
ContentType = "application/json"
Body = $Body
}

$Result = Invoke-WebRequest @parameters
$Result.Content
}


#Get data export details
Function Get-DataExport{
Param(
[Parameter(Mandatory=$true,Position=0)] [String]$DataExportId
)
$Uri = $BaseUrl + "dataExport/exports/" + $DataExportId + "?api-version=1.1-preview"
$Body = @{}
$Parameters = @{
Method      = "GET"
Uri         = $Uri
Headers     = $Header
ContentType = "application/json"
Body = $Body
}

$Result = Invoke-WebRequest @parameters
$Result.Content
}

#Create a new data export
Function Add-DataExport{
Param(
[Parameter(Mandatory=$true,Position=0)] [String]$Config,
[Parameter(Mandatory=$false,Position=1)] [String]$DataExportId
)

if($DataExportId.Length -eq 0){
$DataExportId = New-Guid
}

$Uri = $BaseUrl + "dataExport/exports/" + $DataExportId + "?api-version=1.1-preview"
$Parameters = @{
Method      = "PUT"
Uri         = $Uri
Headers     = $Header
ContentType = "application/json"
Body = $Config
}
$Result = Invoke-WebRequest @parameters
$Result.Content
}

#Update Data Export
Function Update{
Param(
[Parameter(Mandatory=$true,Position=0)] [String]$DataExportId,
[Parameter(Mandatory=$true,Position=1)] [String]$Config
)

#$DataExportId = 192dbb3a-8e40-4705-9654-d9fa51ace2fe
# $newExportJson = '{"displayName":"Telemetry","enabled":true,"source":"telemetry","filter":"SELECT * FROM devices WHERE $id != \"Foo\"","enrichments":{"Foo":{"target":"dtmi:nerf:NerfGun_79h;2","path":"BuzzerEnabled"},"Region":{"value":"US"}},"destinations":[{"id":"8e46792d-c026-44f8-9001-668ad20dea39"}],"status":"healthy","lastExportTime":"2022-02-22T18:58:25.19Z"}'
$Uri = $BaseUrl + "dataExport/exports/" + $DataExportId + "?api-version=1.1-preview"
$Parameters = @{
Method      = "PUT"
Uri         = $Uri
Headers     = $Header
ContentType = "application/json"
Body = $Config
}


$Result = Invoke-WebRequest @parameters
$Result.Content
}

#Get list of device groups
Function Get-DeviceGroups{

$Uri = $BaseUrl + "deviceGroups?api-version=1.1-preview"
$Body = @{}
$Parameters = @{
Method      = "GET"
Uri         = $Uri
Headers     = $Header
ContentType = "application/json"
Body = $Body
}

$Result = Invoke-WebRequest @parameters
$Result.Content
}

#Get File Upload Configuration
Function Get-FileUploads{

$Uri = $BaseUrl + "fileUploads?api-version=1.1-preview"
$Body = @{}
$Parameters = @{
Method      = "GET"
Uri         = $Uri
Headers     = $Header
ContentType = "application/json"
Body = $Body
}

try{
$Result = Invoke-WebRequest @parameters
}
catch{
if($_.Exception.Response.StatusCode -eq "404"){
    $Result = "404"
}
}
$Result
}

#Create a new file upload configuration
Function Add-FileUploads{
Param(
[Parameter(Mandatory=$true,Position=0)] [String]$Config
)
$Uri = $BaseUrl + "fileUploads?api-version=1.1-preview"
$Parameters = @{
Method      = "PUT"
Uri         = $Uri
Headers     = $Header
ContentType = "application/json"
Body = $Config
}

$Result = Invoke-WebRequest @parameters
$Result.Content
}

#Get Jobs Configuration
Function Get-Jobs{
$Uri = $BaseUrl + "jobs?api-version=1.1-preview"
$Body = @{}
$Parameters = @{
Method      = "GET"
Uri         = $Uri
Headers     = $Header
ContentType = "application/json"
Body = $Body
}

$Result = Invoke-WebRequest @parameters
$Result.Content
}

#Create a new file upload configuration
Function Add-Job{
Param(
[Parameter(Mandatory=$true,Position=0)] [String]$Config,
[Parameter(Mandatory=$false,Position=1)] [String]$JobId
)
if($JobId.Length -eq 0){
$JobId = New-Guid
}
$Uri = $BaseUrl + "jobs/" + $JobId + "?api-version=1.1-preview"
$Parameters = @{
Method      = "PUT"
Uri         = $Uri
Headers     = $Header
ContentType = "application/json"
Body = $Config
}

$Result = Invoke-WebRequest @parameters
$Result.Content
}

#Get List of Organizations
Function Get-Orgs{
$Uri = $BaseUrl + "organizations?api-version=1.1-preview"
$Body = @{}
$Parameters = @{
Method      = "GET"
Uri         = $Uri
Headers     = $Header
ContentType = "application/json"
Body = $Body
}

$Result = Invoke-WebRequest @parameters
$Result.Content
}

#Create a new Org
Function Add-Org{
Param(
[Parameter(Mandatory=$true,Position=0)] [String]$Config,
[Parameter(Mandatory=$false,Position=1)] [String]$OrgId
)
if($OrgId.Length -eq 0){
$OrgId = New-Guid
}
$Uri = $BaseUrl + "organizations/" + $OrgId + "?api-version=1.1-preview"
$Parameters = @{
Method      = "PUT"
Uri         = $Uri
Headers     = $Header
ContentType = "application/json"
Body = $Config
}

$Result = Invoke-WebRequest @parameters
$Result.Content
}

Function Update-Org{
Param(
[Parameter(Mandatory=$true,Position=0)] [String]$Config,
[Parameter(Mandatory=$true,Position=1)] [String]$OrgId
)
$Uri = $BaseUrl + "organizations/" + $OrgId + "?api-version=1.1-preview"
$Parameters = @{
    Method      = "PUT"
    Uri         = $Uri
    Headers     = $Header
    ContentType = "application/json"
    Body = $Config
}

$Result = Invoke-WebRequest @parameters
$Result.Content
}

#Get List of Roles
Function Get-Roles{
$Uri = $BaseUrl + "roles?api-version=1.1-preview"
$Body = @{}
$Parameters = @{
Method      = "GET"
Uri         = $Uri
Headers     = $Header
ContentType = "application/json"
Body = $Body
}

$Result = Invoke-WebRequest @parameters
$Result.Content
}






<#
.SYNOPSIS
This function will apply IoT Central settings based on a config file

.DESCRIPTION
This function will apply IoT Central settings based on a config file. This can be used to copy an IoT Central app configuration from
a dev environment to QA to pre-production and finally to production. 

This currently will not do the following:
1. Document or update Dashboards, Views, Custom Settings on Device Templates, Pricing Plan, UX Customizations (Appearance & App Links), Application Image, Rules, Scheduled Jobs, Saved Jobs, and Enrollment Groups"
2. Remove settings from the target IoT Central app that are not present in the config file
#>
Function Update-App{  
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
Write-Host "     File uploads not in config file."
Write-Host " Skipping"
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

Write-Host "     Adding dashboards Not-Yet Supported" 

Write-Host "     Adding custom device template settings Not-Yet Supported" 

Write-Host "     Adding views Not-Yet Supported" 

Write-Host "     Adding UX customizations Not-Yet Supported" 

Write-Host "     Adding rules Not-Yet Supported" 

Write-Host "     Adding saved and scheduled jobs Not-Yet Supported" 

Write-Host "     Adding enrollment groups Not-Yet Supported" 
}



Update-App
