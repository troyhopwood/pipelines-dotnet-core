clear-host
$RequiredVersion = 7
$MajorVersion = $PSVersionTable.PSVersion.Major
If($MajorVersion  -lt $RequiredVersion){
    Write-Host "IoTC Config requires Powershell Core version $RequiredVersion or greater. You can get the latest release for Windows, Mac, and Linux here: https://github.com/PowerShell/PowerShell/releases/" -ForegroundColor red
    Exit
}
#Requires -Version 7.0

Read-Host -Prompt "Hit <Enter> to Open a Web Browser and Log Into Azure"
Connect-AzAccount
$location = Get-Location
. $location\IoTC-Helper.ps1

#Todo:
# Seperate script for using jobs to migrate devices to a new device template

$greenCheck = @{
    Object = [Char]8730
    ForegroundColor = 'Green'
    NoNewLine = $false
    }

Write-Host "___  ________  _________  ________          ________  ________  ________   ________ ___  ________    " -ForegroundColor yellow
Write-Host "|\  \|\   __  \|\___   ___\\   ____\        |\   ____\|\   __  \|\   ___  \|\  _____\\  \|\   ____\    " -ForegroundColor yellow
Write-Host "\ \  \ \  \|\  \|___ \  \_\ \  \___|        \ \  \___|\ \  \|\  \ \  \\ \  \ \  \__/\ \  \ \  \___|    " -ForegroundColor yellow
Write-Host " \ \  \ \  \\\  \   \ \  \ \ \  \            \ \  \    \ \  \\\  \ \  \\ \  \ \   __\\ \  \ \  \  ___  " -ForegroundColor yellow
Write-Host "  \ \  \ \  \\\  \   \ \  \ \ \  \____        \ \  \____\ \  \\\  \ \  \\ \  \ \  \_| \ \  \ \  \|\  \ " -ForegroundColor yellow
Write-Host "   \ \__\ \_______\   \ \__\ \ \_______\       \ \_______\ \_______\ \__\\ \__\ \__\   \ \__\ \_______\" -ForegroundColor yellow
Write-Host "    \|__|\|_______|    \|__|  \|_______|        \|_______|\|_______|\|__| \|__|\|__|    \|__|\|_______|`n`n" -ForegroundColor yellow
Write-Host "`nNotice: This tool cannot document or update the following IoT Central application settings: Dashboards, Views, Custom Settings on Device Templates, Pricing Plan, UX Customizations (Appearance & App Links), Application Image, Rules, Scheduled Jobs, Saved Jobs, and Enrollment Groups"

<#
.SYNOPSIS
Downloads device models and generates a config file

.DESCRIPTION
Downloads all device models and then generates a config file that can be used to replicate an IoT Central application's configuraiton in a new IoT Central application

This currently will not do the following:
1. Document or update Dashboards, Views, Custom Settings on Device Templates, Pricing Plan, UX Customizations (Appearance & App Links), Application Image, Rules, Scheduled Jobs, Saved Jobs, and Enrollment Groups"
2. Remove settings from the target IoT Central app that are not present in the config file
#>
Function Build-Config{
    $ApiToken = Read-Host -Prompt "API Token (Admin Required)" -MaskInput
    $AppName = Read-Host -Prompt "IoT Central App Subdomain"
    $ConfigPath = Read-Host -Prompt "Config Directory"
    $VaultName = Read-Host -Prompt "Key Vault Name"
    $BaseUrl = "https://" + $AppName + ".azureiotcentral.com/api/"
    $Header = @{"authorization" = $ApiToken }

    Write-Host "`n`nChecking the specified directory" -ForegroundColor DarkGray
    #Ensure the expected directories exist
    if((test-path "$ConfigPath/IoTC Configuration") -eq $False){
        New-Item -Path "$ConfigPath/IoTC Configuration" -ItemType Directory
    }

    if((test-path "$ConfigPath/IoTC Configuration/Device Models") -eq $False){
        New-Item -Path "$ConfigPath/IoTC Configuration/Device Models" -ItemType Directory
    }

    #Copy All Device Models
    Write-Host "`nCopying device models......" -ForegroundColor DarkGray
    Save-DeviceModels
    Write-Host "     Device models created at $ConfigPath/Device Models/" -ForegroundColor DarkGray

    Write-Host "`nGenerating configuration file......" -ForegroundColor DarkGray

    #Begin Get Data Export Destinations
    $DestinationsObject = Get-CDEDestinations | ConvertFrom-Json -ErrorAction Stop
    Write-Host "     Data export destinations" -ForegroundColor DarkGray
    $DestinationsObject = @{"destinations" = $DestinationsObject}
    
    #Begin Get Data Exports
    $DataExportsObject = Get-DataExports | ConvertFrom-Json -ErrorAction Stop
    Write-Host "     Data exports" -ForegroundColor DarkGray
    $DataExportsObject = @{"data exports" = $DataExportsObject}

    #Begin Get Device Groups
    $JObject = Get-DeviceGroups | ConvertFrom-Json -ErrorAction Stop
    $deviceGroupsObject = @{"device groups" = $JObject}
    Write-Host "     Device groups" -ForegroundColor DarkGray

    #Begin Get File Uploads
    $Json = Get-FileUploads -ErrorAction Stop
    if($Json -eq "404"){
        Write-Host "     File uploads not configured" -ForegroundColor DarkGray -NoNewLine
        Write-Host " Skipping" -ForegroundColor green
    }
    else{
        $SecretName = "FileUplaod$AppName"
        $JObject = $Json | ConvertFrom-Json
        
        foreach ($element in $JObject.PSObject.Properties) {
            if($element.Name -eq "state" -or $element.Name -eq "etag"){
                $JObject.PSObject.Properties.Remove($element.Name)
                }
            if($element.Name -eq "connectionString"){
                $Secret = ConvertTo-SecureString $Element.value -AsPlainText
                $element.value = $SecretName
            }
        }
        $fileUploadsObject = @{"file uploads" = $JObject}
        Write-Host "     File uploads" -ForegroundColor DarkGray

        Set-AzKeyVaultSecret -VaultName $VaultName -Name $SecretName -SecretValue $Secret
    }

    #Begin Get Jobs
    $JObject = Get-Jobs | ConvertFrom-Json -ErrorAction Stop
    $jobsObject = @{"jobs" = $JObject}
    Write-Host "     Jobs" -ForegroundColor DarkGray

    #Begin Get Organizations
    $OrgsObject = Get-Orgs | ConvertFrom-Json -ErrorAction Stop
    Write-Host "     Organizations" -ForegroundColor DarkGray
    $OrgsObject = @{"organizations" = $OrgsObject}

    #Begin Get Roles
    $JObject = Get-Roles | ConvertFrom-Json -ErrorAction Stop
    $rolesObject = @{"roles" = $JObject}
    Write-Host "     Roles" -ForegroundColor DarkGray

    #Begin Get API Tokens
    $TokensObject = Get-Tokens | ConvertFrom-Json -ErrorAction Stop
    $TokensObject = @{"APITokens" = $TokensObject}
    Write-Host "     API Tokens" -ForegroundColor DarkGray

    #Create the Config File
    $JsonFile = @{}
    $JsonFile += $destinationsObject += $dataExportsObject += $devicegroupsObject += $fileUploadsObject += $jobsObject += $orgsObject += $rolesObject += $TokensObject

    $JsonFile | ConvertTo-Json -Depth 10 | Set-Content "$ConfigPath/IoTC Configuration/IoTC-Config.json" -ErrorAction Stop
    Write-Host "Config file saved at $ConfigPath/IoTC-Config.json" -ForegroundColor DarkGray
    Write-Host "`nFinished`n`n`n`n`n" -ForegroundColor green

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
    $ApiToken = Read-Host -Prompt "API Token (Admin Required)" -MaskInput
    $AppName = Read-Host -Prompt "IoT Central App Subdomain"
    $ConfigPath = Read-Host -Prompt "Config Directory"
    $VaultName = Read-Host -Prompt "Key Vault Name"
    $BaseUrl = "https://" + $AppName + ".azureiotcentral.com/api/"
    $Header = @{"authorization" = $ApiToken }

    Write-Host "`n`nChecking the specified directory"
    #Ensure the expected directories exist
    if((test-path "$ConfigPath/IoTC Configuration") -eq $False){
        Write-Host "`nDirectory not found: $ConfigPath/IoTC Configuration" -ForegroundColor red
        Exit
    }

    if((test-path "$ConfigPath/IoTC Configuration/Device Models") -eq $False){
        Write-Host "`nDirectory not found: $ConfigPath/IoTC Configuration/Device Models" -ForegroundColor red
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
                    Write-Host "     Uploading model $Name to IoT Central" -ForegroundColor darkgray -NoNewLine
                    $Model = Add-DeviceModel -DeviceTemplateId $id -Model $Model
                    Write-Host @greenCheck
                }
                else{
                    $SourceObject = $Model | ConvertFrom-Json
                    $CloudObject = $CloudModel | ConvertFrom-Json
                    
                    $ContentEqual = ($SourceObject | ConvertTo-Json -Compress -Depth 100) -eq ($CloudObject | ConvertTo-Json -Compress -Depth 100)
                    
                    if($ContentEqual){
                        #They are the same so we don't need to do anything
                        Write-Host "     Model $Name already exists and is current " -ForegroundColor darkgray -NoNewLine
                        Write-Host @greenCheck
                    }
                    else{
                        #We need to update the model
                        Write-Host "     Updating model $Name in IoT Central " -ForegroundColor darkgray -NoNewLine
                        $ETag = Get-DeviceModelETag -DeviceTemplateId $id
                        $SourceObject | add-member -Name "etag" -Value "$ETag" -MemberType NoteProperty
                        $NewJson = $SourceObject | ConvertTo-Json -Depth 100 -Compress
                        $ETag = Update-DeviceModel -DeviceTemplateId $id -Model $NewJson -ErrorAction stop
                        Write-Host @greenCheck
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
        Write-Host "     Device groups not in config file." -ForegroundColor DarkGray -NoNewLine
        Write-Host " Skipping" -ForegroundColor green
    }
    else{
        $ContentEqual = ($CloudGroups | ConvertTo-Json -Compress -Depth 100) -eq ($ConfigGroups | ConvertTo-Json -Compress -Depth 100)

        if($ContentEqual){
            Write-Host "     Device groups match config " -ForegroundColor DarkGray -NoNewline
            Write-Host @greenCheck
        }
        else{
            Write-Host "     Comparing device groups to the config file " -ForegroundColor DarkGray -NoNewLine
            Write-Host "No Match" -ForegroundColor DarkYellow
        }
    }


    # #Compare Jobs to Config
    # $CloudJobs = Get-Jobs -ErrorAction stop
    # $CloudJobsObj = $CloudJobs | ConvertFrom-Json
    # $JobsConfigObj = $ConfigObj."jobs"
    # if($JobsConfigObj.length -eq 0){
    #     Write-Host "     Jobs not in config file." -ForegroundColor DarkGray -NoNewLine
    #   Write-Host " Skipping" -ForegroundColor green
    # }
    # else{
    #     #Remove status from the JSON so we can accurately compare the config to the app
    #     $CloudJobsObj."value" | ForEach-Object {
    #         $_.PSObject.Properties.Remove("status")
    #     }
    #     $CloudJobsObj = $CloudJobsObj."value"

    #     #Remove status from the config so we can accurately compare the config to the app
    #     $JobsConfigObj."value" | ForEach-Object {
    #         $_.PSObject.Properties.Remove("status")
    #     }
    #     $JobsConfigObj = $JobsConfigObj."value"

    #     $ContentEqual = ($CloudJobsObj | ConvertTo-Json -Compress -Depth 100) -eq ($JobsConfigObj | ConvertTo-Json -Compress -Depth 100)

    #     if($ContentEqual){
    #         Write-Host "     Jobs match config " -ForegroundColor DarkGray -NoNewLine
    #         Write-Host @greenCheck
    #     }
    #     else{           
    #         #Iterate through jobs in config file to find the missing jobs
    #         $JobsConfigObj | ForEach-Object {
    #             $id = $_.id
    #             if(($CloudJobs -eq '{"value":[]}') -or ($CloudJobs -inotmatch $id)) #We need to add this job
    #             {
    #                 Write-Host "     Adding missing job " $_.'displayName'  -ForegroundColor DarkGray -NoNewline
    #                 $Config = $_ | ConvertTo-Json -Depth 100 -Compress
    #                 $Config
    #                 $Config = Add-Job -Config $Config -JobId $_.'id'
    #                 Write-Host @greenCheck
    #             }
    #             else{
    #                 Write-Host "CloudJobs:$CloudJobs"
    #                 Exit
    #             }
    #         }

    #     }
        
    # }

    #Compare Data Export Destinations to Config
    $ConfigDestinationsObj = $ConfigObj."destinations"
    if($ConfigDestinationsObj.length -eq 0){
        Write-Host "     Data Export Destinations not in config file." -ForegroundColor DarkGray -NoNewLine
        Write-Host " Skipping" -ForegroundColor green
    }
    else{
        $CloudDestinationsObj = Get-CDEDestinations -ErrorAction stop
        $CloudDestinationsObj = $CloudDestinationsObj | ConvertFrom-Json

        #Remove status from both source and target as they could be different
        $ConfigDestinationsObj."value" | ForEach-Object {
            $ConfigDestinationsObj.PSObject.Properties.Remove("status")
        }
        $CloudDestinationsObj."value" | ForEach-Object {
            $CloudDestinationsObj.PSObject.Properties.Remove("status")
        }
        $CloudDestinations = $CloudDestinationsObj | ConvertTo-Json -Depth 100 -Compress
        $ConfigDestinations = $ConfigDestinationsObj | ConvertTo-Json -Depth 100 -Compress

        $ContentEqual = ($CloudDestinations -eq $ConfigDestinations)
        if($ContentEqual){
            Write-Host "     Data export destinations match config " -ForegroundColor DarkGray -NoNewLine
            Write-Host @greenCheck
        }
        else{
            #Iterate through destinations in config file to find the missing exports
            $ConfigDestinationsObj | ForEach-Object {
                $Id = $_.id
                $Name = $_.name
                $DestinationConfigObj = $_.value[0]
                $DestinationConfigObj.PSObject.Properties.Remove("status")
                $SecretName = "Undefined"

                switch($DestinationConfigObj.type){
                    "webhook@v1" {
                        if($DestinationConfigObj.headerCustomizations."x-custom-region".secret -ne $false){
                            $SecretName = $DestinationConfigObj.headerCustomizations."x-custom-region".secret
                            $Secret = az keyvault secret show --vault-name $VaultName --name $SecretName
                            $DestinationConfigObj.headerCustomizations."x-custom-region".secret = $Secret
                        }
                        Break
                    }
                    "dataexplorer@v1" {
                        $SecretName = $DestinationConfigObj.authorization.clientSecret
                        $Result = az keyvault secret show --vault-name $VaultName --name $SecretName
                        $ResultObj = $Result | ConvertFrom-Json
                        $Secret = $ResultObj.value
                        $DestinationConfigObj.authorization.clientSecret = $Secret
                        Break
                    }
                    Default {
                        $SecretName = $DestinationConfigObj.authorization.connectionString
                        $Secret = az keyvault secret show --vault-name $VaultName --name $SecretName
                        $Result = az keyvault secret show --vault-name $VaultName --name $SecretName
                        $ResultObj = $Result | ConvertFrom-Json
                        $Secret = $ResultObj.value
                        $DestinationConfigObj.authorization.connectionString = $Secret
                    }
                }

                $Config = $DestinationConfigObj | ConvertTo-Json -Depth 100 -Compress

                if(($CloudDestinations.Length -eq 0) -or ($CloudDestinations -inotmatch $id)) #We need to add this data export
                {
                    Write-Host "     Adding missing data export destination $name " -ForegroundColor DarkGray -NoNewline
                    $Result = Add-Destination -Config $Config
                    Write-Host @greenCheck
                }
                elseif(($CloudDestinations.Length -gt 0) -and (!$CloudDestinations.Contains($Config))) #We need to update this data export
                {
                    Write-Host "     Updating existing data export destination $name " -ForegroundColor DarkGray -NoNewline
                    $Result = Add-Destination -Config $Config
                    Write-Host @greenCheck
                }
                else{
                    Write-Host "We didn't do anything with data export destinations"
                    Write-Host "Record: $Record"
                    Write-Host "ID: $Id"
                }
            }
        }
    }



    #Compare Data Exports to Config
    $ConfigExportsObj = $ConfigObj."data exports"
    if($ConfigExportsObj.length -eq 0){
        Write-Host "     Data exports not in config file." -ForegroundColor DarkGray -NoNewLine
        Write-Host " Skipping" -ForegroundColor green
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

        $ContentEqual = ($CloudExports -eq $ConfigExports)
        if($ContentEqual){
            Write-Host "     Data exports match config " -ForegroundColor DarkGray -NoNewLine
            Write-Host @greenCheck
        }
        else{
            #Iterate through data exports in config file to find the missing exports
            $ConfigExportsObj | ForEach-Object {
                $id = $_.id
                $name = $_.displayName
                $Config = $_.value | ConvertTo-Json -Depth 100 -Compress

                if(($CloudExports.Length -eq 0) -or ($CloudExports -inotmatch $id)) #We need to add this data export
                {
                    Write-Host "     Adding missing data export $name " -ForegroundColor DarkGray -NoNewline
                    $Result = Add-DataExport -Config $Config -DataExportId $id
                    Write-Host @greenCheck
                }
                elseif(($CloudExports.Length -gt 0) -and (!$cloudExports.Contains($Config))) #We need to update this data export
                {
                    Write-Host "     Updating existing data export $name " -ForegroundColor DarkGray -NoNewline
                    $Result = Add-DataExport -Config $Config -DataExportId $id
                    Write-Host @greenCheck
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
        Write-Host "     Organizations match config " -ForegroundColor DarkGray -NoNewline
        Write-Host @greenCheck
    }
    else{
        #Iterate through orgs in config file to find the missing orgs
        $ConfigOrgsObj."value" | ForEach-Object {
            $id = $_.id
            $name = $_.displayName
            if($CloudOrgs -inotmatch $id) #We need to add this org
            {
                Write-Host "     Adding missing organization $name " -ForegroundColor DarkGray -NoNewline
                $Config = $_ | ConvertTo-Json -Depth 100 -Compress
                $Config = Add-Org -Config $Config -OrgId $_.id
                Write-Host @greenCheck
            }
            elseif($CloudOrgs -inotmatch $_) #We need to update this org
            {
                Write-Host "     Updating existing org $name" -ForegroundColor DarkGray -NoNewline
                $Config = $_ | ConvertTo-Json -Depth 100 -Compress
                $Config = Add-Org -Config $Config -OrgId $id
                Write-Host @greenCheck
            }    
            else{
                Write-Host "     Organizations " -ForegroundColor DarkGray -NoNewline
                Write-Host "Missed" -ForegroundColor Red
            }
        }

    }


    #Compare Roles to Config
    $CloudRoles = Get-Roles -ErrorAction stop
    $CloudRoles = $CloudRoles | ConvertFrom-Json
    $RolesConfig = $ConfigObj."roles"

    $ContentEqual = ($CloudRoles | ConvertTo-Json -Compress -Depth 100) -eq ($RolesConfig | ConvertTo-Json -Compress -Depth 100)

    if($ContentEqual){
        Write-Host "     Roles match config " -ForegroundColor DarkGray -NoNewLine
        Write-Host @greenCheck
    }
    else{
        Write-Host "     Comparing roles to the config file " -ForegroundColor DarkGray -NoNewLine
        Write-Host "No Match" -ForegroundColor DarkYellow
    }

    #Compare File Uploads to Config
    $CloudUploads = Get-FileUploads -ErrorAction stop
    $CloudUploadsObj = $CloudUploads | ConvertFrom-Json
    $UploadsConfig = $ConfigObj."file uploads"

    if($UploadsConfig.length -eq 0){
        Write-Host "     File uploads not in config file." -ForegroundColor DarkGray -NoNewLine
        Write-Host " Skipping" -ForegroundColor green
    }
    else{
        #Remove state and etag from the JSON so we can accurately compare the config to the app
        $CloudUploadsObj | ForEach-Object {
            $_.PSObject.Properties.Remove("state")
            $_.PSObject.Properties.Remove("etag")
        }
        $ContentEqual = ($CloudUploadsObj | ConvertTo-Json -Compress -Depth 100) -eq ($UploadsConfig | ConvertTo-Json -Compress -Depth 100)

        if($ContentEqual){
            Write-Host "     File uploads match config " -ForegroundColor DarkGray -NoNewLine
            Write-Host @greenCheck
        }
        else{
            $Secret = az keyvault secret show --vault-name $VaultName --name $UploadsConfig.connectionString #Get the secret name from the connection string value in the config
            $ConnectionString = ($Secret | ConvertFrom-Json).value
            $UploadsConfig.connectionString = $ConnectionString   

            if($CloudUploads -eq "404"){ #There is no file upload configured currently
                Write-Host "     Adding file uploads config to IoT Central " -ForegroundColor DarkGray -NoNewLine
                $UploadsConfig = $UploadsConfig | ConvertTo-Json -Compress -Depth 100
                $UploadsConfig = Add-FileUploads -Config  $UploadsConfig
                Write-Host @greenCheck
            }
            else{ #We need to update the existing config
                Write-Host "     Updating file uploads config in IoT Central " -ForegroundColor DarkGray -NoNewLine
                $UploadsConfig = $UploadsConfig | ConvertTo-Json -Compress -Depth 100
                $UploadsConfig = Add-FileUploads -Config  $UploadsConfig
                Write-Host @greenCheck
            }
        }
    }

    #Compare API Tokens to Config
    $CloudTokens = Get-Tokens -ErrorAction stop
    $CloudTokensObj = $CloudTokens | ConvertFrom-Json
    $TokensConfig = $ConfigObj."APITokens"

    if($TokensConfig.length -eq 0){
        Write-Host "     API Tokens not in config file." -ForegroundColor DarkGray -NoNewLine
        Write-Host " Skipping" -ForegroundColor green
    }
    else{
        $ContentEqual = ($CloudTokensObj | ConvertTo-Json -Compress -Depth 100) -eq ($TokensConfig | ConvertTo-Json -Compress -Depth 100)

        if($ContentEqual){
            Write-Host "     API tokens match config " -ForegroundColor DarkGray -NoNewLine
            Write-Host @greenCheck
        }
        else{
            #Iterate through API tokens in config file to find the missing tokens
            $TokensConfig."value" | ForEach-Object {
                $id = $_.id
                $_.PSObject.Properties.remove("expiry")
                
                if($CloudTokens -inotmatch $id) #We need to add this API token
                {
                    Write-Host "     Adding missing API token $id " -ForegroundColor DarkGray -NoNewline
                    $Config = $_ | ConvertTo-Json -Depth 100 -Compress
                    $Result = Add-Token -TokenId $id -Config $Config
                    $Result = $Result | ConvertFrom-Json
                    $Secret = ConvertTo-SecureString $Result.token -AsPlainText
                    $Expires = (Get-Date).AddYears(1)
                    Set-AzKeyVaultSecret -VaultName $VaultName -Name $_.id -SecretValue $Secret -Expires $Expires
                    Write-Host @greenCheck

                }
            }
        }
    }

    Write-Host "     Adding dashboards " -ForegroundColor DarkGray -NoNewLine
    Write-Host "Not-Yet Supported" 

    Write-Host "     Adding custom device template settings " -ForegroundColor DarkGray -NoNewLine
    Write-Host "Not-Yet Supported" 

    Write-Host "     Adding views " -ForegroundColor DarkGray -NoNewLine
    Write-Host "Not-Yet Supported" 

    Write-Host "     Adding UX customizations " -ForegroundColor DarkGray -NoNewLine
    Write-Host "Not-Yet Supported" 

    Write-Host "     Adding rules " -ForegroundColor DarkGray -NoNewLine
    Write-Host "Not-Yet Supported" 

    Write-Host "     Adding saved and scheduled jobs " -ForegroundColor DarkGray -NoNewLine
    Write-Host "Not-Yet Supported" 
    
    Write-Host "     Adding enrollment groups " -ForegroundColor DarkGray -NoNewLine
    Write-Host "Not-Yet Supported" 



    Write-Host "`nFinished`n`n`n`n`n" -ForegroundColor green

        
}


#Display the Menu
do
 {
    Write-Host "============================= Options =============================" -ForegroundColor cyan
    Write-Host "1: Generate a config file from an existing IoT Central application." -ForegroundColor cyan
    Write-Host "2: Apply a config file to an existing IoT Central application." -ForegroundColor cyan
    Write-Host "Q: Press 'Q' to quit." -ForegroundColor cyan
    try{
    $selection = Read-Host "Options" -ErrorAction Stop
    }
    catch{
        Exit
    }
    switch ($selection)
    {
    '1' {
    Build-Config
    } '2' {
    Update-App
    } 
    }
    
 }
 until ($selection -eq 'q')