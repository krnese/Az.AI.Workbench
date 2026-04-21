# Basic Chat — Agent Reference & Direct Mode
# Shows multi-turn conversations using both execution modes.
#
# Usage:
#   ./basic-chat.ps1 -Endpoint <your-endpoint> -Project <your-project>
#   ./basic-chat.ps1 -Endpoint <your-endpoint> -Project <your-project> -AgentName "MyAgent"
#   ./basic-chat.ps1 -Endpoint <your-endpoint> -Project <your-project> -Model "gpt-4.1-mini"

param(
    [Parameter(Mandatory)]
    [string]$Endpoint,

    [Parameter(Mandatory)]
    [string]$Project,

    [string]$AgentName,

    [string]$Model = 'gpt-5-mini'
)

Import-Module "$PSScriptRoot/../Az.AI.Workbench.psd1" -Force

# Connect using Entra ID (no API key needed — uses your Azure identity)
Connect-AzAIFoundry -Endpoint $Endpoint -Project $Project

# Create a conversation
$conv = New-AzAIConversation

# ── Agent Reference Mode ──
# Use -AgentName to invoke a named agent deployed in your Foundry project.
# The agent brings its own instructions, tools, and model configuration.
if ($AgentName) {
    Write-Host "`n── Agent Reference Mode: $AgentName ──" -ForegroundColor Cyan

    $r1 = Invoke-AzAIAgent -Conversation $conv -AgentName $AgentName `
            -Message "What is Azure RBAC?"
    Write-Host "`n$AgentName says:" -ForegroundColor Cyan
    Write-Host $r1.Response

    # Turn 2 — same conversation, agent remembers context
    $r2 = Invoke-AzAIAgent -Conversation $conv -AgentName $AgentName `
            -Message "How do I assign a custom role?"
    Write-Host "`n$AgentName says:" -ForegroundColor Cyan
    Write-Host $r2.Response
}

# ── Direct Mode ──
# Use -Model to send requests without a pre-configured agent.
# You control the model, instructions, and tools per-request.
else {
    Write-Host "`n── Direct Mode: $Model ──" -ForegroundColor Cyan

    $r1 = Invoke-AzAIAgent -Conversation $conv -Model $Model `
            -Instructions "You are a helpful Azure cloud architect." `
            -Message "What is Azure RBAC?"
    Write-Host "`n[$Model] says:" -ForegroundColor Cyan
    Write-Host $r1.Response

    # Turn 2 — same conversation, context is preserved
    $r2 = Invoke-AzAIAgent -Conversation $conv -Model $Model `
            -Instructions "You are a helpful Azure cloud architect." `
            -Message "How do I assign a custom role?"
    Write-Host "`n[$Model] says:" -ForegroundColor Cyan
    Write-Host $r2.Response
}

# Token usage
Write-Host "`nTokens used:" -ForegroundColor Yellow
Write-Host "  Turn 1: $($r1.TokensUsed.TotalTokens) tokens ($($r1.DurationMs)ms)"
Write-Host "  Turn 2: $($r2.TokensUsed.TotalTokens) tokens ($($r2.DurationMs)ms)"
