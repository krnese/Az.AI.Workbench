# Agent Switching — Multiple agents on the same conversation
# Demonstrates the shared-conversation sequential handoff pattern.
# Mix agent reference and direct mode on a single conversation thread.
#
# Usage:
#   ./agent-switching.ps1 -Endpoint <endpoint> -Project <project> -Agent1 "ResearchAgent" -Agent2 "WriterAgent"
#   ./agent-switching.ps1 -Endpoint <endpoint> -Project <project> -Agent1 "ResearchAgent"
#   ./agent-switching.ps1 -Endpoint <endpoint> -Project <project> -SummaryModel "gpt-4.1"

param(
    [Parameter(Mandatory)]
    [string]$Endpoint,

    [Parameter(Mandatory)]
    [string]$Project,

    [string]$Agent1,

    [string]$Agent2,

    [string]$SummaryModel = 'gpt-5-mini'
)

Import-Module ./Az.AI.Workbench.psd1

Connect-AzAIFoundry -Endpoint $Endpoint -Project $Project

$conv = New-AzAIConversation

# ── Turn 1: First agent (or direct mode) ──
if ($Agent1) {
    Write-Host "Turn 1 — Agent: $Agent1" -ForegroundColor Cyan
    $r1 = Invoke-AzAIAgent -Conversation $conv -AgentName $Agent1 `
            -Message "What are the common causes of Azure RBAC permission denied errors?"
}
else {
    Write-Host "Turn 1 — Direct Mode: $SummaryModel" -ForegroundColor Cyan
    $r1 = Invoke-AzAIAgent -Conversation $conv -Model $SummaryModel `
            -Instructions "You are an Azure infrastructure expert." `
            -Message "What are the common causes of Azure RBAC permission denied errors?"
}
Write-Host $r1.Response.Substring(0, [Math]::Min(300, $r1.Response.Length))
Write-Host "..."

# ── Turn 2: Switch to second agent (or direct mode) ──
# The key insight: this agent sees everything from Turn 1 — no context copying.
if ($Agent2) {
    Write-Host "`nTurn 2 — Agent switch: $Agent2" -ForegroundColor Green
    $r2 = Invoke-AzAIAgent -Conversation $conv -AgentName $Agent2 `
            -Message "Based on the above, draft remediation steps for a customer experiencing this"
}
else {
    Write-Host "`nTurn 2 — Direct Mode (different instructions, same conversation)" -ForegroundColor Green
    $r2 = Invoke-AzAIAgent -Conversation $conv -Model $SummaryModel `
            -Instructions "You are a support engineer. Write actionable remediation steps." `
            -Message "Based on the above, draft remediation steps for a customer experiencing this"
}
Write-Host $r2.Response.Substring(0, [Math]::Min(300, $r2.Response.Length))
Write-Host "..."

# ── Turn 3: Direct mode summary ──
# Direct mode is always available — compose model + instructions on the fly.
Write-Host "`nTurn 3 — Direct Mode summary ($SummaryModel)" -ForegroundColor Yellow
$r3 = Invoke-AzAIAgent -Conversation $conv `
        -Model $SummaryModel `
        -Instructions "You are a concise executive summarizer. Use bullet points." `
        -Message "Summarize this entire conversation in 3 bullet points"
Write-Host $r3.Response

Write-Host "`nAll 3 turns used conversation: $($conv.ConversationId)" -ForegroundColor DarkGray
