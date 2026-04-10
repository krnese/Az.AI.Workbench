# Agent Switching — Multiple agents on the same conversation
# Demonstrates the shared-conversation sequential handoff pattern

Import-Module ./Az.AI.Workbench.psd1

Connect-AzAIFoundry -WorkbenchUrl "https://app-support-cxa-e2e-swc.azurewebsites.net"

$conv = New-AzAIConversation

# Turn 1: MSLearn explains the concept
$r1 = Invoke-AzAIAgent -Conversation $conv -AgentName "MSLearn" `
        -Message "What are the common causes of Azure RBAC permission denied errors?"
Write-Host "MSLearn:" -ForegroundColor Cyan
Write-Host $r1.Response.Substring(0, [Math]::Min(300, $r1.Response.Length))
Write-Host "..."

# Turn 2: Switch to CaseAgent — it sees MSLearn's answer
$r2 = Invoke-AzAIAgent -Conversation $conv -AgentName "CaseAgent" `
        -Message "Based on the above, create a support case for a customer experiencing this"
Write-Host "`nCaseAgent:" -ForegroundColor Green
Write-Host $r2.Response.Substring(0, [Math]::Min(300, $r2.Response.Length))
Write-Host "..."

# Turn 3: Switch to direct mode with custom instructions
$r3 = Invoke-AzAIAgent -Conversation $conv `
        -Model "gpt-5-mini" `
        -Instructions "You are a concise executive summarizer. Use bullet points." `
        -Message "Summarize this entire conversation in 3 bullet points"
Write-Host "`nSummary (direct mode, gpt-5-mini):" -ForegroundColor Yellow
Write-Host $r3.Response

Write-Host "`nAll 3 turns used conversation: $($conv.ConversationId)" -ForegroundColor DarkGray
