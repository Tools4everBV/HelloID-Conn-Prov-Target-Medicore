####################################################################
# HelloID-Conn-Prov-Target-HelloID-ImportPermissionEntitlements-Location
# PowerShell V2
# Note: we get all employees and then further information for each employee individually to get the location assignments,
# This is needed as there is no endpoint to get the assigned locations per location
####################################################################

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
    Write-Information 'Starting import of location permission entitlements'

    # Get access token
    $actionMessage = "creating access token for Medicore API"
    $token = Get-MedicoreAuthToken

    # Create headers
    $actionMessage = "creating authorization headers with Medicore access token"
    $headers = Set-MedicoreHeader -AccessToken $token

    # Get employees (required as the location assignment is only available on employee objects)
    $actionMessage = "querying employees"
    $splatImportEmployeesParams = @{
        Uri         = "$($actionContext.Configuration.BaseUrl)/employees?orderDirection=ASC"
        Method      = 'GET'
        Headers     = $headers
        ContentType = "application/json;charset=utf-8"
        Verbose     = $false
        ErrorAction = "Stop"
    }
    $importedAccounts = (Invoke-RestMethod @splatImportEmployeesParams).data
    Write-Information "Queried employees. Result count: $(($importedAccounts | Measure-Object).Count)"

    # Filter out accounts without 'hrNumber', as this is required to get the full employee details as well as the account reference for the permission entitlement
    $actionMessage = "filtering out accounts without 'hrNumber'"
    $importedAccounts = $importedAccounts | Where-Object { -not [string]::IsNullOrEmpty($_.hrNumber) }
    Write-Information "Filtered out accounts without 'hrNumber'. Result count: $(($importedAccounts | Measure-Object).Count)"

    # Optional: filter out 'archived' accounts, recognized by '_zz' (set by the delete action). Disabled by default.
    # - Initial implementation: keep this disabled, so archived accounts are imported and can be correlated and put under management.
    # - After go-live, when Governance Reconciliation is used: enable this. Archived accounts are treated as deleted by HelloID, so without
    #   this filter they keep returning as accounts without an owner in every reconciliation report.
    # - Before enabling, verify how 'name' is composed for an archived account in the GET all employees response, as the check below must match it.
    # $actionMessage = "filtering out archived accounts, by filtering outnames ending with '_zz'"
    # $importedAccounts = $importedAccounts | Where-Object { -not $_.name.EndsWith('_zz') }
    # Write-Information "Filtered out archived accounts, by filtering outnames ending with '_zz'. Result count: $(($importedAccounts | Measure-Object).Count)"

    # Process each employee and output permission entitlement objects with account references in batches to prevent exceeding maximum limits
    $actionMessage = "querying location assignments of employees and outputting permission entitlements to HelloID (in batches of 500 account references)"
    $importedPermissionEntitlements = 0
    foreach ($importedAccount in $importedAccounts) {
        # Get current account with locations
        $actionMessage = "querying employee where hrNumber = [$($importedAccount.hrNumber)] to get location assignments for this employee"
        $queryUserSplatParams = @{
            Uri         = "$($actionContext.Configuration.baseUrl)/employees/$($importedAccount.hrNumber)"
            Method      = "GET"
            Headers     = $headers
            ContentType = "application/json;charset=utf-8"
            Verbose     = $false
            ErrorAction = "Stop"
        }
        $employeeWithLocations = $null
        $employeeWithLocations = (Invoke-RestMethod @queryUserSplatParams).data

        foreach ($location in $employeeWithLocations.locations) {
            # Shorten DisplayName to max. 100 chars
            $displayName = "$($location.name)"
            $displayName = $displayName.substring(0, [System.Math]::Min(100, $displayName.Length))

            Write-Output @{
                PermissionReference = @{
                    Id = "$($location.id)"
                }
                DisplayName         = "$displayName"
                AccountReferences   = @("$($employeeWithLocations.hrNumber)")
            }
            $importedPermissionEntitlements++
        }
    }

    Write-Information "Completed import of location permission entitlements. Result count: $($importedPermissionEntitlements)"
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