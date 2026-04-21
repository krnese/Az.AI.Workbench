function Invoke-AzAITopology {
    <#
    .SYNOPSIS
        Executes a multi-agent topology from a YAML definition file.

    .DESCRIPTION
        Reads a topology YAML file exported from AI Workbench (or hand-authored),
        resolves agents against the connected Foundry project or Workbench instance,
        and executes the orchestration pattern with role-aware prompt injection —
        the same strategy used by the AI Workbench backend.

        Supported topologies: chain, panel, debate, debate-rounds, pipeline.

        Agent resolution:
        - Name-match: agents are matched by name against Get-AzAIAgent
        - Fallback: unresolved agents run in direct mode using the topology's
          fallbackModel and the agent's instructions from the YAML

    .PARAMETER TopologyFile
        Path to a topology YAML file (schemaVersion 1.0).

    .PARAMETER Message
        The user message / scenario to run through the topology.
        If omitted, uses config.samplePrompt from the YAML.

    .PARAMETER MaxOutputTokens
        Optional per-agent max output token limit.

    .EXAMPLE
        # Execute a topology exported from AI Workbench
        Invoke-AzAITopology -TopologyFile ./my-topology.yaml -Message "Analyze RBAC issue"

    .EXAMPLE
        # Use the sample prompt embedded in the YAML
        Invoke-AzAITopology -TopologyFile ./support-case-investigation.yaml

    .EXAMPLE
        # Execute with verbose output showing each agent step
        Invoke-AzAITopology -TopologyFile ./debate.yaml -Message "Microservices vs monolith?" -Verbose
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TopologyFile,

        [string]$Message,

        [int]$MaxOutputTokens
    )

    $conn = $script:Connection
    if (-not $conn) {
        throw 'Not connected. Run Connect-AzAIFoundry first.'
    }

    # ── Parse YAML ────────────────────────────────────────────
    if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
        throw "Module 'powershell-yaml' is required. Install with: Install-Module powershell-yaml"
    }
    Import-Module powershell-yaml -ErrorAction Stop

    if (-not (Test-Path $TopologyFile)) {
        throw "Topology file not found: $TopologyFile"
    }

    $yamlContent = Get-Content -Path $TopologyFile -Raw
    $doc = ConvertFrom-Yaml $yamlContent

    if (-not $doc.schemaVersion) {
        throw "Invalid topology file: missing schemaVersion"
    }

    $topologyType = $doc.topology
    $validTopologies = @('chain', 'panel', 'debate', 'debate-rounds', 'pipeline')
    if ($topologyType -notin $validTopologies) {
        throw "Unsupported topology: '$topologyType'. Supported: $($validTopologies -join ', ')"
    }

    $agents = $doc.agents
    if (-not $agents -or $agents.Count -lt 2) {
        throw "Topology requires at least 2 agents. Found: $($agents.Count)"
    }

    # Resolve message
    if (-not $Message) {
        $Message = $doc.config.samplePrompt
        if (-not $Message) {
            throw "No -Message provided and no config.samplePrompt in the topology file."
        }
        $Message = $Message.Trim()
        Write-Verbose "Using sample prompt from topology: $($Message.Substring(0, [Math]::Min(80, $Message.Length)))..."
    }

    $fallbackModel = $doc.resolution.fallbackModel ?? 'gpt-5'
    $debateRounds = $doc.debateRounds ?? 2

    Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "  AI Workbench — Topology Execution" -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "  Topology:  $topologyType" -ForegroundColor White
    Write-Host "  Name:      $($doc.metadata.name ?? '(unnamed)')" -ForegroundColor Gray
    Write-Host "  Agents:    $($agents.Count)" -ForegroundColor White
    if ($topologyType -eq 'debate-rounds') {
        Write-Host "  Rounds:    $debateRounds" -ForegroundColor White
    }
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Cyan

    # ── Resolve Agents ────────────────────────────────────────
    # Try to match each YAML agent name against available agents
    $availableAgents = @()
    try {
        $availableAgents = @(Get-AzAIAgent | ForEach-Object { $_.Name })
        Write-Verbose "Available agents: $($availableAgents -join ', ')"
    }
    catch {
        Write-Verbose "Could not list agents: $_. Will use fallback model for all."
    }

    $resolvedAgents = @{}
    foreach ($agent in $agents) {
        $name = $agent.name
        if ($name -in $availableAgents) {
            $resolvedAgents[$name] = @{ Mode = 'agent_reference'; Name = $name }
            Write-Host "  ✓ $name" -ForegroundColor Green -NoNewline
            Write-Host " → agent reference" -ForegroundColor Gray
        }
        else {
            $resolvedAgents[$name] = @{
                Mode         = 'direct'
                Model        = $fallbackModel
                Instructions = $agent.instructions ?? $agent.role ?? ''
            }
            Write-Host "  ○ $name" -ForegroundColor Yellow -NoNewline
            Write-Host " → direct mode ($fallbackModel)" -ForegroundColor Gray
        }
    }
    Write-Host ""

    # ── Helper: invoke a resolved agent ───────────────────────
    function Invoke-ResolvedAgent {
        param(
            [string]$AgentName,
            [string]$Prompt,
            [string]$RoleHint
        )

        $resolved = $resolvedAgents[$AgentName]
        $params = @{ Message = $Prompt }

        if ($resolved.Mode -eq 'agent_reference') {
            $params.AgentName = $resolved.Name
            if ($RoleHint) { $params.Instructions = $RoleHint }
        }
        else {
            $params.Model = $resolved.Model
            # Layer: agent instructions + role hint (same as backend)
            $instructions = @($resolved.Instructions, $RoleHint) | Where-Object { $_ } | Join-String -Separator "`n`n"
            if ($instructions) { $params.Instructions = $instructions }
        }

        if ($MaxOutputTokens -gt 0) { $params.MaxOutputTokens = $MaxOutputTokens }

        $start = Get-Date
        $result = Invoke-AzAIAgent @params
        $elapsed = ((Get-Date) - $start).TotalMilliseconds

        return [PSCustomObject]@{
            Agent      = $AgentName
            Role       = ($agents | Where-Object { $_.name -eq $AgentName }).role ?? ''
            Response   = $result.Response
            TokensUsed = $result.TokensUsed
            DurationMs = [int]$elapsed
            ToolCalls  = $result.ToolCalls
        }
    }

    # ── Track execution steps ─────────────────────────────────
    $steps = [System.Collections.Generic.List[PSCustomObject]]::new()
    $totalStart = Get-Date
    $finalAnswer = ''

    # ══════════════════════════════════════════════════════════
    # TOPOLOGY EXECUTORS
    # Same prompt injection strategy as AI Workbench backend
    # ══════════════════════════════════════════════════════════

    switch ($topologyType) {

        'chain' {
            # Chain: sequential refinement with position-aware prompts
            $context = ''
            for ($i = 0; $i -lt $agents.Count; $i++) {
                $agent = $agents[$i]
                $isLast = ($i -eq $agents.Count - 1)
                $stepNum = $i + 1

                if ($i -eq 0) {
                    $prompt = $Message
                }
                elseif ($isLast) {
                    $prompt = @"
Previous analysis from other agents:

$context

---
Original question: $Message

Please synthesize a comprehensive final answer considering all prior perspectives.
"@
                }
                else {
                    $prompt = @"
Previous agent's analysis:

$context

---
Original question: $Message

Please build on the previous analysis and add your perspective.
"@
                }

                Write-Host "  [$stepNum/$($agents.Count)] $($agent.name)" -ForegroundColor Cyan -NoNewline
                Write-Host " ($($agent.role ?? 'agent'))" -ForegroundColor Gray

                $result = Invoke-ResolvedAgent -AgentName $agent.name -Prompt $prompt -RoleHint $agent.role
                $steps.Add($result)
                $context = $result.Response
                $finalAnswer = $result.Response

                Write-Host "      → $($result.Response.Length) chars, $($result.DurationMs)ms" -ForegroundColor DarkGray
            }
        }

        'panel' {
            # Panel: parallel independent analysis + synthesis
            $panelists = $agents[0..($agents.Count - 2)]
            $synthesizer = $agents[-1]

            Write-Host "  Panel phase: $($panelists.Count) panelists" -ForegroundColor Cyan

            # Fan-out panelists in parallel
            $branches = $panelists | ForEach-Object {
                $resolved = $resolvedAgents[$_.name]
                $branch = @{ Message = $Message }
                if ($resolved.Mode -eq 'agent_reference') {
                    $branch.AgentName = $resolved.Name
                }
                else {
                    $branch.Model = $resolved.Model
                    $instructions = @($resolved.Instructions, $_.role) | Where-Object { $_ } | Join-String -Separator "`n`n"
                    if ($instructions) { $branch.Instructions = $instructions }
                }
                $branch
            }

            $panelistResults = Invoke-AzAIFanOut -Branches $branches
            foreach ($pr in $panelistResults) {
                $agentName = $pr.AgentName ?? 'Unknown'
                $steps.Add([PSCustomObject]@{
                    Agent      = $agentName
                    Role       = 'Panelist'
                    Response   = $pr.Response
                    TokensUsed = $pr.TokensUsed
                    DurationMs = $pr.DurationMs
                    ToolCalls  = $pr.ToolCalls
                })
                Write-Host "    ✓ $agentName" -ForegroundColor Green -NoNewline
                Write-Host " → $($pr.Response.Length) chars" -ForegroundColor DarkGray
            }

            # Synthesis
            $perspectives = ($panelistResults | ForEach-Object {
                $name = $_.AgentName ?? 'Unknown'
                "**$name**:`n$($_.Response)"
            }) -join "`n`n---`n`n"

            $synthPrompt = @"
Multiple agents have independently analyzed this question:

$perspectives

---
Original question: $Message

Please synthesize the best comprehensive answer, combining the strongest insights from each perspective.
"@

            Write-Host "  Synthesis: $($synthesizer.name)" -ForegroundColor Cyan
            $synthResult = Invoke-ResolvedAgent -AgentName $synthesizer.name -Prompt $synthPrompt -RoleHint $synthesizer.role
            $steps.Add($synthResult)
            $finalAnswer = $synthResult.Response

            Write-Host "      → $($synthResult.Response.Length) chars, $($synthResult.DurationMs)ms" -ForegroundColor DarkGray
        }

        'debate' {
            # Debate: proposer → challenger → judge
            $proposer = $agents[0]
            $challenger = $agents[1]
            $judge = $agents[2] ?? $agents[0]

            # Proposer — gets raw message
            Write-Host "  [1/3] $($proposer.name)" -ForegroundColor Cyan -NoNewline
            Write-Host " (Proposer)" -ForegroundColor Gray
            $propResult = Invoke-ResolvedAgent -AgentName $proposer.name -Prompt $Message -RoleHint $proposer.role
            $steps.Add($propResult)
            Write-Host "      → $($propResult.Response.Length) chars, $($propResult.DurationMs)ms" -ForegroundColor DarkGray

            # Challenger — critique prompt
            $challengePrompt = @"
Another agent proposes the following answer:

$($propResult.Response)

---
Original question: $Message

Please critically evaluate this response. Identify weaknesses, gaps, or errors, and provide your counter-argument or improved answer.
"@

            Write-Host "  [2/3] $($challenger.name)" -ForegroundColor Cyan -NoNewline
            Write-Host " (Challenger)" -ForegroundColor Gray
            $challResult = Invoke-ResolvedAgent -AgentName $challenger.name -Prompt $challengePrompt -RoleHint $challenger.role
            $steps.Add($challResult)
            Write-Host "      → $($challResult.Response.Length) chars, $($challResult.DurationMs)ms" -ForegroundColor DarkGray

            # Judge — evaluate both sides
            $judgePrompt = @"
Two agents have debated this question:

**$($proposer.name) (Proposer)**:
$($propResult.Response)

**$($challenger.name) (Challenger)**:
$($challResult.Response)

---
Original question: $Message

As the judge, evaluate both arguments. Determine the best answer, incorporating the strongest points from each side.
"@

            Write-Host "  [3/3] $($judge.name)" -ForegroundColor Cyan -NoNewline
            Write-Host " (Judge)" -ForegroundColor Gray
            $judgeResult = Invoke-ResolvedAgent -AgentName $judge.name -Prompt $judgePrompt -RoleHint $judge.role
            $steps.Add($judgeResult)
            $finalAnswer = $judgeResult.Response
            Write-Host "      → $($judgeResult.Response.Length) chars, $($judgeResult.DurationMs)ms" -ForegroundColor DarkGray
        }

        'debate-rounds' {
            # Multi-round debate with rebuttals
            $proposer = $agents[0]
            $challenger = $agents[1]
            $judge = $agents[2] ?? $agents[0]
            $allRoundsText = ''

            # Round 1: initial positions
            Write-Host "  Round 1/$debateRounds" -ForegroundColor Magenta

            Write-Host "    $($proposer.name)" -ForegroundColor Cyan -NoNewline
            Write-Host " (Proposer)" -ForegroundColor Gray
            $propResult = Invoke-ResolvedAgent -AgentName $proposer.name -Prompt $Message -RoleHint $proposer.role
            $steps.Add($propResult)
            $proposerArgs = $propResult.Response
            Write-Host "      → $($propResult.Response.Length) chars, $($propResult.DurationMs)ms" -ForegroundColor DarkGray

            $challPrompt = @"
Another agent proposes:

$proposerArgs

---
Original question: $Message

Critically evaluate this response. Identify weaknesses, gaps, or errors, and provide your counter-argument.
"@

            Write-Host "    $($challenger.name)" -ForegroundColor Cyan -NoNewline
            Write-Host " (Challenger)" -ForegroundColor Gray
            $challResult = Invoke-ResolvedAgent -AgentName $challenger.name -Prompt $challPrompt -RoleHint $challenger.role
            $steps.Add($challResult)
            $challengerArgs = $challResult.Response
            Write-Host "      → $($challResult.Response.Length) chars, $($challResult.DurationMs)ms" -ForegroundColor DarkGray

            $allRoundsText += "**Round 1 — $($proposer.name) (Proposer)**:`n$proposerArgs`n`n"
            $allRoundsText += "**Round 1 — $($challenger.name) (Challenger)**:`n$challengerArgs`n`n"

            # Rebuttal rounds
            for ($round = 2; $round -le $debateRounds; $round++) {
                Write-Host "  Round $round/$debateRounds" -ForegroundColor Magenta

                # Proposer rebuttal
                $rebutPrompt = @"
You previously argued:

$proposerArgs

The challenger countered:

$challengerArgs

---
Original question: $Message

Strengthen your argument. Address the challenger's points and provide additional evidence or reasoning. Round $round of $debateRounds.
"@

                Write-Host "    $($proposer.name)" -ForegroundColor Cyan -NoNewline
                Write-Host " (Rebuttal)" -ForegroundColor Gray
                $propRebuttal = Invoke-ResolvedAgent -AgentName $proposer.name -Prompt $rebutPrompt -RoleHint $proposer.role
                $steps.Add($propRebuttal)
                $proposerArgs = $propRebuttal.Response
                Write-Host "      → $($propRebuttal.Response.Length) chars, $($propRebuttal.DurationMs)ms" -ForegroundColor DarkGray

                # Challenger rebuttal
                $challRebutPrompt = @"
You previously argued:

$challengerArgs

The proposer countered:

$proposerArgs

---
Original question: $Message

Strengthen your counter-argument. Address the proposer's new points. Round $round of $debateRounds.
"@

                Write-Host "    $($challenger.name)" -ForegroundColor Cyan -NoNewline
                Write-Host " (Rebuttal)" -ForegroundColor Gray
                $challRebuttal = Invoke-ResolvedAgent -AgentName $challenger.name -Prompt $challRebutPrompt -RoleHint $challenger.role
                $steps.Add($challRebuttal)
                $challengerArgs = $challRebuttal.Response
                Write-Host "      → $($challRebuttal.Response.Length) chars, $($challRebuttal.DurationMs)ms" -ForegroundColor DarkGray

                $allRoundsText += "**Round $round — $($proposer.name) (Rebuttal)**:`n$proposerArgs`n`n"
                $allRoundsText += "**Round $round — $($challenger.name) (Rebuttal)**:`n$challengerArgs`n`n"
            }

            # Judge — full debate evaluation
            $judgePrompt = @"
A $debateRounds-round debate on this question:

$allRoundsText

---
Original question: $Message

As the judge, evaluate the full debate. Who made the stronger case? Provide the definitive answer, incorporating the strongest arguments from both sides.
"@

            Write-Host "  Judgment: $($judge.name)" -ForegroundColor Cyan
            $judgeResult = Invoke-ResolvedAgent -AgentName $judge.name -Prompt $judgePrompt -RoleHint $judge.role
            $steps.Add($judgeResult)
            $finalAnswer = $judgeResult.Response
            Write-Host "      → $($judgeResult.Response.Length) chars, $($judgeResult.DurationMs)ms" -ForegroundColor DarkGray
        }

        'pipeline' {
            # Pipeline: router → specialists → synthesis
            $phases = $doc.phases
            if (-not $phases -or $phases.Count -eq 0) {
                # No phases defined — fall back to simple pipeline:
                # first agent = router, middle = specialists, last = synthesizer
                $router = $agents[0]
                $specialists = $agents[1..($agents.Count - 2)]
                $synthesizer = $agents[-1]

                # Router
                $specialistList = ($specialists | ForEach-Object {
                    "- $($_.name): $($_.role ?? $_.domain ?? 'specialist')"
                }) -join "`n"

                $routingPrompt = @"
Analyze this scenario and decide which specialist agents should be consulted.

SCENARIO:
$Message

AVAILABLE SPECIALIST AGENTS:
$specialistList

Respond with a JSON object listing which agents to invoke:
{
  "agentsToInvoke": [
    { "agentId": "agent-name", "reason": "why this agent is needed" }
  ],
  "initialHypothesis": "Your initial assessment of the situation"
}

You may invoke all, some, or none of the specialists depending on relevance.
"@

                Write-Host "  [Route] $($router.name)" -ForegroundColor Cyan
                $routeResult = Invoke-ResolvedAgent -AgentName $router.name -Prompt $routingPrompt -RoleHint $router.role
                $steps.Add($routeResult)
                Write-Host "      → $($routeResult.Response.Length) chars, $($routeResult.DurationMs)ms" -ForegroundColor DarkGray

                # Parse routing decision
                $hypothesis = ''
                $selectedSpecialists = $specialists
                try {
                    $jsonMatch = [regex]::Match($routeResult.Response, '\{[\s\S]*\}')
                    if ($jsonMatch.Success) {
                        $routing = $jsonMatch.Value | ConvertFrom-Json
                        $hypothesis = $routing.initialHypothesis
                        if ($routing.agentsToInvoke) {
                            $selectedNames = @($routing.agentsToInvoke | ForEach-Object { $_.agentId })
                            $selectedSpecialists = $specialists | Where-Object { $_.name -in $selectedNames }
                            if ($selectedSpecialists.Count -eq 0) { $selectedSpecialists = $specialists }
                        }
                    }
                }
                catch {
                    Write-Verbose "Could not parse routing JSON, invoking all specialists"
                }

                # Specialists (parallel)
                Write-Host "  [Investigate] $($selectedSpecialists.Count) specialists" -ForegroundColor Cyan
                $specPrompt = if ($hypothesis) {
                    "$Message`n`nInitial assessment from the routing agent: $hypothesis"
                }
                else { $Message }

                $specBranches = $selectedSpecialists | ForEach-Object {
                    $resolved = $resolvedAgents[$_.name]
                    $branch = @{ Message = $specPrompt }
                    if ($resolved.Mode -eq 'agent_reference') {
                        $branch.AgentName = $resolved.Name
                    }
                    else {
                        $branch.Model = $resolved.Model
                        $instructions = @($resolved.Instructions, $_.role) | Where-Object { $_ } | Join-String -Separator "`n`n"
                        if ($instructions) { $branch.Instructions = $instructions }
                    }
                    $branch
                }

                $specResults = Invoke-AzAIFanOut -Branches $specBranches
                foreach ($sr in $specResults) {
                    $agentName = $sr.AgentName ?? 'Unknown'
                    $steps.Add([PSCustomObject]@{
                        Agent      = $agentName
                        Role       = 'Specialist'
                        Response   = $sr.Response
                        TokensUsed = $sr.TokensUsed
                        DurationMs = $sr.DurationMs
                        ToolCalls  = $sr.ToolCalls
                    })
                    Write-Host "    ✓ $agentName → $($sr.Response.Length) chars" -ForegroundColor Green
                }

                # Synthesizer
                $evidence = ($specResults | ForEach-Object {
                    $name = $_.AgentName ?? 'Unknown'
                    "**$name**:`n$($_.Response)"
                }) -join "`n`n---`n`n"

                $synthPrompt = @"
You analyzed this scenario and routed to $($specResults.Count) specialist agents.

Your initial analysis:
$($routeResult.Response)

The following specialist agents provided their findings:

$evidence

---
Original scenario: $Message

Based on ALL gathered evidence, provide a comprehensive synthesis combining the strongest findings from each specialist. Be explicit about confidence levels and identify any remaining unknowns.
"@

                Write-Host "  [Synthesize] $($synthesizer.name)" -ForegroundColor Cyan
                $synthResult = Invoke-ResolvedAgent -AgentName $synthesizer.name -Prompt $synthPrompt -RoleHint $synthesizer.role
                $steps.Add($synthResult)
                $finalAnswer = $synthResult.Response
                Write-Host "      → $($synthResult.Response.Length) chars, $($synthResult.DurationMs)ms" -ForegroundColor DarkGray
            }
            else {
                # Custom pipeline with phases
                $phaseContext = ''
                for ($p = 0; $p -lt $phases.Count; $p++) {
                    $phase = $phases[$p]
                    $phaseNum = $p + 1
                    $phaseMode = $phase.mode ?? 'parallel'
                    $phaseAgentNames = @($phase.agents)

                    Write-Host "  Phase $phaseNum: $($phase.name)" -ForegroundColor Magenta -NoNewline
                    Write-Host " ($phaseMode)" -ForegroundColor Gray

                    $contextPrefix = if ($phaseContext) {
                        "Previous phase output:`n$phaseContext`n`n---`nOriginal scenario: $Message"
                    }
                    else { $Message }

                    switch ($phaseMode) {
                        'parallel' {
                            $pBranches = $phaseAgentNames | ForEach-Object {
                                $agentName = $_
                                $resolved = $resolvedAgents[$agentName]
                                $branch = @{ Message = $contextPrefix }
                                if ($resolved.Mode -eq 'agent_reference') {
                                    $branch.AgentName = $resolved.Name
                                }
                                else {
                                    $branch.Model = $resolved.Model
                                    $inst = @($resolved.Instructions, $phase.roleHint) | Where-Object { $_ } | Join-String -Separator "`n`n"
                                    if ($inst) { $branch.Instructions = $inst }
                                }
                                $branch
                            }

                            $phaseResults = Invoke-AzAIFanOut -Branches $pBranches
                            foreach ($pr in $phaseResults) {
                                $aName = $pr.AgentName ?? 'Unknown'
                                $steps.Add([PSCustomObject]@{
                                    Agent = $aName; Role = $phase.name; Response = $pr.Response
                                    TokensUsed = $pr.TokensUsed; DurationMs = $pr.DurationMs; ToolCalls = $pr.ToolCalls
                                })
                                Write-Host "    ✓ $aName → $($pr.Response.Length) chars" -ForegroundColor Green
                            }
                            $phaseContext = ($phaseResults | ForEach-Object {
                                "$($_.AgentName ?? 'Unknown'): $($_.Response)"
                            }) -join "`n`n"
                        }

                        'sequential' {
                            $chainCtx = $contextPrefix
                            foreach ($agentName in $phaseAgentNames) {
                                Write-Host "    → $agentName" -ForegroundColor Cyan
                                $result = Invoke-ResolvedAgent -AgentName $agentName -Prompt $chainCtx -RoleHint $phase.roleHint
                                $steps.Add($result)
                                $chainCtx = "$contextPrefix`n`nPrevious agent ($agentName) output:`n$($result.Response)"
                                Write-Host "      $($result.Response.Length) chars, $($result.DurationMs)ms" -ForegroundColor DarkGray
                            }
                            $phaseContext = ($steps | Select-Object -Last $phaseAgentNames.Count | ForEach-Object {
                                "$($_.Agent): $($_.Response)"
                            }) -join "`n`n"
                        }

                        'single' {
                            $agentName = $phaseAgentNames[0]
                            Write-Host "    → $agentName" -ForegroundColor Cyan
                            $result = Invoke-ResolvedAgent -AgentName $agentName -Prompt $contextPrefix -RoleHint $phase.roleHint
                            $steps.Add($result)
                            $phaseContext = $result.Response
                            Write-Host "      $($result.Response.Length) chars, $($result.DurationMs)ms" -ForegroundColor DarkGray
                        }

                        'routed' {
                            $routerName = $phase.routerAgent ?? $phaseAgentNames[0]
                            $candidates = $phaseAgentNames | Where-Object { $_ -ne $routerName }

                            $routePrompt = @"
You are a routing agent for phase "$($phase.name)". Given the scenario below, decide which specialist agents should be invoked.

Available agents:
$($candidates | ForEach-Object { "- $_" } | Out-String)

Scenario:
$contextPrefix

Respond with JSON: { "agentsToInvoke": [{ "agentId": "...", "reason": "..." }], "hypothesis": "...", "skipReason": "..." }
"@

                            Write-Host "    [Route] $routerName" -ForegroundColor Cyan
                            $routeResult = Invoke-ResolvedAgent -AgentName $routerName -Prompt $routePrompt -RoleHint $phase.roleHint
                            $steps.Add($routeResult)

                            $selectedCandidates = $candidates
                            try {
                                $jm = [regex]::Match($routeResult.Response, '\{[\s\S]*\}')
                                if ($jm.Success) {
                                    $rd = $jm.Value | ConvertFrom-Json
                                    if ($rd.agentsToInvoke) {
                                        $sn = @($rd.agentsToInvoke | ForEach-Object { $_.agentId })
                                        $filtered = $candidates | Where-Object { $_ -in $sn }
                                        if ($filtered.Count -gt 0) { $selectedCandidates = $filtered }
                                    }
                                }
                            }
                            catch { Write-Verbose "Could not parse routing, invoking all candidates" }

                            $rBranches = $selectedCandidates | ForEach-Object {
                                $aName = $_
                                $resolved = $resolvedAgents[$aName]
                                $branch = @{ Message = $contextPrefix }
                                if ($resolved.Mode -eq 'agent_reference') { $branch.AgentName = $resolved.Name }
                                else {
                                    $branch.Model = $resolved.Model
                                    if ($resolved.Instructions) { $branch.Instructions = $resolved.Instructions }
                                }
                                $branch
                            }

                            $rResults = Invoke-AzAIFanOut -Branches $rBranches
                            foreach ($rr in $rResults) {
                                $aName = $rr.AgentName ?? 'Unknown'
                                $steps.Add([PSCustomObject]@{
                                    Agent = $aName; Role = $phase.name; Response = $rr.Response
                                    TokensUsed = $rr.TokensUsed; DurationMs = $rr.DurationMs; ToolCalls = $rr.ToolCalls
                                })
                                Write-Host "    ✓ $aName → $($rr.Response.Length) chars" -ForegroundColor Green
                            }
                            $phaseContext = ($rResults | ForEach-Object {
                                "$($_.AgentName ?? 'Unknown'): $($_.Response)"
                            }) -join "`n`n"
                        }
                    }
                }
                $finalAnswer = $phaseContext
            }
        }
    }

    # ── Results ───────────────────────────────────────────────
    $totalElapsed = ((Get-Date) - $totalStart).TotalMilliseconds
    $totalTokens = ($steps | ForEach-Object { $_.TokensUsed.TotalTokens } | Measure-Object -Sum).Sum

    Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "  Execution Complete" -ForegroundColor Green
    Write-Host "  Steps:     $($steps.Count)" -ForegroundColor White
    Write-Host "  Tokens:    $totalTokens" -ForegroundColor White
    Write-Host "  Duration:  $([int]$totalElapsed)ms ($([math]::Round($totalElapsed/1000, 1))s)" -ForegroundColor White
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Cyan

    return [PSCustomObject]@{
        PSTypeName    = 'AzAITopologyResult'
        Topology      = $topologyType
        Name          = $doc.metadata.name
        Steps         = $steps.ToArray()
        FinalAnswer   = $finalAnswer
        TotalTokens   = $totalTokens
        TotalDuration = [int]$totalElapsed
        AgentCount    = $agents.Count
        StepCount     = $steps.Count
        Source        = $TopologyFile
    }
}
