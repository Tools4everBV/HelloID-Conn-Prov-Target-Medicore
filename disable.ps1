########################################################################
# HelloID-Conn-Prov-Target-Medicore-Disable
# PowerShell V2
######################################################

# Only perform type conversions when not in reconciliation mode (field mapping is used)
if ($actionContext.ReconciliationOrigin -ne 'reconciliation') {
    # Convert templateId to int, as this is required by the API
    if ($actionContext.Data.PSObject.Properties['templateId']) {
        $actionContext.Data.templateId = [int]$actionContext.Data.templateId
    }
    # Convert gender to int, as this is required by the API
    if ($actionContext.Data.PSObject.Properties['gender']) {
        $actionContext.Data.gender = [int]$actionContext.Data.gender
    }
    # Convert isAttendingPhysicianto bool, as this is required by the API
    if ($actionContext.Data.PSObject.Properties['isAttendingPhysician']) {
        $actionContext.Data.isAttendingPhysician = [System.Convert]::ToBoolean($actionContext.Data.isAttendingPhysician)
    }
    # Convert isPatientBoundto bool, as this is required by the API
    if ($actionContext.Data.PSObject.Properties['isPatientBound']) {
        $actionContext.Data.isPatientBound = [System.Convert]::ToBoolean($actionContext.Data.isPatientBound)
    }
}

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

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
    }
    catch {
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
        }
        elseif ((-not($null -eq $ErrorObject.Exception.Response) -and $ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException')) {
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

                }
                elseif ($convertedErrorObject.meta.messages.Length -gt 1) {
                    $httpErrorObj.FriendlyMessage = $convertedErrorObject.meta.messages.message -join ', '

                }
                elseif (-not [string]::IsNullOrEmpty($convertedErrorObject.error_description)) {
                    $httpErrorObj.FriendlyMessage = $convertedErrorObject.error_description

                }
                elseif (-not [string]::IsNullOrEmpty($convertedErrorObject.message)) {
                    $httpErrorObj.FriendlyMessage = $convertedErrorObject.message
                }
            }
            catch {
                Write-Warning "Unexpected web service response, Error during Json conversion: $($_.Exception.Message)"
            }
        }
        Write-Output $httpErrorObj
    }
}

function ConvertTo-FlatObject {
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]
        $Object,

        [string]
        $Prefix = ''
    )
    $result = [ordered]@{}
    foreach ($property in $Object.PSObject.Properties) {
        $name = if ($Prefix) {
            "$Prefix.$($property.Name)"
        }
        else {
            $property.Name
        }
        if ($null -ne $property.Value -and $property.Value.GetType().FullName -eq 'System.Management.Automation.PSCustomObject') {
            # if ($property.Value -is [PSCustomObject]) {
            $property.Value = $property.Value | Sort-Object
            $flattenedSubObject = ConvertTo-FlatObject -Object $property.Value -Prefix $name
            foreach ($subProperty in $flattenedSubObject.PSObject.Properties) {
                # Set property name to lower case to ensure this doesn't trigger an update
                $result[$subProperty.Name] = [string]$subProperty.Value
            }
        }
        else {
            $property.Value = $property.Value | Sort-Object

            $result[$name] = [string]$property.Value
        }
    }
    Write-Output ([PSCustomObject]$result)
}
#endregion functions

try {
    # Get access token
    $actionMessage = "creating access token for Medicore API"
    $token = Get-MedicoreAuthToken

    # Create headers
    $actionMessage = "creating authorization headers with Medicore access token"
    $headers = Set-MedicoreHeader -AccessToken $token


    # Get current account
    $actionMessage = "querying employee where hrNumber = [$($actionContext.References.Account)]"
    $queryEmployeeSplatParams = @{
        Uri         = "$($actionContext.Configuration.baseUrl)/employees/$($actionContext.References.Account)"
        Method      = "GET"
        Headers     = $headers
        ContentType = "application/json;charset=utf-8"
        Verbose     = $false
        ErrorAction = "Stop"
    }
    $correlatedAccount = (Invoke-RestMethod @queryEmployeeSplatParams).data

    # Apply reconciliation logic after retrieving current account
    if ($actionContext.ReconciliationOrigin -eq 'reconciliation') {
        # Reconciliation mode: Use hardcoded values for disable action
        # Set dateOutOfService to current date to disable the account
        $currentDate = Get-Date -Format "yyyy-MM-dd"
        $actionContext.Data = [PSCustomObject]@{
            dateOutOfService = $currentDate
        }
        $dataString = ($actionContext.Data.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ', '
        Write-Information "Reconciliation mode: disable ($dataString)"
    }

    # Determine action
    $actionMessage = "determining action"
    if (($correlatedAccount | Measure-Object).count -eq 1) {
        # Username is stored in user.name, set it to username to match the fieldmapping and to be able to compare it in the next step
        if ($correlatedAccount.user -and $correlatedAccount.user.name) {
            $correlatedAccount | Add-Member -MemberType NoteProperty -Name 'username' -Value $correlatedAccount.user.name -Force
        }

        # templateId is stored in templates.id, set it to templateId to match the fieldmapping and to be able to compare it in the next step
        if ($correlatedAccount.templates -and $correlatedAccount.templates.id) {
            $correlatedAccount | Add-Member -MemberType NoteProperty -Name 'templateId' -Value $correlatedAccount.templates.id -Force
        }

        # Set outputContext.PreviousData to deep copy of correlated account limited to the properties present in outputContext.Data (to support none mapping and storing the current data)
        $outputContext.PreviousData = ($correlatedAccount | Select-Object $outputContext.Data.PSObject.Properties.Name | ConvertTo-Json -Depth 10 | ConvertFrom-Json)

        # Set outputContext.Data to deep copy of correlated account, then merge with .Data (to support none mapping and storing the current data)
        $outputContext.Data = ($correlatedAccount | Select-Object $outputContext.Data.PSObject.Properties.Name | ConvertTo-Json -Depth 10 | ConvertFrom-Json)
        # Update/append fields from actionContext.Data into PreviousData
        foreach ($property in $actionContext.Data.PSObject.Properties) {
            if ($outputContext.Data.PSObject.Properties.Name -contains $property.Name) {
                # Update existing property
                $outputContext.Data.$($property.Name) = $property.Value
            }
            else {
                # Append with new property
                $outputContext.Data | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force
            }
        }

        # Normalize correlatedAccount to have the same properties as desired data
        # Select-Object will add null values for properties that don't exist in correlatedAccount
        $desiredData = $actionContext.Data
        $correlatedAccountNormalized = $correlatedAccount | Select-Object $desiredData.PSObject.Properties.Name
        
        # Normalize both objects to ensure null and empty string are treated as equivalent
        # and convert values to string for type-safe comparison
        $desiredDataNormalized = [PSCustomObject]@{}
        $correlatedAccountNormalized2 = [PSCustomObject]@{}
        
        foreach ($property in $desiredData.PSObject.Properties) {
            $desiredValue = $property.Value
            $currentValue = $correlatedAccountNormalized.$($property.Name)
            
            # Normalize null and empty string to empty string for both objects
            $normalizedDesiredValue = if ([string]::IsNullOrEmpty($desiredValue)) { "" } else { [string]$desiredValue }
            $normalizedCurrentValue = if ([string]::IsNullOrEmpty($currentValue)) { "" } else { [string]$currentValue }
            
            $desiredDataNormalized | Add-Member -MemberType NoteProperty -Name $property.Name -Value $normalizedDesiredValue
            $correlatedAccountNormalized2 | Add-Member -MemberType NoteProperty -Name $property.Name -Value $normalizedCurrentValue
        }
        
        # Compare all properties using Compare-Object
        $splatCompareProperties = @{
            ReferenceObject  = @($correlatedAccountNormalized2.PSObject.Properties)
            DifferenceObject = @($desiredDataNormalized.PSObject.Properties)
        }
        $propertiesChanged = Compare-Object @splatCompareProperties -PassThru | Where-Object { $_.SideIndicator -eq '=>' }
        
        if ($propertiesChanged) {
            $action = "UpdateAccount"
        }
        else {
            $action = "NoChanges"
        }
    }
    elseif (($correlatedAccount | Measure-Object).count -gt 1) {
        throw "Multiple accounts found where $($correlationField) = [$($correlationValue)]. Please correct this so the accounts are unique."
    }
    elseif (($correlatedAccount | Measure-Object).count -eq 0) {
        $action = "NotFound"
    }
    Write-Verbose "Determined action: $($action)"

    # Process
    switch ($action) {
        "UpdateAccount" {
            # Update account
            $actionMessage = "updating account with accountReference: [$($actionContext.References.Account)]. Properties changed: $($propertiesChanged.Name -join ', ')"

            # Create body with only the changed properties
            $updateAccountBody = @{}
            $propertiesChanged | ForEach-Object { $updateAccountBody[$_.Name] = $_.Value }
            
            $updateAccountSplatParams = @{
                Uri         = "$($actionContext.Configuration.baseUrl)/employees/$($actionContext.References.Account)"
                Method      = 'PUT'
                Headers     = $headers
                Body        = ([System.Text.Encoding]::UTF8.GetBytes(($updateAccountBody | ConvertTo-Json -Depth 10)))
                ContentType = "application/json;charset=utf-8"
                Verbose     = $false
                ErrorAction = "Stop"
            }

            if (-Not($actionContext.DryRun -eq $true)) {
                $updateAccountResponse = Invoke-RestMethod @updateAccountSplatParams

                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Action  = "UpdateAccount"
                        Message = "Updated account with AccountReference: [$($actionContext.References.Account)]. Properties changed: $($propertiesChanged.Name -join ', ')"
                        IsError = $false
                    })
            }
            else {
                Write-Information "[DryRun] Would update account with AccountReference: [$($actionContext.References.Account)]. Properties changed: $($propertiesChanged.Name -join ', ')"
            }
            break
        }

        "NoChanges" {
            $actionMessage = "skipping updating account with accountReference: [$($actionContext.References.Account)] (no changes)"
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Skipped updating account with AccountReference [$($actionContext.References.Account)]. Reason: No changes."
                    IsError = $false
                })
            break
        }

        "MultipleFound" {
            $actionMessage = "updating account with accountReference: [$($actionContext.References.Account)] (multiple found)"
            # Throw terminal error
            throw "Multiple accounts found with hrNumber: [$($actionContext.References.Account)]. Please correct this so the accounts are unique."
            break
        }

        "NotFound" {
            $actionMessage = "skipping updating account with accountReference: [$($actionContext.References.Account)] (not found)"
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Skipped updating account with AccountReference [$($actionContext.References.Account)]. Reason: Account not found."
                    IsError = $false
                })
            break
        }
    }

    $outputContext.Success = $true
}
catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq "Microsoft.PowerShell.Commands.HttpResponseException") -or
        $($ex.Exception.GetType().FullName -eq "System.Net.WebException")) {
        $errorObj = Resolve-MedicoreError -ErrorObject $ex
        $warningMessage = "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
        $errorMessage = "Error $($actionMessage). Error: $($errorObj.FriendlyMessage)"
    }
    else {
        $warningMessage = "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        $errorMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
    }
    Write-Warning $warningMessage

    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
}