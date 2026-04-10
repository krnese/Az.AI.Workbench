@{
    RootModule        = 'Az.AI.Workbench.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'a3f2c8e1-7b4d-4f9a-8e6c-2d1b0a5f3e7c'
    Author            = 'Kristian Nese'
    CompanyName       = 'Microsoft'
    Copyright         = '(c) 2026 Microsoft. All rights reserved.'
    Description       = 'Application-layer multi-agent orchestration for Azure AI Foundry. Invoke agents, switch between them on shared conversations, fan-out to parallel specialists, and synthesize results — all from PowerShell.'
    PowerShellVersion = '7.0'

    RequiredModules   = @('Az.Accounts')

    # Functions to export
    FunctionsToExport = @(
        'Connect-AzAIFoundry',
        'New-AzAIConversation',
        'Invoke-AzAIAgent',
        'Invoke-AzAIFanOut',
        'Invoke-AzAISynthesize',
        'Get-AzAIAgent',
        'Import-AzAIManifest'
    )

    CmdletsToExport   = @()
    VariablesToExport  = @()
    AliasesToExport    = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('Azure', 'AI', 'Foundry', 'Agent', 'Orchestration', 'MCP', 'LLM')
            LicenseUri   = 'https://github.com/krnese/Az.AI.Workbench/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/krnese/Az.AI.Workbench'
            ReleaseNotes = 'v1.0.0 — Connect-AzAIFoundry (Entra ID + Workbench), Invoke-AzAIAgent (agent reference + direct mode), fan-out, synthesis, agent listing. Full Azure AI Foundry Responses API support.'
        }
    }
}
