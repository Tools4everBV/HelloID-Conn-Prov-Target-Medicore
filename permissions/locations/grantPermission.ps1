########################################################################
# HelloID-Conn-Prov-Target-Medicore-GrantPermission-Location
# PowerShell V2
######################################################

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
    # Verify if [aRef] has a value
    $actionMessage = "verifying account reference"
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw "The account reference could not be found"
    }

    # Get access token
    $actionMessage = "creating access token for Medicore API"
    $token = Get-MedicoreAuthToken

    # Create headers
    $actionMessage = "creating authorization headers with Medicore access token"
    $headers = Set-MedicoreHeader -AccessToken $token

    # Get current account with locations
    $actionMessage = "querying employee where hrNumber = [$($actionContext.References.Account)]"
    $queryUserSplatParams = @{
        Uri         = "$($actionContext.Configuration.baseUrl)/employees/$($actionContext.References.Account)"
        Method      = "GET"
        Headers     = $headers
        ContentType = "application/json;charset=utf-8"
        Verbose     = $false
        ErrorAction = "Stop"
    }
    $correlatedAccount = (Invoke-RestMethod @queryUserSplatParams).data
    Write-Information "Found employee with hrNumber [$($actionContext.References.Account)], current locations: [$(($correlatedAccount.locations.id -join ', '))]"

    # Determine action
    $actionMessage = "determining action"
    $locationId = [int]$actionContext.References.Permission.id
    $currentLocationIds = @($correlatedAccount.locations.id)
    
    if (($correlatedAccount | Measure-Object).count -eq 1) {
        if ($currentLocationIds -contains $locationId) {
            $action = "AlreadyHasLocation"
        }
        else {
            $action = "GrantPermission"
        }
    }
    elseif (($correlatedAccount | Measure-Object).count -gt 1) {
        $action = "MultipleFound"
    }
    elseif (($correlatedAccount | Measure-Object).count -eq 0) {
        $action = "NotFound"
    }
    Write-Verbose "Determined action: $($action)"

    # Process
    switch ($action) {
        "GrantPermission" {
            # Add location to existing locations array
            $actionMessage = "granting location: [$($actionContext.PermissionDisplayName)] with locationId: [$($actionContext.References.Permission.id)] to account with AccountReference: $($actionContext.References.Account)"

            # Build array with existing locations + new location
            $locationsArray = @()
            foreach ($existingLocation in $correlatedAccount.locations) {
                $locationObject = [PSCustomObject]@{
                    id = [int]$existingLocation.id
                }
                $locationsArray += $locationObject
            }
            
            # Add new location
            $newLocationObject = [PSCustomObject]@{
                id = [int]$actionContext.References.Permission.Id
            }
            $locationsArray += $newLocationObject

            $updateAccountBody = @{
                locations = $locationsArray
            }

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
                        Action  = "GrantPermission"
                        Message = "Granted location: [$($actionContext.PermissionDisplayName)] with locationId: [$($actionContext.References.Permission.id)] to account with AccountReference: $($actionContext.References.Account)"
                        IsError = $false
                    })
            }
            else {
                Write-Information "[DryRun] Would grant location: [$($actionContext.PermissionDisplayName)] with locationId: [$($actionContext.References.Permission.id)] to account with AccountReference: [$($actionContext.References.Account)]"
            }
            break
        }

        "AlreadyHasLocation" {
            $actionMessage = "granting location: [$($actionContext.PermissionDisplayName)] with locationId: [$($actionContext.References.Permission.id)] to account with AccountReference: $($actionContext.References.Account)"

            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Action  = "GrantPermission"
                    Message = "Skipped granting location: [$($actionContext.PermissionDisplayName)] with locationId: [$($actionContext.References.Permission.id)] to account with AccountReference: $($actionContext.References.Account). Reason: Account already has location"
                    IsError = $false
                })
            break
        }

        "MultipleFound" {
            $actionMessage = "granting location: [$($actionContext.PermissionDisplayName)] with locationId: [$($actionContext.References.Permission.id)] to account with AccountReference: $($actionContext.References.Account)"
            # Throw terminal error
            throw "Multiple accounts found with hrNumber: [$($actionContext.References.Account)]. Please correct this so the accounts are unique."
            break
        }

        "NotFound" {
            $actionMessage = "granting location: [$($actionContext.PermissionDisplayName)] with locationId: [$($actionContext.References.Permission.id)] to account with AccountReference: $($actionContext.References.Account)"
            # Throw terminal error
            throw "No account found with hrNumber: [$($actionContext.References.Account)]."
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