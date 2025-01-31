#################################################
# HelloID-Conn-Prov-Target-Medicore-Update
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

$locationLookupField1 = { $_.Department.ExternalId } # Mandatory
$locationLookupField2 = { $_.Title.ExternalId }      # Not mandatory

#region functions
function Get-MedicoreAuthToken {
    [CmdletBinding()]
    param ()
    try {
        $grantBody = @{
            grant_type    = 'password'
            username      = $actionContext.configuration.username
            password      = $actionContext.configuration.password
            client_id     = $actionContext.configuration.client_id
            client_secret = $actionContext.configuration.client_secret
        }
        $splatToken = @{
            Uri         = "$($actionContext.configuration.TokenUrl)"
            Method      = 'POST'
            ContentType = 'application/x-www-form-urlencoded'
            Body        = $grantBody
        }
        Write-Output (Invoke-RestMethod @splatToken -Verbose:$false).access_token
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

function Set-MedicoreHeader {
    [CmdletBinding()]
    param (
        [parameter(Mandatory)]
        $AccessToken
    )
    Write-Output @{
        Authorization               = "Bearer $($AccessToken)"
        'Ocp-Apim-Subscription-Key' = $actionContext.configuration.OcpApimSubscriptionKey
    }
}

function Resolve-MedicoreError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        $webResponse = $false
        if ($ErrorObject.ErrorDetails) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails
            $httpErrorObj.FriendlyMessage = $ErrorObject.ErrorDetails
            $webResponse = $true
        } elseif ((-not($null -eq $ErrorObject.Exception.Response) -and $ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException')) {
            $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
            if (-not([string]::IsNullOrWhiteSpace($streamReaderResponse))) {
                $httpErrorObj.ErrorDetails = $streamReaderResponse
                $httpErrorObj.FriendlyMessage = $streamReaderResponse
                $webResponse = $true
            }
        }

        if ($webResponse) {
            try {
                $convertedErrorObject = ($httpErrorObj.FriendlyMessage | ConvertFrom-Json)
                if ($convertedErrorObject.meta.messages.Length -eq 1) {
                    $httpErrorObj.FriendlyMessage = $convertedErrorObject.meta.messages[0].message

                } elseif ($convertedErrorObject.meta.messages.Length -gt 1) {
                    $httpErrorObj.FriendlyMessage = $convertedErrorObject.meta.messages.message -join ', '

                } elseif (-not [string]::IsNullOrEmpty($convertedErrorObject.error_description)) {
                    $httpErrorObj.FriendlyMessage = $convertedErrorObject.error_description

                } elseif (-not [string]::IsNullOrEmpty($convertedErrorObject.message)) {
                    $httpErrorObj.FriendlyMessage = $convertedErrorObject.message
                }
            } catch {
                Write-Warning "Unexpected web service response, Error during Json conversion: $($_.Exception.Message)"
            }
        }
        Write-Output $httpErrorObj
    }
}

function Compare-Array {
    [OutputType([array], [array], [array])] # $Left , $Right, $common
    param(
        [parameter(Mandatory)]
        [AllowNull()]
        [string[]]$ReferenceObject,

        [parameter(Mandatory)]
        [AllowNull()]
        [string[]]$DifferenceObject
    )
    if ($null -eq $DifferenceObject) {
        $Left = $ReferenceObject
    } elseif ($null -eq $ReferenceObject) {
        $right = $DifferenceObject
    } else {
        $left = [string[]][Linq.Enumerable]::Except($ReferenceObject, $DifferenceObject)
        $right = [string[]][Linq.Enumerable]::Except($DifferenceObject, $ReferenceObject)
        $common = [string[]][Linq.Enumerable]::Intersect($ReferenceObject, $DifferenceObject)
    }
    return $Left , $Right, $common
}

function Get-MedicoreLocationIdsFromMapping {
    [Cmdletbinding()]
    param(
        [parameter(Mandatory)]
        $LookupField1,

        $LookupField2,

        [parameter(Mandatory)]
        $Contracts,

        $Mapping,

        [string]
        $ColumnName1,

        [string]
        $ColumnName2
    )
    try {
        $list = [System.Collections.Generic.list[object]]::new()
        foreach ($contract in $Contracts) {
            $tableLookupValue1 = ($contract | Select-Object $LookupField1).$LookupField1

            if ($null -eq $tableLookupValue1) {
                throw "Calculation error. No results when filtering contracts in scope [$($contract.count)] on Header [$ColumnName1] Value [$LookupField1]"
            }
            $tableLookupValue2 = ($contract | Select-Object $LookupField2).$LookupField2
            Write-Information "Values found in Contract [$LookupField1 | $tableLookupValue1] and [$LookupField2 | $tableLookupValue2]"
            if ($null -ne $LookupField2) {
                if ($null -eq $tableLookupValue2) {
                    throw "Calculation error. No results when filtering contracts in scope [$($contract.count)] on Header [$ColumnName2] Value [$LookupField2]"
                }
                $result = $Mapping | Where-Object {
                    (
                        $_.$ColumnName1 -eq $tableLookupValue1 -and
                        $_.$ColumnName2 -eq $tableLookupValue2 ) -or
                    (
                        $_.$ColumnName1 -eq $tableLookupValue1 -and
                        [string]::IsNullOrEmpty($_.$ColumnName2 )
                    )
                }
            } else {
                $result = $Mapping | Where-Object {
                    (
                        $_.$ColumnName1 -eq $tableLookupValue1
                    )
                }
            }
            if ($null -eq $result) {
                throw "Calculation error. No entry found in the CSV file for [$LookupField1]: [$tableLookupValue1] and [$LookupField2] : [$tableLookupValue2]? (Second is optional)"
            }
            $list.add($result)
        }
        Write-Output $list

    } catch {
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }
}
#endregion

try {
    # Verify if [aRef] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

    Write-Information "Verifying if a Medicore account for [$($personContext.Person.DisplayName)] exists"

    $token = Get-MedicoreAuthToken
    $headers = Set-MedicoreHeader -AccessToken $token

    $splatGetEmployee = @{
        Uri     = "$($actionContext.configuration.BaseUrl)/employees/$($actionContext.References.Account)"
        Method  = 'GET'
        Headers = $headers
    }
    try {
        $employee = Invoke-RestMethod @splatGetEmployee -Verbose:$false
    } catch {
        $errorObj = Resolve-MedicoreError -ErrorObject $_
        if ($errorObj.FriendlyMessage -eq "No employee found for hrnumber ``$($actionContext.References.Account)``") {
            $correlatedAccount = $null
        } else {
            throw $errorObj.FriendlyMessage
        }
    }

    $correlatedAccount = $employee.data
    $outputContext.PreviousData = $correlatedAccount

    # Always compare the account against the current account in target system
    if ($null -ne $correlatedAccount) {
        #Preview : Note! there are no contracts in scope (InConditions) in the HelloID preview mode.
        [array]$desiredContracts = $personContext.person.contracts | Where-Object { $_.Context.InConditions -eq $true }
        if ($actionContext.DryRun -eq $true) {
            [array]$desiredContracts = $personContext.Person.Contracts
        }
        if ($desiredContracts.length -lt 1) {
            throw "[$($personContext.Person.DisplayName)] No Contracts in scope [InConditions] found!"
        }

        $auditLogsValidation = [System.Collections.Generic.List[PSCustomObject]]::new()

        # Lookup Template id
        $templateMappingTable = Import-Csv $actionContext.configuration.TemplateMappingPath
        $template = $templateMappingTable | Where-Object { $_.HelloIdTitle -eq $actionContext.Data.TemplateTitle -and $_.HelloIdDepartment -eq $actionContext.Data.TemplateDepartment }
        if (($template | Measure-Object).count -ne 1) {
            $auditLogsValidation.Add([PSCustomObject]@{
                    Message = "Template Mapping: [Calculation error. No entry found in the CSV file for Department [$($actionContext.Data.TemplateDepartment)] and Title [$($actionContext.Data.TemplateTitle)] Templates found: [$(($template | Measure-Object).count)]]"
                    IsError = $true
                })
        }

        # Lookup Location id(s)
        $locationMappingTable = Import-Csv $actionContext.configuration.LocationMappingPath
        $splatGetMedicoreLocationIds = @{
            LookupField1 = $locationLookupField1
            LookupField2 = $locationLookupField2
            Contracts    = $desiredContracts
            Mapping      = $locationMappingTable
            ColumnName1  = 'HelloIdDepartment'
            ColumnName2  = 'HelloIdTitle'
        }

        try {
            $desiredLocations = Get-MedicoreLocationIdsFromMapping @splatGetMedicoreLocationIds
            $desiredLocationUniqueIds = [array]($desiredLocations.LocationId | Select-Object -Unique).Where({ -not [string]::IsNullOrEmpty($_) })
            $actionContext.Data | Add-Member -MemberType NoteProperty -Name 'locations' -Value $desiredLocationUniqueIds
        } catch {
            $auditLogsValidation.Add([PSCustomObject]@{
                    Message = "Locations Mapping: [$($_.Exception.Message)]"
                    IsError = $true
                })
        }
        if ($auditLogsValidation.count -gt 0) {
            $outputContext.AuditLogs.AddRange($auditLogsValidation)
            throw 'Validation Error'
        }

        $correlatedAccount.PSObject.Properties.Remove("TemplateDepartment")
        $correlatedAccount.PSObject.Properties.Remove("TemplateTitle")

        $splatCompareProperties = @{
            ReferenceObject  = @($correlatedAccount.PSObject.Properties)
            DifferenceObject = @($actionContext.Data.PSObject.Properties)
        }

        $propertiesChangedObject = Compare-Object @splatCompareProperties -PassThru | Where-Object { $_.SideIndicator -eq '=>' }
        $propertiesChanged = @{}
        $propertiesChangedObject | ForEach-Object { $propertiesChanged[$_.Name] = $_.Value }

        # Additional compare for locations
        $locationsArray = @()
        if ((Compare-Object $actionContext.Data.locations $correlatedAccount.locations.id)) {
            foreach ($location in $actionContext.Data.locations) {
                $locationObject = [PSCustomObject]@{
                    id = [int]$location
                }
                $locationsArray += $locationObject
            }
            $propertiesChanged['locations'] = $locationsArray
        }

        # Additional compare for template
        if ((-not [string]::IsNullOrEmpty($template.TemplateId)) -and $template.TemplateId -ne $correlatedAccount.templates.id) {
            $propertiesChanged['templateId'] = [int]$template.TemplateId
        }

        if ($propertiesChanged.ContainsKey("gender")) {
            $propertiesChanged.gender = [int]$propertiesChanged.gender
        }
        if ($propertiesChanged.ContainsKey("isAttendingPhysician")) {
            $propertiesChanged.isAttendingPhysician = [bool]$propertiesChanged.isAttendingPhysician
        }
        if ($propertiesChanged.ContainsKey("isPatientBound")) {
            $propertiesChanged.isPatientBound = [bool]$propertiesChanged.isPatientBound
        }

        if ($propertiesChanged) {
            $action = 'UpdateAccount'
            $dryRunMessage = "Account property(s) required to update: $($propertiesChanged.keys -join ', ')"
        } else {
            $action = 'NoChanges'
            $dryRunMessage = 'No changes will be made to the account during enforcement'
        }
    } else {
        $action = 'NotFound'
        $dryRunMessage = "Medicore account for: [$($personContext.Person.DisplayName)] not found. Possibly deleted."
    }

    # Add a message and the result of each of the validations showing what will happen during enforcement
    if ($actionContext.DryRun -eq $true) {
        Write-Information "[DryRun] $dryRunMessage"
    }

    # Process
    if (-not($actionContext.DryRun -eq $true)) {
        switch ($action) {
            'UpdateAccount' {
                Write-Information "Updating Medicore account with accountReference: [$($actionContext.References.Account)]"

                $splatUpdateEmployee = @{
                    Uri     = "$($actionContext.configuration.BaseUrl)/employees/$($actionContext.References.Account)"
                    Method  = 'PUT'
                    Headers = $headers
                    Body = ([System.Text.Encoding]::UTF8.GetBytes(($propertiesChanged | ConvertTo-Json -depth 10)))
                }

                $null = Invoke-RestMethod @splatUpdateEmployee -Verbose:$false

                $outputContext.Success = $true
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Update account was successful, Account property(s) updated: [$($propertiesChanged.keys -join ',')]"
                        IsError = $false
                    })
                break
            }

            'NoChanges' {
                Write-Information "No changes to Medicore account with accountReference: [$($actionContext.References.Account)]"

                $outputContext.Success = $true
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = 'No changes will be made to the account during enforcement'
                        IsError = $false
                    })
                break
            }

            'NotFound' {
                $outputContext.Success = $false
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Medicore account with accountReference: [$($actionContext.References.Account)] could not be found, possibly indicating that it could be deleted, or the account is not correlated"
                        IsError = $true
                    })
                break
            }
        }
    }
} catch {
    $outputContext.success = $false
    $ex = $PSItem

    if (-not $ex.Exception.message -eq 'Validation Error') {
        $errorObj = Resolve-MedicoreError -ErrorObject $ex
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"

        $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = "Could not up[date Medicore account. Error: $($errorObj.FriendlyMessage)"
            IsError = $true
        })
    }
}
