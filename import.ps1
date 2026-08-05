#################################################
# HelloID-Conn-Prov-Target-Medicore-Import
# PowerShell V2
# Note: Only the fields id, name, hrNumber and isInternalAccount are returned with the GET all employees endpoint.
# If more fields are needed, A GET call foreach employee is required.
# We do not advice this approach, as it will significantly increase the runtime of the import action, especially with a large number of accounts.
# Preferably, the Medicore API would be updated to include the required fields in the GET all employees endpoint, to ensure optimal performance of the import action.
#################################################

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
    Write-Information 'Starting import of accounts'

    # Get access token
    $actionMessage = "creating access token for Medicore API"
    $token = Get-MedicoreAuthToken

    # Create headers
    $actionMessage = "creating authorization headers with Medicore access token"
    $headers = Set-MedicoreHeader -AccessToken $token

    # Get accounts
    $actionMessage = "querying accounts"    
    $splatImportAccountParams = @{
        Uri     = "$($actionContext.Configuration.BaseUrl)/employees?orderDirection=ASC"
        Method  = 'GET'
        Headers = $headers
    }
    $importedAccounts = (Invoke-RestMethod @splatImportAccountParams).data
    Write-Information "Queried accounts. Result count: $(($importedAccounts | Measure-Object).Count)"

    # Filter out 'archived' accounts, recognized by their name ending with _zz
    $actionMessage = "filtering out archived accounts, by filtering outnames ending with '_zz'"
    $importedAccounts = $importedAccounts | Where-Object { -not $_.name.EndsWith('_zz') }
    Write-Information "Filtered out archived accounts, by filtering outnames ending with '_zz'. Result count: $(($importedAccounts | Measure-Object).Count)"

    # Process each account and output account entitlement objects
    $actionMessage = "processing imported accounts and outputting account entitlements to HelloID"
    $importedAccountEntitlements = 0

    foreach ($importedAccount in $importedAccounts) {
        $actionMessage = "processing account [$($importedAccount.name) ($($importedAccount.hrNumber))]"

        # Making sure only fieldMapping fields are imported
        $data = @{}
        foreach ($field in $actionContext.ImportFields) {
            $data[$field] = $importedAccount.$field
        }

        # Make sure the AccountReference has a value
        $accountReference = $importedAccount.hrNumber
        if ([string]::IsNullOrEmpty($accountReference)) {
            $accountReference = $importedAccount.id
        }

        # Make sure the UserName has a value
        $displayName = $importedAccount.name
        if ([string]::IsNullOrEmpty($displayName)) {
            $displayName = $importedAccount.id
        }

        # Make sure the UserName has a value
        # No username available, as this is required, set to hrNumber
        $userName = $importedAccount.hrNumber
        if ([string]::IsNullOrEmpty($userName)) {
            $userName = $importedAccount.id
        }

        # Return the result
        Write-Output @{
            AccountReference = "$accountReference"
            displayName      = "$displayName"
            UserName         = "$userName"
            Enabled          = $false # No enabled status available, as this is required, set to false
            Data             = $data
        }

        # Increment count of imported account entitlements by 1
        $importedAccountEntitlements++
    }

    Write-Information "Completed import of accounts. Result count: $($importedAccountEntitlements)"
}
catch {
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

    Write-Error $errorMessage
}