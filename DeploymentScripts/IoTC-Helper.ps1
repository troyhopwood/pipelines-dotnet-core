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