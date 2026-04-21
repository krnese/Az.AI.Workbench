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
| `Invoke-AzAITopology` | Execute a topology YAML with role-aware prompt injection |
| `Invoke-AzAIFanOut` | Parallel fan-out to multiple agents on isolated conversations |
| `Invoke-AzAISynthesize` | Synthesize branch results on a shared conversation |
| `Get-AzAIAgent` | List available agents |
| `Import-AzAIManifest` | Load agent definitions from local YAML manifests |

## Orchestration Patterns

### Topology-as-Code (Design → Validate → Export → Automate)

The flagship pattern: execute topology YAML files exported from AI Workbench. The PowerShell module applies the **same role-aware prompt injection** as the Workbench backend — agents receive position-specific instructions based on their role in the topology.

```powershell
# Execute a topology YAML — chain, panel, debate, debate-rounds, or pipeline
$result = Invoke-AzAITopology -TopologyFile ./my-topology.yaml -Message "Analyze this issue"

# Use the sample prompt embedded in the YAML
$result = Invoke-AzAITopology -TopologyFile ./support-investigation.yaml

# Access structured results
$result.FinalAnswer       # The synthesized output
$result.Steps             # Per-agent breakdown (agent, role, response, tokens, duration)
$result.TotalTokens       # Total token consumption
$result.TotalDuration     # End-to-end execution time (ms)
```

**How prompt injection works by topology:**

| Topology | Agent 1 | Agent 2 | Agent 3 |
|----------|---------|---------|---------|
| **Chain** | Raw input | "Build on previous analysis" | "Synthesize final answer" |
| **Panel** | Raw input (parallel) | Raw input (parallel) | "Combine strongest insights" |
| **Debate** | Raw input (proposer) | "Critically evaluate" (challenger) | "Evaluate both sides" (judge) |
| **Debate-Rounds** | Rebuttal prompts per round | Counter-arguments per round | Full debate judgment |
| **Pipeline** | Routing prompt (JSON) | Input + hypothesis (specialists) | Evidence synthesis |

**The workflow:**
1. **Design** topologies in AI Workbench UI
2. **Validate** with assessment (quality, cost, latency, safety)
3. **Export** as YAML — version-controlled, portable
4. **Automate** with `Invoke-AzAITopology` in CI/CD, scripts, or production

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
