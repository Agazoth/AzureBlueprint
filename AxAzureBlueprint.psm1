function Connect-AzureBlueprint {
    [CmdletBinding()]
    param (
        [parameter(mandatory=$true)]
        [string]$ManagementGroupName,
        [switch]$Force
    )
    
    begin {
        $Script:AzureContext = Get-AzureRmContext
        if (!$Script:AzureContext){
            Login-AzureRMAccount
            $Script:AzureContext = Get-AzureRmContext
        }
        if (!$Script:AzureContext){
            Write-Warning "Could not connect to Azure"
            Continue
        }
    }
    
    process {
        $ManagementGroups = Get-AzureRmManagementGroup
        if ($ManagementGroups.Name -notcontains $ManagementGroupName){
            if ($Force){
                New-AzureRmManagementGroup -GroupName $ManagementGroupName
            } else {
                Write-Warning "$ManagementGroupName not found. Use the Force switch if you want to create it"
                continue
            }
        }
        $Script:ManagementGroupName = $ManagementGroupName
        $Script:AzureProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
        $Script:AzureProfileClient = New-Object -TypeName Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient -ArgumentList ($Script:AzureProfile)
        $Script:BlueprintPrefix = 'https://management.azure.com/providers/Microsoft.Management/managementGroups/{0}/providers/Microsoft.Blueprint/blueprints' -f $Script:ManagementGroupName
        $Script:APIversion = '?api-version=2017-11-11-preview'
        Write-Verbose "Connected to $ManagementGroupName"
    }
    
    end {
    }
}
function Get-AzureBlueprint {
    [CmdletBinding()]
    param (
        [Parameter (ParameterSetName = 'Specific', Mandatory = $True)]
        [string]$Blueprint,
        [Parameter (ParameterSetName = 'All')]
        [Switch]$ListAll,
        [switch]$AsObject
    )
    
    begin {
        if (!$Script:ManagementGroupName){Connect-AzureBlueprint}
        Get-Header
        $ParamHash = @{
            Uri = ''
            Method = 'Get'
            Headers = $Script:Header
            UseBasicParsing = $True
        }
    }
    
    process {
        if ($ListAll){
            $ParamHash.Uri = '{0}{2}' -f $Script:BlueprintPrefix,$Blueprint,$Script:APIversion
        } else {
            $ParamHash.Uri = '{0}/{1}{2}' -f $Script:BlueprintPrefix,$Blueprint,$Script:APIversion
        }
        try {
            $Blueprint = Invoke-WebRequest @ParamHash | Select-Object -ExpandProperty Content
        } catch {
            Write-Warning "$Blueprint not found!"
            continue
        }
    }
    
    end {
        if ($AsObject){
            $Blueprint | ConvertFrom-Json
        } else {
            $Blueprint
        }
    }
}
function Get-AzureBlueprintArtifact {
    [CmdletBinding()]
    param (
        [string]$Blueprint,
        [string[]]$Artifact,
        [switch]$ListAllArtifacts,
        [switch]$AsObject
    )
    
    begin {
        if (!$Script:ManagementGroupName){Connect-AzureBlueprint}
        Get-Header
        $ParamHash = @{
            Uri = ''
            Method = 'GET'
            Headers = $Script:Header
            UseBasicParsing = $True
        }
    }
    
    process {
        $ArtifactJson = @()
        if ($Artifact){
            $ArtifactJson += foreach ($a in $Artifact){
                $ParamHash.Uri = '{0}/{1}/artifacts/{2}{3}' -f $Script:BlueprintPrefix,$Blueprint,$a,$Script:APIversion
                Invoke-WebRequest @ParamHash | Select-Object -ExpandProperty Content
            }
        }
        elseif ($ListAllArtifacts){
            $ParamHash.Uri = '{0}/{1}/artifacts{2}' -f $Script:BlueprintPrefix,$Blueprint,$Script:APIversion
            $ArtifactJson += Invoke-WebRequest @ParamHash| Select-Object -ExpandProperty Content
        }
        else {
            Write-warning "Please provide specific artifact names or the -ListAllArtifacts switch"
            continue
        }
    }
    
    end {
        if ($AsObject){
            if ($ListAllArtifacts){
                $ArtifactJson | ConvertFrom-Json | Select-Object -ExpandProperty value
            } else {
                $ArtifactJson | ConvertFrom-Json
            }
        }
        else {$ArtifactJson}
    }
}
function Import-AzureBlueprintArtifact {
    [CmdletBinding()]
    param (
        [ValidateScript({$_.exists})]
        [System.IO.FileInfo]$ARMTemplateJson,
        [ValidateScript({$_.exists})]
        [System.Io.DirectoryInfo]$TargetDirectory,
        [parameter(mandatory=$true)]
        [string]$ResourceGroup,
        [parameter(mandatory=$true)]
        [string]$ArtifactName,
        [string]$NewBlueprintName = 'blueprint'
    )
    
    begin {
        $JsonObjects = Get-JsonObject -BlueprintFolder $TargetDirectory.FullName
        $ARMTemplate = ConvertFrom-Json -InputObject $(Get-Content $ARMTemplateJson.Fullname -Raw)
        $CurrentParameters = $ARMTemplate.parameters
        if (!$CurrentParameters ){
            $ARMTemplate
            continue
        }
        $MarkedParameters = Set-ArtifactParameter -ParameterObject $CurrentParameters -ResourceGroup $ResourceGroup
        Write-Verbose "Blueprint parameters has been calculated"
    }
    
    process {
        $Blueprint = $JsonObjects | Where-Object {!$_.kind}
        if ($Blueprint){
            Write-Verbose "Updating $($Blueprint.Filepath)"
            $Blueprint = Get-JsonObject -BlueprintFile $Blueprint.Filepath
            $Blueprint.JsonObject = Add-BlueprintParameter -BlueprintJson $Blueprint.JsonObject -ArtifactParameters $MarkedParameters -ResourceGroup $ResourceGroup
        } else {
            $Blueprintfile = '{0}\blueprint.json' -f $TargetDirectory.FullName
            Write-Warning "No blueprint found - creating $Blueprintfile"
            $Blueprint = [PSCustomObject]@{
                Filepath = $Blueprintfile
                Content = ''
                Kind = $Null
                BaseName = $NewBlueprintName 
                Name = '{0}.json' -f $NewBlueprintName 
                Blueprint = $TargetDirectory.Name
                JsonObject = New-BlueprintJsonObject -Parameters $MarkedParameters -ResourceGroup $ResourceGroup
            }
        }
        $Blueprint.Content = Convertto-Json -InputObject $Blueprint.JsonObject -Depth 99
        $Blueprint.Content | Out-file $Blueprint.Filepath

        $PairHash = Set-ArtifactParameter -ParameterObject $CurrentParameters -ResourceGroup $ResourceGroup -AsPairHash
        $PropParams = New-Object -TypeName PSCustomObject
        $TemplParams = New-Object -TypeName PSCustomObject
        foreach ($key in $PairHash.Keys){
            $ParamHash = @{
                InputObject = $PropParams
                NotePropertyName = $key
                NotePropertyValue = [PsCustomObject]@{value = "[parameters('{0}')]" -f $PairHash[$key]}
            }
            Add-Member @ParamHash
            $ParamHash = @{
                InputObject = $TemplParams
                NotePropertyName = $key
                NotePropertyValue = [PsCustomObject]@{type = $CurrentParameters.$key.type}
            }
            Add-Member @ParamHash
        }

        $ARMTemplate.parameters = $TemplParams
        $Artifact = [PSCustomObject]@{
            kind = 'template'
            properties = [PSCustomObject]@{
                template = $ARMTemplate
                resourceGroup = $ResourceGroup
                parameters = $PropParams
            }
        }
        $ArtifactFile = '{0}\{1}.json' -f $TargetDirectory.FullName,$ArtifactName
        Convertto-Json -InputObject $Artifact -Depth 99 | Out-File $ArtifactFile
    }
    
    end {
    }
}
function Remove-AzureBlueprint {
    [CmdletBinding()]
    param (
        [string]$Blueprint,
        [string[]]$Artifact,
        [switch]$Recurse
    )
    
    begin {
        $Ids = @()
        if ($Recurse){
            $Ids = Get-AzureBlueprint -Blueprint $Blueprint -AsObject | Select-Object -ExpandProperty Id
        }
        else {
            $Ids += Get-AzureBlueprintArtifact -Blueprint $Blueprint -Artifact $Artifact -AsObject | Select-Object -ExpandProperty Id
        }
    }
    
    process {
        foreach ($Id in $Ids){
            Get-Header
            $ParamHash = @{
                Uri = 'https://management.azure.com{0}{1}' -f $Id,$Script:APIversion
                Method = 'DELETE'
                Headers = $Script:Header
                UseBasicParsing = $True
            }
            $Name = $Id -split '/' | Select-Object -last 1
            try {
                $Req = Invoke-WebRequest @ParamHash
                Write-Verbose "$Name has been deleted"
            } catch {
                Write-Warning "$Name could not be delete"
            }

        }
    }
    
    end {
    }
}
function Set-AzureBlueprint {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateScript({$_.exists})]
        [System.IO.DirectoryInfo]$BlueprintFolder,
        [switch]$Passthru
    )
    
    begin {
        if (!$Script:ManagementGroupName){Connect-AzureBlueprint}
    }
    
    process {
        $JsonObjects = Get-JsonObject -BlueprintFolder $BlueprintFolder.FullName
        Get-Header
        foreach ($JsonObject in $($JsonObjects | Sort-Object kind)){
            $Name = '{0}{1}' -f $JsonObject.Blueprint,$(if ($JsonObject.kind){'/artifacts/{0}' -f $JsonObject.BaseName} else {''})
            $ParamHash = @{
                Uri = '{0}/{1}{2}' -f $Script:BlueprintPrefix,$Name,$Script:APIversion
                Method = 'PUT'
                Headers = $Script:Header
                Body = $JsonObject.Content
                UseBasicParsing = $True
            }
            Write-Verbose "Uri: $($ParamHash['Uri'])"
            try {
                $Put = Invoke-WebRequest @ParamHash -ErrorVariable Fail
                if ($Passthru){$Put.Content}
            } catch {
                Write-Warning "Could not set $($JsonObject.Name)"
                if ($Fail.message){
                    $Message = try {
                        $fail.message  | ConvertFrom-Json  | Select-Object -ExpandProperty error | Select-Object -ExpandProperty message | Out-String
                    }  catch {
                        $Fail.message
                    }
                }
                else {
                    $Message = $fail
                }
                Write-Warning $Message
            }
        }
    }
    
    end {
    }
}
function Add-BlueprintParameter {
    [CmdletBinding()]
    param (
        $BlueprintJsonObject,
        $ArtifactParameters,
        $ResourceGroupName
    )
    
    begin {
    }
    
    process {
        if (-not $BlueprintJsonObject.resourceGroups.$ResourceGroupName) {
            Write-Verbose "Adding ResourceGroup $ResourceGroupName to $($BlueprintJsonObject.Name)"
            $AddMemberParams = @{
                InputObject       = $BlueprintJsonObject.resourceGroups
                NotePropertyName  = $ResourceGroupName
                NotePropertyValue = @{}
            }            
        }
        $ArtifactNames = Get-Member -MemberType NoteProperty -InputObject $ArtifactParameters  | Select-Object -expand  Name
        foreach ($ArtifactName in $ArtifactNames) {
            $AddMemberParams = @{
                InputObject       = $BlueprintJsonObject.properties.parameters
                NotePropertyName  = $ArtifactName
                NotePropertyValue = $ArtifactParameters.$ArtifactName
                ErrorAction = 'Stop'
            }
            try {
                Add-Member @AddMemberParams
            } catch {
                Write-Verbose "$ArtifactName is already in the Blueprint"
            }
            
        }
    }
    
    end {
        $BlueprintJsonObject
    }
}
function Get-Header {
    [CmdletBinding()]
    param (
        [switch]$Passthru
    )
    
    begin {
    }
    
    process {
        $Token = $Script:AzureProfileClient.AcquireAccessToken($Script:AzureContext.Subscription.TenantId)
        Write-Verbose "Accesstoken: $($Token.AccessToken)"
        $Script:Header = @{
            'Content-Type'='application/json'
            'Authorization'='Bearer ' + $Token.AccessToken
        }
    }
    
    end {
        if ($Passthru){
            $Script:Header
        }
    }
}
function Get-JsonObject {
    [CmdletBinding(DefaultParameterSetName='Directory')]
    param (
        [Parameter(ParameterSetName='Directory')]
        [ValidateScript({$_.exists})]
        [System.IO.DirectoryInfo]$BlueprintFolder,
        [Parameter(ParameterSetName='Files')]
        [ValidateScript({$_.exists})]
        [System.IO.FileInfo[]]$BlueprintFile
    )
    
    begin {
        If ($PSCmdlet.ParameterSetName -eq 'Directory'){
            if ($JsonFiles = Get-ChildItem $BlueprintFolder.Fullname -Filter *.json){
            } else {
                Write-Warning "No json files found in $BlueprintFolder"
            }
        } else {
            $JsonFiles = $BlueprintFile
        }
        Write-Verbose $("Doing these files",$JsonFiles.Name | Out-String)
    }
    
    process {
        foreach ($File in $JsonFiles) {
            $FileContent = Get-Content $File.Fullname -Raw
            try {
                $Object = ConvertFrom-Json -InputObject $FileContent
                [PSCustomObject]@{
                    Filepath = $File.Fullname
                    Content = $FileContent
                    Kind = $Object.kind
                    Name = $File.Name
                    BaseName = $File.BaseName
                    Blueprint = $BlueprintFolder.Name
                    JsonObject = $Object
                }
            } catch {
                Write-Warning "$($File.Fullname) is not a valid JSON"
            }
        }
    }
    
    end {
    }
}
function New-BlueprintJsonObject {
    [CmdletBinding()]
    param (
        $Parameters,
        $Description = 'Autogenerated Blueprint',
        $TargetScope = 'subscription',
        $ResourceGroup
    )
    
    begin {
    }
    
    process {
        [PSCustomObject]@{
            properties = @{
                description    = $Description
                targetScope    = $TargetScope
                parameters = $Parameters
                resourceGroups = @{
                    $ResourceGroup = @{}
                }
            }
        }
    }
    
    end {
    }
}
function Set-ArtifactParameter {
    [CmdletBinding()]
    param (
        [PSCustomObject]$ParameterObject,
        $ResourceGroupName,
        $NameStyle = 'ResourceGroupName_ParameterName',
        $DisplayNameStyle = 'ParameterName (ResourceGroupName)',
        [switch]$AsPairHash
    )
    begin {
        $NameStyle = $NameStyle -replace 'ParameterName', '{0}' -replace 'ResourceGroupName', '{1}'
        $DisplayNameStyle = $DisplayNameStyle -replace 'ParameterName', '{0}' -replace 'ResourceGroupName', '{1}'
        $CurrentNPs = Get-Member -InputObject $ParameterObject -MemberType NoteProperty | Select-Object -ExpandProperty Name
    }
    process {
        if ($AsPairHash) {
            $PairHash = @{}
            foreach ($CurrentNP in $CurrentNPs) {
                $PairHash.Add($CurrentNP, $($NameStyle -f $CurrentNP, $ResourceGroupName))
            }
            $PairHash 
        }
        else {
            $NewObject = New-Object -TypeName PSCustomObject
            foreach ($CurrentNP in $CurrentNPs) {
                $NewNPName = $NameStyle -f $CurrentNP, $ResourceGroupName
                $NewNPdisplayName =  $DisplayNameStyle -f $CurrentNP, $ResourceGroupName
                Add-Member -InputObject $NewObject -NotePropertyName $NewNPName -NotePropertyValue $ParameterObject.$CurrentNP
                If (-not $NewObject.$NewNPName.metadata){
                    Add-Member -InputObject $NewObject.$NewNPName -NotePropertyName metadata -NotePropertyValue @{}
                }
                if (-not $NewObject.$NewNPName.metadata.displayName){
                    Add-Member -InputObject $NewObject.$NewNPName.metadata -NotePropertyName displayName -NotePropertyValue $NewNPdisplayName
                }
            }
            $NewObject
        }
    }
    end {
       
    }
   
}
