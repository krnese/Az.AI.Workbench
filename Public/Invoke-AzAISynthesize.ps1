function Invoke-AzAISynthesize {
    <#
    .SYNOPSIS
        Synthesizes results from multiple agents on a shared conversation.

    .DESCRIPTION
        Takes branch results from Invoke-AzAIFanOut and feeds them as context to a
        synthesis agent on a shared conversation. The synthesis agent sees the full
        conversation history plus all branch outputs.

    .EXAMPLE
        $conv = New-AzAIConversation
        $triage = Invoke-AzAIAgent -Conversation $conv -AgentName "CaseAgent" -Message "User can't access RG"
        $results = @("MSLearn", "MSSupport") | Invoke-AzAIFanOut -Message $triage.Response
        $synthesis = Invoke-AzAISynthesize -Conversation $conv -AgentName "CaseAgent" -BranchResults $results

    .EXAMPLE
        # Custom synthesis prompt
        Invoke-AzAISynthesize -Conversation $conv -AgentName "CaseAgent" -BranchResults $results `
            -Prompt "Compare findings, identify consensus, and recommend top 3 actions"
    #>
    [CmdletBinding(DefaultParameterSetName = 'AgentReference')]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Conversation,

        [Parameter(Mandatory, ParameterSetName = 'AgentReference')]
        [string]$AgentName,

        [Parameter(Mandatory, ParameterSetName = 'DirectMode')]
        [string]$Model,

        [Parameter(ParameterSetName = 'DirectMode')]
        [string]$Instructions,

        [Parameter(Mandatory)]
        [PSCustomObject[]]$BranchResults,

        [string]$Prompt = 'Synthesize the specialist outputs below into: key findings, confidence level, recommended actions, and any conflicts between sources.',

        [int]$MaxOutputTokens
    )

    # Compose synthesis message from branch results
    $branchText = ($BranchResults | ForEach-Object {
        $agent = $_.AgentName ?? 'Unknown'
        $status = $_.BranchStatus ?? 'Success'
        $response = if ($status -eq 'Failed') { "(failed: $($_.Response))" } else { $_.Response }
        "[$agent] ($status):`n$response"
    }) -join "`n`n---`n`n"

    $synthesisMessage = @"
Specialist agents provided the following evidence:

$branchText

---

$Prompt
"@

    Write-Verbose "Synthesis message: $($synthesisMessage.Length) chars from $($BranchResults.Count) branches"

    # Invoke on the shared conversation
    $params = @{
        Conversation = $Conversation
        Message      = $synthesisMessage
    }

    if ($AgentName) {
        $params.AgentName = $AgentName
    }
    else {
        $params.Model = $Model
        if ($Instructions) { $params.Instructions = $Instructions }
    }

    if ($MaxOutputTokens -gt 0) { $params.MaxOutputTokens = $MaxOutputTokens }

    $result = Invoke-AzAIAgent @params
    $result | Add-Member -NotePropertyName 'SynthesizedFrom' -NotePropertyValue @($BranchResults.AgentName)
    return $result
}
