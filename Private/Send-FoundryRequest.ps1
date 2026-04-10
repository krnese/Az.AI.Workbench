function Send-FoundryRequest {
    <#
    .SYNOPSIS
        Internal helper — sends an HTTP request to the Foundry Responses API or AI Workbench.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$Path,

        [hashtable]$Body,

        [hashtable]$QueryParams,

        [int]$TimeoutSec = 120
    )

    $conn = $script:Connection
    if (-not $conn) {
        throw 'Not connected. Run Connect-AzAIFoundry first.'
    }

    # Build URL
    if ($conn.Mode -eq 'Workbench') {
        $baseUrl = $conn.WorkbenchUrl.TrimEnd('/')
        $url = "$baseUrl$Path"
    }
    else {
        # Foundry Direct
        $baseUrl = $conn.Endpoint.TrimEnd('/')
        $project = $conn.Project
        $apiVersion = $conn.ApiVersion
        $url = "$baseUrl/api/projects/$project$Path"
        $separator = if ($url.Contains('?')) { '&' } else { '?' }
        $url = "${url}${separator}api-version=$apiVersion"
    }

    # Build headers
    $headers = @{
        'Content-Type' = 'application/json'
    }

    if ($conn.Mode -eq 'Workbench') {
        # Workbench uses its own auth (Easy Auth passthrough or API key)
        if ($conn.ApiKey) {
            $headers['x-api-key'] = $conn.ApiKey
        }
    }
    else {
        # Foundry Direct — use API key or Az token
        if ($conn.ApiKey) {
            $headers['api-key'] = $conn.ApiKey
        }
        elseif ($conn.Token) {
            $headers['Authorization'] = "Bearer $($conn.Token)"
        }
    }

    # Build request params
    $requestParams = @{
        Method      = $Method
        Uri         = $url
        Headers     = $headers
        TimeoutSec  = $TimeoutSec
    }

    if ($Body) {
        $requestParams['Body'] = ($Body | ConvertTo-Json -Depth 20 -Compress)
    }

    Write-Verbose "[$Method] $url"

    try {
        $response = Invoke-RestMethod @requestParams
        return $response
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $errorBody = $_.ErrorDetails.Message

        if ($statusCode -eq 404) {
            throw "Resource not found: $Path"
        }
        elseif ($statusCode -eq 400) {
            throw "Bad request: $errorBody"
        }
        elseif ($statusCode -eq 401 -or $statusCode -eq 403) {
            throw "Authentication failed. Run Connect-AzAIFoundry to reconnect."
        }
        else {
            throw "Request failed ($statusCode): $errorBody"
        }
    }
}
