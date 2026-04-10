function New-AzAIConversation {
    <#
    .SYNOPSIS
        Creates a new conversation in Azure AI Foundry.

    .DESCRIPTION
        Creates an empty conversation that can be used across multiple Invoke-AzAIAgent calls.
        Omit this cmdlet to let Invoke-AzAIAgent auto-create conversations.

    .EXAMPLE
        $conv = New-AzAIConversation
        Invoke-AzAIAgent -Conversation $conv -AgentName "MyAgent" -Message "Hello"

    .EXAMPLE
        $conv = New-AzAIConversation -Metadata @{ source = "automation"; caseId = "SR-12345" }
    #>
    [CmdletBinding()]
    param(
        [hashtable]$Metadata
    )

    $conn = $script:Connection
    if (-not $conn) {
        throw 'Not connected. Run Connect-AzAIFoundry first.'
    }

    if ($conn.Mode -eq 'Workbench') {
        $body = @{}
        if ($Metadata) { $body.metadata = $Metadata }

        $result = Send-FoundryRequest -Method POST -Path '/api/conversations' -Body $body
        $convId = $result.id ?? $result.conversationId

        Write-Verbose "Created conversation: $convId"
        return [PSCustomObject]@{
            ConversationId = $convId
            Source         = 'Workbench'
            CreatedAt      = Get-Date
        }
    }
    else {
        $body = @{}
        if ($Metadata) { $body.metadata = $Metadata }

        $result = Send-FoundryRequest -Method POST -Path '/openai/conversations' -Body $body
        $convId = $result.id

        Write-Verbose "Created conversation: $convId"
        return [PSCustomObject]@{
            ConversationId = $convId
            Source         = 'FoundryDirect'
            CreatedAt      = Get-Date
        }
    }
}
