#################################################
# HelloID-Conn-Prov-Target-Medicore-Create
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
    # Initial Assignments
    $outputContext.AccountReference = 'Currently not available'

    #Preview : Note! there are no contracts in scope (InConditions) in the HelloID preview mode.
    [array]$desiredContracts = $personContext.person.contracts | Where-Object { $_.Context.InConditions -eq $true }
    if ($actionContext.DryRun -eq $true) {
        [array]$desiredContracts = $personContext.person.contracts
    }
    if ($desiredContracts.length -lt 1) {
        throw "[$($($personContext.Person.DisplayName))] No Contracts in scope [InConditions] found!"
    }

    # Lookup Template id
    $auditLogsValidation = [System.Collections.Generic.List[PSCustomObject]]::new()

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

    $token = Get-MedicoreAuthToken
    $headers = Set-MedicoreHeader -AccessToken $token

    # Validate correlation configuration
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationField = $actionContext.CorrelationConfiguration.accountField
        $correlationValue = $actionContext.CorrelationConfiguration.accountFieldValue

        if ([string]::IsNullOrEmpty($($correlationField))) {
            throw 'Correlation is enabled but not configured correctly'
        }
        if ([string]::IsNullOrEmpty($($correlationValue))) {
            throw 'Correlation is enabled but [accountFieldValue] is empty. Please make sure it is correctly mapped'
        }

        $splatGetEmployee = @{
            Uri     = "$($actionContext.configuration.BaseUrl)/employees/$($correlationValue)"
            Method  = 'GET'
            Headers = $headers
        }
        try {
            $employee = Invoke-RestMethod @splatGetEmployee -Verbose:$false
            $correlatedAccount = $employee.data
        }
        catch {
            $errorObj = Resolve-MedicoreError -ErrorObject $_
            if ($errorObj.FriendlyMessage -eq "No employee found for hrnumber ``$($correlationValue)``") {
                $correlatedAccount = $null
            } else {
                throw $errorObj.FriendlyMessage
            }
        }
    }

    if ($null -ne $correlatedAccount) {
        $action = 'CorrelateAccount'
    } else {
        $action = 'CreateAccount'
    }

    # Add a message and the result of each of the validations showing what will happen during enforcement
    if ($actionContext.DryRun -eq $true) {
        Write-Information "[DryRun] $action Medicore account for: [$($personContext.Person.DisplayName)], will be executed during enforcement"
    }

    # Process
    if (-not($actionContext.DryRun -eq $true)) {
        switch ($action) {
            'CreateAccount' {
                Write-Information 'Creating and correlating Medicore account'

                $actionContext.Data | Add-Member -MemberType NoteProperty -Name 'locations' -Value $desiredLocationUniqueIds
                if ($actionContext.Data.locations.Count -eq 0 ) {
                    $actionContext.Data.locations = @($null)
                }

                $actionContext.Data.gender = [int]$actionContext.Data.gender

                if($actionContext.Data.PSObject.Properties['isAttendingPhysician']){
                    $actionContext.Data.isAttendingPhysician = [bool]$actionContext.Data.isAttendingPhysician
                }

                if($actionContext.Data.PSObject.Properties['isPatientBound']){
                    $actionContext.Data.isPatientBound = [bool]$actionContext.Data.isPatientBound
                }

                $splatNewEmployee = @{
                    Uri     = "$($actionContext.Configuration.BaseUrl)/employees/$($template.TemplateId)"
                    Method  = 'POST'
                    Headers = $headers
                    body    = ([System.Text.Encoding]::UTF8.GetBytes(($actionContext.Data | Select-Object * -ExcludeProperty TemplateTitle, TemplateDepartment | ConvertTo-Json -depth 10)))
                }

                $employee = Invoke-RestMethod @splatNewEmployee -Verbose:$false

                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Add Template to Account was successful. TemplateId is [$($template.TemplateId)]"
                        IsError = $false
                    })

                foreach ($location in $desiredLocationUniqueIds ) {
                    $outputContext.AuditLogs.Add([PSCustomObject]@{
                            Message = "Add Location to Account was successful. Location is [$location]"
                            IsError = $false
                        })
                }

                $outputContext.Data = $employee.data
                $outputContext.AccountReference = $employee.data.hrNumber
                $auditLogMessage = "Create account was successful. AccountReference is: [$($outputContext.AccountReference)]"
                break
            }

            'CorrelateAccount' {
                Write-Information 'Correlating Medicore account'

                $outputContext.Data = $correlatedAccount
                $outputContext.AccountReference = $correlatedAccount.hrNumber
                $outputContext.AccountCorrelated = $true
                $auditLogMessage = "Correlated account: [$($correlatedAccount.hrNumber)] on field: [$($correlationField)] with value: [$($correlationValue)]"
                break
            }
        }

        $outputContext.success = $true
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Action  = $action
                Message = $auditLogMessage
                IsError = $false
            })
    }
} catch {
    $outputContext.success = $false
    $ex = $PSItem

    if (-not $ex.Exception.message -eq 'Validation Error') {
        $errorObj = Resolve-MedicoreError -ErrorObject $ex
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"

        $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = "Could not create or correlate Medicore account. Error: $($errorObj.FriendlyMessage)"
            IsError = $true
        })
    }
}
 