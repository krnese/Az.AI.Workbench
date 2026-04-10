# Fan-Out + Synthesize — Parallel specialists with result synthesis
# Demonstrates the isolated branch / fan-out orchestration pattern

Import-Module ./Az.AI.Workbench.psd1

Connect-AzAIFoundry -WorkbenchUrl "https://app-support-cxa-e2e-swc.azurewebsites.net"

$conv = New-AzAIConversation

# Phase 1: Triage — CaseAgent classifies the issue
Write-Host "Phase 1: Triage" -ForegroundColor Cyan
$triage = Invoke-AzAIAgent -Conversation $conv -AgentName "CaseAgent" `
            -Message "A customer reports they cannot access their Azure Key Vault in West Europe. They get 403 Forbidden on all operations. Started 2 hours ago."
Write-Host "  Triage: $($triage.Response.Substring(0, [Math]::Min(200, $triage.Response.Length)))..."
Write-Host "  Duration: $($triage.DurationMs)ms"

# Phase 2: Fan-out — parallel specialists (each gets isolated conversation)
Write-Host "`nPhase 2: Fan-out to specialists" -ForegroundColor Yellow
$results = Invoke-AzAIFanOut -Branches @(
    @{ AgentName = "MSLearn";   Message = "Azure Key Vault 403 Forbidden troubleshooting steps and common causes" }
    @{ AgentName = "MSSupport"; Message = "Known issues or service incidents affecting Azure Key Vault in West Europe" }
)

foreach ($r in $results) {
    $status = if ($r.BranchStatus -eq 'Success') { '✅' } else { '❌' }
    Write-Host "  $status $($r.AgentName): $($r.Response.Length) chars, $($r.DurationMs)ms, $($r.ToolCalls.Count) tools"
}

# Phase 3: Synthesize — back on the shared conversation
Write-Host "`nPhase 3: Synthesize" -ForegroundColor Green
$resolution = Invoke-AzAISynthesize -Conversation $conv -AgentName "CaseAgent" `
                -BranchResults $results `
                -Prompt "Synthesize into: root cause hypothesis, confidence level, recommended immediate action, and escalation criteria."
Write-Host $resolution.Response

Write-Host "`n--- Execution Summary ---" -ForegroundColor DarkGray
Write-Host "  Triage:     $($triage.DurationMs)ms"
Write-Host "  Fan-out:    $($results.Count) branches"
Write-Host "  Synthesis:  $($resolution.DurationMs)ms"
Write-Host "  Total tokens: $(($triage.TokensUsed.TotalTokens + ($results | ForEach-Object { $_.TokensUsed.TotalTokens } | Measure-Object -Sum).Sum + $resolution.TokensUsed.TotalTokens))"
