function Invoke-AzAIFanOut {
    <#
    .SYNOPSIS
        Invokes multiple agents in parallel on isolated conversations (fan-out pattern).

    .DESCRIPTION
        Each agent gets its own conversation seeded with the provided message.
        Agents work independently — they do not see each other's outputs.
        Results are collected and returned as an array.

        Use Invoke-AzAISynthesize to combine the results on a shared conversation.

    .EXAMPLE
        # Fan-out to 3 specialists
        $results = @("MSLearn", "MSSupport", "CaseAgent") | Invoke-AzAIFanOut -Message "Analyze RBAC issue"

    .EXAMPLE
        # Fan-out with per-agent prompts
        $branches = @(
            @{ AgentName = "MSLearn";    Message = "Search docs for RBAC configuration" }
            @{ AgentName = "MSSupport";  Message = "Known issues with RBAC in last 30 days" }
            @{ AgentName = "CaseAgent";  Message = "Similar cases for RBAC failures" }
        )
        $results = Invoke-AzAIFanOut -Branches $branches

    .EXAMPLE
        # Fan-out with direct mode agents
        $branches = @(
            @{ Model = "gpt-5-mini"; Instructions = "Summarize briefly"; Message = "What is RBAC?" }
            @{ Model = "gpt-5-mini"; Instructions = "Explain in detail";  Message = "What is RBAC?" }
        )
        $results = Invoke-AzAIFanOut -Branches $branches
    #>
    [CmdletBinding(DefaultParameterSetName = 'PipelineInput')]
    param(
        [Parameter(ValueFromPipeline, ParameterSetName = 'PipelineInput')]
        [string]$AgentName,

        [Parameter(ParameterSetName = 'PipelineInput')]
        [string]$Message,

        [Parameter(Mandatory, ParameterSetName = 'BranchList')]
        [hashtable[]]$Branches,

        [int]$MaxOutputTokens,

        [double]$Temperature,

        [int]$ThrottleLimit = 5
    )

    begin {
        $pipelineAgents = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($AgentName) {
            $pipelineAgents.Add($AgentName)
        }
    }

    end {
        # Build branch list from pipeline input or -Branches parameter
        if ($pipelineAgents.Count -gt 0) {
            if (-not $Message) {
                throw 'When piping agent names, -Message is required.'
            }
            $branchList = $pipelineAgents | ForEach-Object {
                @{ AgentName = $_; Message = $Message }
            }
        }
        elseif ($Branches) {
            $branchList = $Branches
        }
        else {
            throw 'Provide agent names via pipeline or use -Branches parameter.'
        }

        Write-Verbose "Fan-out: $($branchList.Count) branches (throttle: $ThrottleLimit)"

        # Capture connection for parallel runspaces
        $connData = $script:Connection
        $modulePath = $PSScriptRoot

        # Execute in parallel using thread jobs for proper isolation
        $jobs = foreach ($branch in $branchList) {
            Start-ThreadJob -ScriptBlock {
                param($Branch, $ConnData, $ModulePath, $MaxTok, $Temp)

                # Load module and restore connection in this runspace
                Import-Module "$ModulePath/../Az.AI.Workbench.psd1" -Force
                & (Get-Module Az.AI.Workbench) { $script:Connection = $args[0] } $ConnData

                $params = @{ Message = $Branch.Message }
                if ($Branch.AgentName) { $params.AgentName = $Branch.AgentName }
                elseif ($Branch.Model) {
                    $params.Model = $Branch.Model
                    if ($Branch.Instructions) { $params.Instructions = $Branch.Instructions }
                    if ($Branch.Tools) { $params.Tools = $Branch.Tools }
                }
                if ($MaxTok -gt 0) { $params.MaxOutputTokens = $MaxTok }

                try {
                    $result = Invoke-AzAIAgent @params
                    $result | Add-Member -NotePropertyName 'BranchStatus' -NotePropertyValue 'Success' -PassThru
                }
                catch {
                    [PSCustomObject]@{
                        PSTypeName     = 'AzAIAgentResponse'
                        AgentName      = $Branch.AgentName ?? $Branch.Model
                        Response       = "Error: $_"
                        BranchStatus   = 'Failed'
                        ConversationId = $null
                        ToolCalls      = @()
                        DurationMs     = 0
                    }
                }
            } -ArgumentList $branch, $connData, $modulePath, $MaxOutputTokens, $Temperature -ThrottleLimit $ThrottleLimit
        }

        # Wait for all jobs and collect results
        $results = $jobs | Wait-Job | Receive-Job
        $jobs | Remove-Job -Force

        Write-Verbose "Fan-out complete: $($results.Count) results"
        return $results
    }
}
