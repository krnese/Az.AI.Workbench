# Az.AI.Workbench

Application-layer multi-agent orchestration for Azure AI Foundry — from PowerShell.

## What it does

This module provides cmdlets for invoking AI agents via the Azure AI Foundry Responses API. It supports agent switching on shared conversations, parallel fan-out to specialists, and result synthesis — the orchestration patterns validated in the Microsoft AI Workbench.

**Two connection modes:**
- **Foundry Direct** — talk directly to the Responses API using Entra ID (your Azure identity)
- **AI Workbench** — route through an AI Workbench instance (uses `/api/invoke`)

**Two execution modes:**
- **Agent Reference** (`-AgentName`) — invoke a named agent deployed in your Foundry project
- **Direct Mode** (`-Model`) — specify the model deployment, instructions, and tools per-request (no pre-configured agent needed)

## Installation

```powershell
Install-Module Az.AI.Workbench
```

## Quick Start

### Connect with Entra ID (recommended)

```powershell
Import-Module Az.AI.Workbench

# Authenticate with your Azure identity — no API keys needed
Connect-AzAIFoundry -Endpoint "https://ais-myproject.services.ai.azure.com" `
                     -Project "my-project"
```

### Or connect via AI Workbench

```powershell
Connect-AzAIFoundry -WorkbenchUrl "https://my-workbench.azurewebsites.net"
```

### Invoke an agent (Agent Reference mode)

```powershell
# Use a named agent deployed in your Foundry project
$resp = Invoke-AzAIAgent -AgentName "MyAgent" -Message "What is Azure RBAC?"
$resp.Response
```

### Invoke directly (Direct Mode)

```powershell
# No pre-configured agent needed — specify model + instructions per-request
$resp = Invoke-AzAIAgent -Model "gpt-5-mini" `
                          -Instructions "You are an Azure cloud architect." `
                          -Message "What is Azure RBAC?"
$resp.Response
```

## Cmdlets

| Cmdlet | Description |
|--------|-------------|
| `Connect-AzAIFoundry` | Establish connection to Foundry (Entra ID) or AI Workbench |
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

# Turn 1: Agent reference
Invoke-AzAIAgent -Conversation $conv -AgentName "ResearchAgent" -Message "Explain RBAC"

# Turn 2: Switch to a different agent — it sees everything from Turn 1
Invoke-AzAIAgent -Conversation $conv -AgentName "WriterAgent" -Message "Draft a summary of the above"

# Turn 3: Switch to direct mode on the same conversation
Invoke-AzAIAgent -Conversation $conv -Model "gpt-5-mini" `
                  -Instructions "You are an executive summarizer." `
                  -Message "Summarize this conversation in 3 bullet points"
```

### Isolated Fan-Out + Synthesis

Separate conversations per branch, parallel execution, explicit synthesis.

```powershell
$conv = New-AzAIConversation
$triage = Invoke-AzAIAgent -Conversation $conv -Model "gpt-5-mini" `
            -Instructions "You are a triage specialist." `
            -Message "User can't access resource group"

# Fan-out: each branch gets its own isolated conversation
$results = Invoke-AzAIFanOut -Branches @(
    @{ AgentName = "DocsAgent";     Message = "RBAC troubleshooting steps" }
    @{ AgentName = "IncidentAgent"; Message = "Known issues with RBAC" }
)

# Synthesize back on the shared conversation
$resolution = Invoke-AzAISynthesize -Conversation $conv -Model "gpt-5-mini" `
                -BranchResults $results `
                -Prompt "Identify root cause and recommend actions"
```

### Direct Mode Fan-Out (no pre-configured agents needed)

```powershell
# Fan-out using direct mode — different instructions per branch, same model
$results = Invoke-AzAIFanOut -Branches @(
    @{
        Model        = "gpt-5-mini"
        Instructions = "You are a documentation expert."
        Message      = "RBAC troubleshooting steps"
    }
    @{
        Model        = "gpt-5-mini"
        Instructions = "You are an incident analyst."
        Message      = "Known issues with RBAC"
    }
)
```

### Direct Mode — Runtime Composition

```powershell
# Compose model, instructions, and tools per-request
Invoke-AzAIAgent -Model "gpt-5-mini" `
                  -Instructions "You are a security analyst. Be concise." `
                  -Tools @("https://my-mcp-server/mcp") `
                  -Message "Analyze these access logs"
```

## Authentication

The module uses Entra ID by default via the `Az.Accounts` module:

```powershell
# Ensure you're logged in
Connect-AzAccount

# Connect to your Foundry project — token is acquired automatically
Connect-AzAIFoundry -Endpoint "https://ais-myproject.services.ai.azure.com" -Project "my-project"
```

The token audience is `https://ai.azure.com`. No API keys are required.

## Requirements

- PowerShell 7.0+
- Azure AI Foundry project with a `.services.ai.azure.com` endpoint
- `Az.Accounts` module for Entra ID authentication (`Install-Module Az.Accounts`)
- Optional: AI Workbench instance for `/api/invoke` routing

## License

MIT
