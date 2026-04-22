function Export-AzAITopology {
    <#
    .SYNOPSIS
        Exports a topology YAML from a connected AI Workbench instance.

    .DESCRIPTION
        Downloads the current topology configuration from a running AI Workbench instance
        and saves it as a local YAML file. The exported file can then be executed with
        Invoke-AzAITopology or committed to source control for CI/CD automation.

        If the topology has been assessed, the exported YAML will include an assessment
        section with readiness scores, grades, and dimension breakdowns.

        Requires an active Workbench connection (Connect-AzAIFoundry -WorkbenchUrl ...).

    .PARAMETER Name
        Name for the topology. Used in metadata and as default filename.

    .PARAMETER Description
        Optional description for the topology.

    .PARAMETER Agents
        Array of agent names to include in the export.

    .PARAMETER Topology
        The topology pattern: chain, panel, debate, debate-rounds, or pipeline.

    .PARAMETER OutputPath
        Path to save the YAML file. Defaults to ./<name>.yaml in current directory.

    .PARAMETER SamplePrompt
        Optional sample prompt to embed in the topology config.

    .PARAMETER PassThru
        If specified, also returns the YAML content as a string.

    .EXAMPLE
        Export-AzAITopology -Name "support-triage" -Agents @("Classifier","Resolver","Reviewer") -Topology "chain" -OutputPath "./topologies/triage.yaml"

    .EXAMPLE
        # Export from Workbench with assessment scores included
        Connect-AzAIFoundry -WorkbenchUrl "https://my-workbench.azurewebsites.net"
        Export-AzAITopology -Name "my-flow" -Agents @("Agent1","Agent2") -Topology "panel"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [string]$Description,

        [Parameter(Mandatory)]
        [string[]]$Agents,

        [Parameter(Mandatory)]
        [ValidateSet('chain', 'panel', 'debate', 'debate-rounds', 'pipeline')]
        [string]$Topology,

        [string]$OutputPath,

        [string]$SamplePrompt,

        [hashtable]$RoleHints,

        [int]$DebateRounds,

        [int]$TokenBudget,

        [switch]$PassThru
    )

    if (-not $script:Connection) {
        throw "Not connected. Run Connect-AzAIFoundry first."
    }

    if ($script:Connection.Mode -ne 'Workbench') {
        # If in FoundryDirect mode, generate YAML locally without hitting Workbench
        Write-Verbose "FoundryDirect mode — generating topology YAML locally"
        $doc = [ordered]@{
            schemaVersion = '1.0'
            metadata = [ordered]@{
                name        = $Name
                description = if ($Description) { $Description } else { $null }
                created     = (Get-Date -Format 'o')
            }
            topology = $Topology
            agents   = @($Agents | ForEach-Object {
                $agent = [ordered]@{ name = $_ }
                if ($RoleHints -and $RoleHints[$_]) {
                    $agent.role = ($RoleHints[$_] -split "`n")[0].Substring(0, [Math]::Min(120, ($RoleHints[$_] -split "`n")[0].Length))
                    $agent.instructions = $RoleHints[$_]
                }
                $agent
            })
        }
        if ($DebateRounds -and $Topology -in @('debate', 'debate-rounds')) {
            $doc.debateRounds = $DebateRounds
        }
        $config = @{}
        if ($SamplePrompt) { $config.samplePrompt = $SamplePrompt }
        if ($TokenBudget)  { $config.tokenBudget = $TokenBudget }
        if ($config.Count -gt 0) { $doc.config = $config }
        $doc.resolution = [ordered]@{ strategy = 'name-match'; fallbackModel = 'gpt-5' }

        $yamlContent = $doc | ConvertTo-Yaml
    }
    else {
        # Workbench mode — call the export API
        Write-Host "⬇ Exporting topology from AI Workbench..." -ForegroundColor Cyan

        $body = @{
            name        = $Name
            description = $Description
            agents      = $Agents
            topology    = $Topology
        }
        if ($RoleHints)    { $body.roleHints = $RoleHints }
        if ($SamplePrompt) { $body.samplePrompt = $SamplePrompt }
        if ($DebateRounds) { $body.debateRounds = $DebateRounds }
        if ($TokenBudget)  { $body.tokenBudget = $TokenBudget }

        $headers = @{ 'Content-Type' = 'application/json' }
        if ($script:Connection.ApiKey) {
            $headers['x-api-key'] = $script:Connection.ApiKey
        }

        try {
            $yamlContent = Invoke-RestMethod `
                -Uri "$($script:Connection.WorkbenchUrl)/api/topology/export" `
                -Method Post `
                -Body ($body | ConvertTo-Json -Depth 10) `
                -Headers $headers `
                -TimeoutSec 30
        }
        catch {
            throw "Failed to export topology from Workbench: $($_.Exception.Message)"
        }
    }

    # Determine output path
    if (-not $OutputPath) {
        $safeName = $Name -replace '[^a-zA-Z0-9\-_]', '-'
        $OutputPath = Join-Path (Get-Location) "$safeName.yaml"
    }

    # Ensure directory exists
    $dir = Split-Path $OutputPath -Parent
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    # Write file
    $yamlContent | Out-File -FilePath $OutputPath -Encoding utf8 -Force

    # Display result
    $fileSize = (Get-Item $OutputPath).Length
    Write-Host ""
    Write-Host "  ✅ Topology exported" -ForegroundColor Green
    Write-Host "  📄 $OutputPath ($fileSize bytes)" -ForegroundColor Gray
    Write-Host ""

    # Show assessment scores if present
    if ($yamlContent -match 'assessment:') {
        Write-Host "  📊 Assessment scores included:" -ForegroundColor Cyan
        # Parse to show scores
        try {
            $parsed = $yamlContent | ConvertFrom-Yaml
            if ($parsed.assessment) {
                $a = $parsed.assessment
                Write-Host "     Readiness: $($a.readinessScore)/100 (Grade $($a.grade))" -ForegroundColor White
                if ($a.dimensions) {
                    foreach ($key in $a.dimensions.Keys) {
                        $d = $a.dimensions[$key]
                        $color = if ($d.score -ge 80) { 'Green' } elseif ($d.score -ge 60) { 'Yellow' } else { 'Red' }
                        Write-Host "     $($key): $($d.score)/100 ($($d.grade))" -ForegroundColor $color
                    }
                }
                Write-Host ""
            }
        }
        catch { }
    }

    Write-Host "  ▶ Run with:" -ForegroundColor DarkGray
    Write-Host "    Invoke-AzAITopology -TopologyFile `"$OutputPath`" -Message `"your prompt`"" -ForegroundColor White
    Write-Host ""

    if ($PassThru) {
        return $yamlContent
    }

    [PSCustomObject]@{
        Name       = $Name
        Topology   = $Topology
        Agents     = $Agents
        OutputPath = $OutputPath
        FileSize   = $fileSize
    }
}
