function Connect-AzAIFoundry {
    <#
    .SYNOPSIS
        Establishes a connection to Azure AI Foundry (direct) or an AI Workbench instance.

    .DESCRIPTION
        Stores connection details in module scope for subsequent cmdlets.
        Supports two connection modes:
        - Foundry Direct: provide -Endpoint and -Project (+ -ApiKey or uses Az token)
        - AI Workbench: provide -WorkbenchUrl to connect via an AI Workbench instance

    .EXAMPLE
        # Connect directly to Foundry
        Connect-AzAIFoundry -Endpoint "https://ais-myproject.services.ai.azure.com" -Project "my-project" -ApiKey $key

    .EXAMPLE
        # Connect via AI Workbench
        Connect-AzAIFoundry -WorkbenchUrl "https://app-support-cxa-e2e-swc.azurewebsites.net"

    .EXAMPLE
        # Connect with Az token (no API key needed)
        Connect-AzAIFoundry -Endpoint "https://ais-myproject.services.ai.azure.com" -Project "my-project"
    #>
    [CmdletBinding(DefaultParameterSetName = 'FoundryDirect')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'FoundryDirect')]
        [string]$Endpoint,

        [Parameter(Mandatory, ParameterSetName = 'FoundryDirect')]
        [string]$Project,

        [Parameter(ParameterSetName = 'FoundryDirect')]
        [Parameter(ParameterSetName = 'Workbench')]
        [string]$ApiKey,

        [Parameter(ParameterSetName = 'FoundryDirect')]
        [string]$ApiVersion = '2025-11-15-preview',

        [Parameter(Mandatory, ParameterSetName = 'Workbench')]
        [string]$WorkbenchUrl
    )

    if ($PSCmdlet.ParameterSetName -eq 'Workbench') {
        $script:Connection = @{
            Mode         = 'Workbench'
            WorkbenchUrl = $WorkbenchUrl.TrimEnd('/')
            ApiKey       = $ApiKey
        }

        # Validate connectivity
        try {
            $info = Invoke-RestMethod -Uri "$($script:Connection.WorkbenchUrl)/api/invoke" -Method Get -TimeoutSec 10
            Write-Verbose "Connected to AI Workbench: $($info.endpoint)"
        }
        catch {
            Write-Warning "Connected but could not reach /api/invoke — verify the Workbench URL."
        }

        Write-Host "Connected to AI Workbench at $WorkbenchUrl" -ForegroundColor Green
    }
    else {
        # Foundry Direct
        $token = $null
        if (-not $ApiKey) {
            try {
                $tokenResponse = Get-AzAccessToken -ResourceUrl 'https://ai.azure.com' -ErrorAction Stop
                # Newer Az module returns SecureString; convert to plain text
                if ($tokenResponse.Token -is [System.Security.SecureString]) {
                    $token = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR(
                        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($tokenResponse.Token)
                    )
                }
                else {
                    $token = $tokenResponse.Token
                }
                Write-Verbose 'Acquired Azure token for AI Foundry (audience: https://ai.azure.com)'
            }
            catch {
                throw 'No API key provided and Az token acquisition failed. Provide -ApiKey or run Connect-AzAccount first.'
            }
        }

        $script:Connection = @{
            Mode       = 'FoundryDirect'
            Endpoint   = $Endpoint.TrimEnd('/')
            Project    = $Project
            ApiKey     = $ApiKey
            Token      = $token
            ApiVersion = $ApiVersion
        }

        Write-Host "Connected to Azure AI Foundry: $Endpoint (project: $Project)" -ForegroundColor Green
    }
}
