function ConvertTo-InvokePayload {
    <#
    .SYNOPSIS
        Internal helper — converts cmdlet parameters into the request body for /api/invoke or Foundry Responses API.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [string]$AgentName,
        [string]$Model,
        [string]$Instructions,
        [string[]]$Tools,
        [string]$ConversationId,
        [int]$MaxOutputTokens,
        [double]$Temperature,
        [bool]$AutoApprove = $true
    )

    $body = @{
        message = $Message
    }

    # Agent Reference mode
    if ($AgentName) {
        $body.agentName = $AgentName
    }

    # Direct mode
    if ($Model) {
        $body.model = $Model
        if ($Instructions) {
            $body.instructions = $Instructions
        }
        if ($Tools -and $Tools.Count -gt 0) {
            $body.tools = @($Tools)
        }
    }

    # Optional fields
    if ($ConversationId) {
        $body.conversationId = $ConversationId
    }
    if ($MaxOutputTokens -gt 0) {
        $body.maxOutputTokens = $MaxOutputTokens
    }
    if ($PSBoundParameters.ContainsKey('Temperature')) {
        $body.temperature = $Temperature
    }
    if (-not $AutoApprove) {
        $body.autoApprove = $false
    }

    return $body
}
