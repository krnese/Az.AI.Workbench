#Requires -Version 7.0

<#
.SYNOPSIS
    Az.AI.Workbench — Application-layer multi-agent orchestration for Azure AI Foundry.

.DESCRIPTION
    This module provides cmdlets for invoking AI agents via the Azure AI Foundry
    Responses API, switching agents mid-conversation, fanning out to parallel
    specialists, and synthesizing results.

    Supports two connection modes:
    - Foundry Direct: talk to the Responses API with endpoint + API key or Az token
    - AI Workbench: talk via an AI Workbench instance (uses /api/invoke)

    Supports two execution modes:
    - Agent Reference: point to a named agent definition in Foundry (-AgentName)
    - Direct Mode: send model + instructions + tools per-request (-Model)
#>

# Module-scoped connection state
$script:Connection = $null

# Dot-source all public and private functions
$PublicFunctions = @(Get-ChildItem -Path "$PSScriptRoot/Public/*.ps1" -ErrorAction SilentlyContinue)
$PrivateFunctions = @(Get-ChildItem -Path "$PSScriptRoot/Private/*.ps1" -ErrorAction SilentlyContinue)

foreach ($file in @($PrivateFunctions + $PublicFunctions)) {
    try {
        . $file.FullName
        Write-Verbose "Loaded: $($file.Name)"
    }
    catch {
        Write-Error "Failed to load $($file.FullName): $_"
    }
}

# Export public functions
Export-ModuleMember -Function $PublicFunctions.BaseName
