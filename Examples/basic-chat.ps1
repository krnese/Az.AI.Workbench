# Basic Chat — Agent Reference Mode
# Connects to AI Workbench and has a multi-turn conversation with MSLearn

Import-Module ./Az.AI.Workbench.psd1

# Connect to your AI Workbench instance
Connect-AzAIFoundry -WorkbenchUrl "https://app-support-cxa-e2e-swc.azurewebsites.net"

# Create a conversation
$conv = New-AzAIConversation

# Turn 1
$r1 = Invoke-AzAIAgent -Conversation $conv -AgentName "MSLearn" -Message "What is Azure RBAC?"
Write-Host "`nMSLearn says:" -ForegroundColor Cyan
Write-Host $r1.Response

# Turn 2 — same conversation, agent remembers context
$r2 = Invoke-AzAIAgent -Conversation $conv -AgentName "MSLearn" -Message "How do I assign a custom role?"
Write-Host "`nMSLearn says:" -ForegroundColor Cyan
Write-Host $r2.Response

# Check token usage
Write-Host "`nTokens used:" -ForegroundColor Yellow
Write-Host "  Turn 1: $($r1.TokensUsed.TotalTokens) tokens ($($r1.DurationMs)ms)"
Write-Host "  Turn 2: $($r2.TokensUsed.TotalTokens) tokens ($($r2.DurationMs)ms)"
