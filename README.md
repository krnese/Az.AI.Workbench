# Az.AI.Workbench

Application-layer multi-agent orchestration for Azure AI Foundry — from PowerShell.

## What it does

This module provides cmdlets for invoking AI agents via the Azure AI Foundry Responses API. It supports agent switching on shared conversations, parallel fan-out to specialists, and result synthesis — the orchestration patterns validated in the Microsoft AI Workbench.

**Two connection modes:**
- **Foundry Direct** — talk directly to the Responses API with endpoint + API key or Az token
- **AI Workbench** — route through an AI Workbench instance (uses `/api/invoke`)

**Two execution modes:**
- **Agent Reference** (`-AgentName`) — point to a named agent definition in Foundry
- **Direct Mode** (`-Model`) — send model, instructions, and tools per-request

## Installation

```powershell
Install-Module Az.AI.Workbench
```

## Quick Start

```powershell
Import-Module Az.AI.Workbench

# Connect to Foundry
Connect-AzAIFoundry -Endpoint "https://ais-myproject.services.ai.azure.com" `
                     -Project "my-project" -ApiKey $env:FOUNDRY_API_KEY

# Or connect via AI Workbench
Connect-AzAIFoundry -WorkbenchUrl "https://my-workbench.azurewebsites.net"

# Invoke an agent
$resp = Invoke-AzAIAgent -AgentName "MSLearn" -Message "What is Azure RBAC?"
$resp.Response
```

## Cmdlets

| Cmdlet | Description |
|--------|-------------|
| `Connect-AzAIFoundry` | Establish connection to Foundry or AI Workbench |
| `New-AzAIConversation` | Create a new conversation |
| `Invoke-AzAIAgent` | Invoke an agent (agent reference or direct mode) |
| `Invoke-AzAIFanOut` | Parallel fan-out to multiple agents on isolated conversations |
| `Invoke-AzAISynthesize` | Synthesize branch results on a shared conversation |
| `Get-AzAIAgent` | List available agents |
| `Import-AzAIManifest` | Load agent definitions from local YAML manifests |

## Orchestration Patterns

### Shared-Conversation Sequential Handoff

Multiple agents take turns on one conversation. Each sees the full history.

```powershell
$conv = New-AzAIConversation
Invoke-AzAIAgent -Conversation $conv -AgentName "MSLearn"    -Message "Explain RBAC"
Invoke-AzAIAgent -Conversation $conv -AgentName "CaseAgent"  -Message "Create a case for this"
# CaseAgent sees everything MSLearn said — no context copying needed
```

### Isolated Fan-Out + Synthesis

Separate conversations per agent, parallel execution, explicit synthesis.

```powershell
$conv = New-AzAIConversation
$triage = Invoke-AzAIAgent -Conversation $conv -AgentName "CaseAgent" `
            -Message "User can't access resource group"

$results = @("MSLearn", "MSSupport") | Invoke-AzAIFanOut -Message $triage.Response

$resolution = Invoke-AzAISynthesize -Conversation $conv -AgentName "CaseAgent" `
                -BranchResults $results `
                -Prompt "Identify root cause and recommend actions"
$resolution | Format-Table AgentName, Response
```

### Direct Mode — Runtime Composition

```powershell
Invoke-AzAIAgent -Model "gpt-5-mini" `
                  -Instructions "You are a security analyst. Be concise." `
                  -Tools @("https://my-mcp-server/mcp") `
                  -Message "Analyze these access logs"
```

## Requirements

- PowerShell 7.0+
- Azure AI Foundry project (endpoint + API key or `Az.Accounts` for token auth)
- Optional: AI Workbench instance for `/api/invoke` routing

## License

MIT
