########################################################################
# HelloID-Conn-Prov-Target-Medicore-Create
# PowerShell V2
######################################################

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
#endregion functions
try {
    # Initial Assignments
    $outputContext.AccountReference = 'Currently not available'

    # Get access token
    $actionMessage = "creating access token for Medicore API"
    $token = Get-MedicoreAuthToken

    # Create headers
    $actionMessage = "creating authorization headers with Medicore access token"
    $headers = Set-MedicoreHeader -AccessToken $token

    # Validate correlation configuration'
    $actionMessage = 'validating correlation configuration'
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationField = $actionContext.CorrelationConfiguration.AccountField
        $correlationValue = $actionContext.CorrelationConfiguration.PersonFieldValue

        if ([string]::IsNullOrEmpty($($correlationField))) {
            throw 'Correlation is enabled but not configured correctly'
        }
        if ([string]::IsNullOrEmpty($($correlationValue))) {
            throw 'Correlation is enabled but [accountFieldValue] is empty. Please make sure it is correctly mapped'
        }

        # Get current account
        $actionMessage = "querying employee where $($correlationField) = [$($correlationValue)]"
        $queryEmployeeSplatParams = @{
            Uri         = "$($actionContext.Configuration.baseUrl)/employees/$($correlationValue)"
            Method      = "GET"
            Headers     = $headers
            ContentType = "application/json;charset=utf-8"
            Verbose     = $false
            ErrorAction = "Stop"
        }
        try {
            $correlatedAccount = (Invoke-RestMethod @queryEmployeeSplatParams).data
        }
        catch {
            $ex = $PSItem
            $errorObj = Resolve-MedicoreError -ErrorObject $ex

            if ($errorObj.FriendlyMessage -eq "No employee found for hrnumber ``$($correlationValue)``") {
                $correlatedAccount = $null
            }
            else {
                throw $errorObj.FriendlyMessage
            }
        }
    }

    # Determine action
    $actionMessage = "determining action"
    if (($correlatedAccount | Measure-Object).count -eq 0) {
        $action = "CreateAccount"
    }
    elseif (($correlatedAccount | Measure-Object).count -eq 1) {
        $action = "CorrelateAccount"
    }
    elseif (($correlatedAccount | Measure-Object).count -gt 1) {
        $action = "MultipleFound"
    }
    Write-Information "Determined action: $($action)"

    # Process
    switch ($action) {
        "CreateAccount" {
            # Add location to existing locations array
            $actionMessage = "creating account with hrNumber [$($actionContext.Data.hrNumber)] and username [$($actionContext.Data.username)] and template [$($actionContext.Data.templateId)]"

            # Select all properties specified in field mapping, except for templateId
            $createAccountBody = $actionContext.Data | Select-Object * -ExcludeProperty templateId
            # locations property is required when creating the account, so we add it to the body with an array containing a null value
            $createAccountBody | Add-Member -MemberType NoteProperty -Name 'locations' -Value @($null) -Force

            $createAccountSplatParams = @{
                Uri         = "$($actionContext.Configuration.baseUrl)/employees/$($actionContext.Data.templateId)"
                Method      = 'POST'
                Headers     = $headers
                Body        = ([System.Text.Encoding]::UTF8.GetBytes(($createAccountBody | ConvertTo-Json -Depth 10)))
                ContentType = "application/json;charset=utf-8"
                Verbose     = $false
                ErrorAction = "Stop"
            }

            if (-Not($actionContext.DryRun -eq $true)) {
                $createAccountResponse = (Invoke-RestMethod @createAccountSplatParams).data

                $outputContext.Data = $createAccountResponse
                $outputContext.AccountReference = $createAccountResponse.hrNumber

                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Action  = "CreateAccount" # Optional
                        Message = "Created account with hrNumber [$($actionContext.Data.hrNumber)] and username [$($actionContext.Data.username)] and template [$($actionContext.Data.templateId)]. AccountReference is: [$($outputContext.AccountReference)]"
                        IsError = $false
                    })
            }
            else {
                Write-Information "[DryRun] Would create account with with hrNumber [$($actionContext.Data.hrNumber)] and username [$($actionContext.Data.username)] and template [$($actionContext.Data.templateId)]"
            }
            break
        }

        "CorrelateAccount" {
            $actionMessage = "correlating account on field: [$($correlationField)] with value: [$($correlationValue)]"
            $outputContext.AccountReference = "$($correlatedAccount.hrNumber)"
            $outputContext.Data = $correlatedAccount

            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Action  = "CorrelateAccount" # Optionally specify a different action for this audit log
                    Message = "Correlated to account with hrNumber [$($correlatedAccount.hrNumber)] and email [$($correlatedAccount.email)] with AccountReference [$($outputContext.AccountReference)] on field: [$($correlationField)] with value: [$($correlationValue)]"
                    IsError = $false
                })
            $outputContext.AccountCorrelated = $true
            break
        }

        "MultipleFound" {
            $actionMessage = "correlating account on field: [$($correlationField)] with value: [$($correlationValue)]"
            # Throw terminal error
            throw "Multiple accounts found where $($correlationField) = [$($correlationValue)]. Please correct this so the accounts are unique."
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