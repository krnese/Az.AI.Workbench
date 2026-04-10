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

        # Execute in parallel
        $results = $branchList | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
            # Import module in parallel runspace
            $modulePath = $using:PSScriptRoot
            Import-Module "$modulePath/../Az.AI.Workbench.psd1" -Force

            # Re-establish connection in parallel runspace
            $conn = $using:script:Connection
            $script:Connection = $conn

            $branch = $_
            $params = @{
                Message = $branch.Message
            }

            if ($branch.AgentName) {
                $params.AgentName = $branch.AgentName
            }
            elseif ($branch.Model) {
                $params.Model = $branch.Model
                if ($branch.Instructions) { $params.Instructions = $branch.Instructions }
                if ($branch.Tools) { $params.Tools = $branch.Tools }
            }

            $maxTokens = $using:MaxOutputTokens
            $temp = $using:Temperature
            if ($maxTokens -gt 0) { $params.MaxOutputTokens = $maxTokens }
            if ($null -ne $temp) { $params.Temperature = $temp }

            try {
                $result = Invoke-AzAIAgent @params
                $result | Add-Member -NotePropertyName 'BranchStatus' -NotePropertyValue 'Success'
                $result
            }
            catch {
                [PSCustomObject]@{
                    PSTypeName     = 'AzAIAgentResponse'
                    AgentName      = $branch.AgentName ?? $branch.Model
                    Response       = "Error: $_"
                    BranchStatus   = 'Failed'
                    ConversationId = $null
                    ToolCalls      = @()
                    DurationMs     = 0
                }
            }
        }

        Write-Verbose "Fan-out complete: $($results.Count) results"
        return $results
    }
}
