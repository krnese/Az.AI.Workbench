function Invoke-AzAIAgent {
    <#
    .SYNOPSIS
        Invokes an AI agent via the Azure AI Foundry Responses API.

    .DESCRIPTION
        Sends a message to an agent and returns the complete response.
        Supports two execution modes:
        - Agent Reference: provide -AgentName to use a named agent in Foundry
        - Direct Mode: provide -Model (+ optional -Instructions, -Tools)

        Use -Conversation to continue on an existing conversation thread (shared-conversation pattern).
        Omit -Conversation to create a new isolated conversation.

    .EXAMPLE
        # Agent Reference mode
        $resp = Invoke-AzAIAgent -AgentName "MSLearn" -Message "What is Azure RBAC?"

    .EXAMPLE
        # Direct mode
        $resp = Invoke-AzAIAgent -Model "gpt-5-mini" -Instructions "You are a math tutor" -Message "What is 2+2?"

    .EXAMPLE
        # Shared conversation — agent switching
        $conv = New-AzAIConversation
        $r1 = Invoke-AzAIAgent -Conversation $conv -AgentName "MSLearn" -Message "Explain RBAC"
        $r2 = Invoke-AzAIAgent -Conversation $conv -AgentName "CaseAgent" -Message "Create a case for this"

    .EXAMPLE
        # Direct mode with MCP tools
        Invoke-AzAIAgent -Model "gpt-5-mini" -Instructions "Manage cases" -Tools @("https://my-mcp/mcp") -Message "List cases"
    #>
    [CmdletBinding(DefaultParameterSetName = 'AgentReference')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'AgentReference')]
        [string]$AgentName,

        [Parameter(Mandatory, ParameterSetName = 'DirectMode')]
        [string]$Model,

        [Parameter(ParameterSetName = 'DirectMode')]
        [string]$Instructions,

        [Parameter(ParameterSetName = 'DirectMode')]
        [string[]]$Tools,

        [Parameter(Mandatory)]
        [string]$Message,

        [PSCustomObject]$Conversation,

        [int]$MaxOutputTokens,

        [double]$Temperature,

        [switch]$NoAutoApprove
    )

    $conn = $script:Connection
    if (-not $conn) {
        throw 'Not connected. Run Connect-AzAIFoundry first.'
    }

    $convId = if ($Conversation) { $Conversation.ConversationId } else { $null }
    $mode = if ($AgentName) { 'agent_reference' } else { 'direct' }

    Write-Verbose "Mode: $mode | Agent: $($AgentName ?? $Model) | Conversation: $($convId ?? '(new)')"

    if ($conn.Mode -eq 'Workbench') {
        # Route through AI Workbench /api/invoke
        $body = ConvertTo-InvokePayload `
            -Message $Message `
            -AgentName $AgentName `
            -Model $Model `
            -Instructions $Instructions `
            -Tools $Tools `
            -ConversationId $convId `
            -MaxOutputTokens $MaxOutputTokens `
            -Temperature $Temperature `
            -AutoApprove (-not $NoAutoApprove)

        $result = Send-FoundryRequest -Method POST -Path '/api/invoke' -Body $body

        # Update conversation object if one was passed
        if ($Conversation -and $result.conversationId) {
            $Conversation.ConversationId = $result.conversationId
        }

        $output = [PSCustomObject]@{
            PSTypeName     = 'AzAIAgentResponse'
            ConversationId = $result.conversationId
            ResponseId     = $result.responseId
            AgentName      = $result.agentName
            Mode           = $result.mode
            Response       = $result.response
            ToolCalls      = $result.toolCalls
            TokensUsed     = if ($result.tokensUsed) {
                [PSCustomObject]@{
                    InputTokens  = $result.tokensUsed.inputTokens
                    OutputTokens = $result.tokensUsed.outputTokens
                    TotalTokens  = $result.tokensUsed.totalTokens
                }
            } else { $null }
            Model          = $result.model
            DurationMs     = $result.durationMs
        }

        # Auto-create conversation object for chaining if none was passed
        if (-not $Conversation) {
            $output | Add-Member -NotePropertyName '_Conversation' -NotePropertyValue ([PSCustomObject]@{
                ConversationId = $result.conversationId
                Source         = 'Workbench'
                CreatedAt      = Get-Date
            })
        }

        Write-Verbose "$($result.agentName ?? $Model) ($mode) → $($result.response.Length) chars, $($result.durationMs)ms"
        return $output
    }
    else {
        # Foundry Direct — build Responses API payload
        if (-not $convId) {
            $newConv = New-AzAIConversation
            $convId = $newConv.ConversationId
        }

        $body = @{
            conversation = $convId
            input        = $Message
            stream       = $false
        }

        if ($AgentName) {
            $body.agent = @{
                type = 'agent_reference'
                name = $AgentName
            }
        }
        else {
            $body.model = $Model
            if ($Instructions) { $body.instructions = $Instructions }
            if ($MaxOutputTokens -gt 0) { $body.max_output_tokens = $MaxOutputTokens }
            if ($Tools) {
                $body.tools = @($Tools | ForEach-Object {
                    @{ type = 'mcp'; server_url = $_; server_label = "mcp-$($Tools.IndexOf($_))" }
                })
            }
        }

        if ($PSBoundParameters.ContainsKey('Temperature')) {
            $body.temperature = $Temperature
        }

        $start = Get-Date
        $result = Send-FoundryRequest -Method POST -Path '/openai/responses' -Body $body
        $elapsed = ((Get-Date) - $start).TotalMilliseconds

        # Extract text from response output
        $responseText = ($result.output | Where-Object { $_.type -eq 'message' } |
            ForEach-Object { $_.content | Where-Object { $_.type -eq 'output_text' } | ForEach-Object { $_.text } }) -join ''

        $toolCalls = @($result.output | Where-Object { $_.type -eq 'mcp_call' } |
            ForEach-Object { [PSCustomObject]@{ name = $_.name; status = $_.status } })

        $usage = if ($result.usage) {
            [PSCustomObject]@{
                InputTokens  = $result.usage.input_tokens
                OutputTokens = $result.usage.output_tokens
                TotalTokens  = $result.usage.total_tokens
            }
        } else { $null }

        # Update conversation object
        if ($Conversation) {
            $Conversation.ConversationId = $convId
        }

        $output = [PSCustomObject]@{
            PSTypeName     = 'AzAIAgentResponse'
            ConversationId = $convId
            ResponseId     = $result.id
            AgentName      = $AgentName
            Mode           = $mode
            Response       = $responseText
            ToolCalls      = $toolCalls
            TokensUsed     = $usage
            Model          = $Model
            DurationMs     = [int]$elapsed
        }

        Write-Verbose "$($AgentName ?? $Model) ($mode) → $($responseText.Length) chars, $([int]$elapsed)ms"
        return $output
    }
}
