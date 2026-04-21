# Fan-Out + Synthesize — Parallel agents with result synthesis
# Demonstrates the isolated branch / fan-out orchestration pattern.
# Each branch runs on its own conversation. Results are synthesized on the shared conversation.
#
# Usage (with named agents):
#   ./fan-out-synthesize.ps1 -Endpoint <endpoint> -Project <project> `
#       -TriageAgent "ClassifierAgent" -BranchAgents @("DocsAgent","IncidentAgent")
#
# Usage (direct mode — no pre-configured agents needed):
#   ./fan-out-synthesize.ps1 -Endpoint <endpoint> -Project <project> -Model "gpt-5-mini"

param(
    [Parameter(Mandatory)]
    [string]$Endpoint,

    [Parameter(Mandatory)]
    [string]$Project,

    [string]$TriageAgent,

    [string[]]$BranchAgents,

    [string]$Model = 'gpt-5-mini'
)

Import-Module "$PSScriptRoot/../Az.AI.Workbench.psd1" -Force

Connect-AzAIFoundry -Endpoint $Endpoint -Project $Project

$conv = New-AzAIConversation

# ── Phase 1: Triage ──
Write-Host "Phase 1: Triage" -ForegroundColor Cyan
$triageMessage = "A customer reports they cannot access their Azure Key Vault in West Europe. They get 403 Forbidden on all operations. Started 2 hours ago."

if ($TriageAgent) {
    $triage = Invoke-AzAIAgent -Conversation $conv -AgentName $TriageAgent `
                -Message $triageMessage
}
else {
    # Direct mode triage — compose instructions at call time
    $triage = Invoke-AzAIAgent -Conversation $conv -Model $Model `
                -Instructions "You are an Azure support triage specialist. Classify the issue, identify affected services, and suggest investigation areas." `
                -Message $triageMessage
}
Write-Host "  Triage: $($triage.Response.Substring(0, [Math]::Min(200, $triage.Response.Length)))..."
Write-Host "  Duration: $($triage.DurationMs)ms"

# ── Phase 2: Fan-out — parallel branches (each gets isolated conversation) ──
Write-Host "`nPhase 2: Fan-out to specialists" -ForegroundColor Yellow

if ($BranchAgents -and $BranchAgents.Count -ge 2) {
    # Fan-out using named agents
    $branches = @(
        @{ AgentName = $BranchAgents[0]; Message = "Azure Key Vault 403 Forbidden troubleshooting steps and common causes" }
        @{ AgentName = $BranchAgents[1]; Message = "Known issues or service incidents affecting Azure Key Vault in West Europe" }
    )
}
else {
    # Fan-out using direct mode — different instructions per branch, same model
    $branches = @(
        @{
            Model        = $Model
            Instructions = "You are an Azure documentation expert. Provide troubleshooting steps based on official documentation."
            Message      = "Azure Key Vault 403 Forbidden troubleshooting steps and common causes"
        }
        @{
            Model        = $Model
            Instructions = "You are an Azure incident analyst. Focus on known issues, outages, and service health."
            Message      = "Known issues or service incidents affecting Azure Key Vault in West Europe"
        }
    )
}

$results = Invoke-AzAIFanOut -Branches $branches

foreach ($r in $results) {
    $status = if ($r.BranchStatus -eq 'Success') { '✅' } else { '❌' }
    $agent = if ($r.AgentName) { $r.AgentName } else { $r.Model }
    Write-Host "  $status $agent : $($r.Response.Length) chars, $($r.DurationMs)ms"
}

# ── Phase 3: Synthesize — back on the shared conversation ──
Write-Host "`nPhase 3: Synthesize" -ForegroundColor Green
$synthParams = @{
    Conversation  = $conv
    BranchResults = $results
    Prompt        = "Synthesize into: root cause hypothesis, confidence level, recommended immediate action, and escalation criteria."
}

if ($TriageAgent) {
    $synthParams.AgentName = $TriageAgent
}
else {
    $synthParams.Model = $Model
    $synthParams.Instructions = "You are a senior support engineer. Synthesize specialist findings into a clear action plan."
}

$resolution = Invoke-AzAISynthesize @synthParams
Write-Host $resolution.Response

Write-Host "`n--- Execution Summary ---" -ForegroundColor DarkGray
Write-Host "  Triage:     $($triage.DurationMs)ms"
Write-Host "  Fan-out:    $($results.Count) branches"
Write-Host "  Synthesis:  $($resolution.DurationMs)ms"
$totalTokens = $triage.TokensUsed.TotalTokens +
    ($results | ForEach-Object { $_.TokensUsed.TotalTokens } | Measure-Object -Sum).Sum +
    $resolution.TokensUsed.TotalTokens
Write-Host "  Total tokens: $totalTokens"
