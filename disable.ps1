##################################################
# HelloID-Conn-Prov-Target-Medicore-Disable
# PowerShell V2
##################################################

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
        $employee = (Invoke-RestMethod @splatGetEmployee -Verbose:$false).data
    } catch {
        $errorObj = Resolve-MedicoreError -ErrorObject $_
        if ($errorObj.FriendlyMessage -eq "No employee found for hrnumber ``$($actionContext.References.Account)``") {
            $correlatedAccount = $null
        } else {
            throw $errorObj.FriendlyMessage
        }
    }

    $correlatedAccount = $employee

    if ($null -ne $correlatedAccount) {
        $action = 'DisableAccount'
        $dryRunMessage = "Disable Medicore account: [$($actionContext.References.Account)] for person: [$($personContext.Person.DisplayName)] will be executed during enforcement"
    } else {
        $action = 'NotFound'
        $dryRunMessage = "Medicore account: [$($actionContext.References.Account)] for person: [$($personContext.Person.DisplayName)] could not be found, possibly indicating that it could be deleted, or the account is not correlated"
    }

    # Add a message and the result of each of the validations showing what will happen during enforcement
    if ($actionContext.DryRun -eq $true) {
        Write-Information "[DryRun] $dryRunMessage"
    }

    # Process
    if (-not($actionContext.DryRun -eq $true)) {
        switch ($action) {
            'DisableAccount' {
                Write-Information "Disabling Medicore account with accountReference: [$($actionContext.References.Account)]"

                $disableBody = [PSCustomObject]@{
                    dateInService    = $actionContext.Data.dateInService
                    dateOutOfService = $actionContext.Data.dateOutOfService
                }

                $splatDisableEmployee = @{
                    Uri     = "$($actionContext.configuration.BaseUrl)/employees/$($actionContext.References.Account)"
                    Method  = 'PUT'
                    Headers = $headers
                    Body    = ($disableBody | ConvertTo-Json -depth 10)
                }

                $disabledEmployee = Invoke-RestMethod @splatDisableEmployee -Verbose:$false

                $outputContext.Success = $true
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = 'Disable account was successful'
                        IsError = $false
                    })
                break
            }

            'NotFound' {
                $outputContext.Success = $true
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Medicore account: [$($actionContext.References.Account)] for person: [$($personContext.Person.DisplayName)] could not be found, possibly indicating that it could be deleted, or the account is not correlated"
                        IsError = $false
                    })
                break
            }
        }
    }
} catch {
    $outputContext.success = $false
    $ex = $PSItem

    $errorObj = Resolve-MedicoreError -ErrorObject $ex
    Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"

    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = "Could not disable Medicore account. Error: $($errorObj.FriendlyMessage)"
            IsError = $true
        })   
}