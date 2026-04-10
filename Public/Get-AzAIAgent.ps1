function Get-AzAIAgent {
    <#
    .SYNOPSIS
        Lists available agents from the connected Foundry project or AI Workbench instance.

    .EXAMPLE
        Get-AzAIAgent

    .EXAMPLE
        Get-AzAIAgent -Name "MSLearn"

    .EXAMPLE
        Get-AzAIAgent | Format-Table Name, Mode, Description
    #>
    [CmdletBinding()]
    param(
        [string]$Name
    )

    $conn = $script:Connection
    if (-not $conn) {
        throw 'Not connected. Run Connect-AzAIFoundry first.'
    }

    if ($conn.Mode -eq 'Workbench') {
        $path = if ($Name) { "/api/manifests/$Name" } else { '/api/manifests' }
        $result = Send-FoundryRequest -Method GET -Path $path

        if ($Name) {
            return [PSCustomObject]@{
                PSTypeName    = 'AzAIAgent'
                Name          = $result.name
                Id            = $result.id
                Description   = $result.description
                Mode          = $result.executionMode
                Tools         = $result.tools
                Model         = $result.model
                ApprovalPolicy = $result.approvalPolicy
            }
        }

        $manifests = $result.manifests ?? $result
        if ($manifests -is [array]) {
            return $manifests | ForEach-Object {
                $ident = $_.identity
                $rt = $_.runtime
                [PSCustomObject]@{
                    PSTypeName     = 'AzAIAgent'
                    Name           = $ident.name
                    Id             = $ident.id
                    Description    = ($ident.description -replace '\s+', ' ').Trim().Substring(0, [Math]::Min(80, ($ident.description -replace '\s+', ' ').Trim().Length))
                    Mode           = $rt.executionMode
                    ApprovalPolicy = $rt.approvalPolicy
                    Tools          = ($_.tools | ForEach-Object { $_.name }) -join ', '
                    Model          = $rt.defaultModel
                }
            }
        }
    }
    else {
        # Foundry Direct — list agents via Agents API
        $result = Send-FoundryRequest -Method GET -Path '/openai/agents'

        $agents = $result.data ?? $result
        $filtered = if ($Name) {
            $agents | Where-Object { $_.name -eq $Name -or $_.id -eq $Name }
        } else { $agents }

        return $filtered | ForEach-Object {
            [PSCustomObject]@{
                PSTypeName  = 'AzAIAgent'
                Name        = $_.name
                Id          = $_.id
                Description = $_.description
                Mode        = 'agent_reference'
                Model       = $_.model
            }
        }
    }
}
