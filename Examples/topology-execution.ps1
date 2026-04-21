# ============================================================
# Topology-as-Code Execution
# ============================================================
# This example shows the end-to-end workflow:
#   1. Connect to Foundry (or AI Workbench)
#   2. Load a topology YAML exported from AI Workbench
#   3. Execute it with role-aware prompt injection
#
# The topology YAML captures: agents, orchestration pattern,
# role hints, and configuration — validated in the Workbench UI,
# executed identically via PowerShell.
#
# Sample topologies included in Examples/topologies/:
#   chain-example.yaml    — Sequential refinement (3 agents)
#   panel-example.yaml    — Independent analysis + synthesis
#   debate-example.yaml   — Adversarial debate with judge
#   pipeline-example.yaml — Route → investigate → synthesize
#
# Usage:
#   # Foundry Direct (Entra ID)
#   ./topology-execution.ps1 -TopologyFile ./topologies/chain-example.yaml `
#       -Endpoint "https://ais-myproject.services.ai.azure.com" -Project "my-project"
#
#   # Via AI Workbench
#   ./topology-execution.ps1 -TopologyFile ./topologies/debate-example.yaml `
#       -WorkbenchUrl "https://my-workbench.azurewebsites.net"
#
#   # With a custom message (overrides samplePrompt in YAML)
#   ./topology-execution.ps1 -TopologyFile ./topologies/pipeline-example.yaml `
#       -Endpoint "..." -Project "..." -Message "Customer cannot access Key Vault"
# ============================================================

param(
    [Parameter(Mandatory)]
    [string]$TopologyFile,

    [string]$Message,

    [string]$Endpoint,
    [string]$Project,

    [string]$WorkbenchUrl
)

Import-Module "$PSScriptRoot/../Az.AI.Workbench.psd1" -Force

# ── Connect ──────────────────────────────────────────────────
if ($WorkbenchUrl) {
    Connect-AzAIFoundry -WorkbenchUrl $WorkbenchUrl
}
elseif ($Endpoint -and $Project) {
    Connect-AzAIFoundry -Endpoint $Endpoint -Project $Project
}
else {
    Write-Host "Usage:" -ForegroundColor Yellow
    Write-Host "  # Via Foundry Direct (Entra ID)"
    Write-Host "  ./topology-execution.ps1 -TopologyFile ./my-topology.yaml -Endpoint 'https://...' -Project 'my-project'"
    Write-Host ""
    Write-Host "  # Via AI Workbench"
    Write-Host "  ./topology-execution.ps1 -TopologyFile ./my-topology.yaml -WorkbenchUrl 'https://my-workbench.azurewebsites.net'"
    Write-Host ""
    Write-Host "  # With a custom message (overrides samplePrompt in YAML)"
    Write-Host "  ./topology-execution.ps1 -TopologyFile ./my-topology.yaml -Endpoint '...' -Project '...' -Message 'My question'"
    return
}

# ── Execute Topology ─────────────────────────────────────────
$params = @{ TopologyFile = $TopologyFile }
if ($Message) { $params.Message = $Message }

$result = Invoke-AzAITopology @params -Verbose

# ── Display Results ──────────────────────────────────────────
Write-Host "`n═══════════════════════════════════════════" -ForegroundColor White
Write-Host "  FINAL ANSWER" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════`n" -ForegroundColor White
Write-Host $result.FinalAnswer

Write-Host "`n═══════════════════════════════════════════" -ForegroundColor White
Write-Host "  EXECUTION SUMMARY" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════" -ForegroundColor White

$result.Steps | ForEach-Object {
    Write-Host "  $($_.Agent)" -ForegroundColor Cyan -NoNewline
    Write-Host " ($($_.Role))" -ForegroundColor Gray -NoNewline
    Write-Host " → $($_.Response.Length) chars, $($_.DurationMs)ms, $($_.TokensUsed.TotalTokens ?? 0) tokens" -ForegroundColor DarkGray
}

Write-Host "`n  Total: $($result.TotalTokens) tokens | $($result.TotalDuration)ms | $($result.StepCount) steps" -ForegroundColor White
Write-Host "═══════════════════════════════════════════`n" -ForegroundColor White
