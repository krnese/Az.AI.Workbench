function Import-AzAIManifest {
    <#
    .SYNOPSIS
        Loads agent definitions from local YAML manifest files.

    .DESCRIPTION
        Reads YAML manifests from a directory and returns agent configuration objects.
        These can be used to understand agent configurations locally without a server connection.
        Requires the powershell-yaml module for YAML parsing.

    .EXAMPLE
        $agents = Import-AzAIManifest -Path "./manifests/"
        $agents["MyAgent"]

    .EXAMPLE
        Import-AzAIManifest -Path "./manifests/" | Format-Table Name, Mode, Tools
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Get-Module -ListAvailable -Name 'powershell-yaml')) {
        throw 'The powershell-yaml module is required. Install with: Install-Module powershell-yaml -Scope CurrentUser'
    }

    Import-Module powershell-yaml -ErrorAction Stop

    $manifestFiles = Get-ChildItem -Path $Path -Filter '*.yaml' -Recurse -ErrorAction Stop
    if ($manifestFiles.Count -eq 0) {
        $manifestFiles = Get-ChildItem -Path $Path -Filter '*.yml' -Recurse -ErrorAction Stop
    }

    if ($manifestFiles.Count -eq 0) {
        Write-Warning "No YAML files found in $Path"
        return @{}
    }

    $agents = @{}

    foreach ($file in $manifestFiles) {
        try {
            $content = Get-Content -Path $file.FullName -Raw
            $manifest = ConvertFrom-Yaml $content

            $identity = $manifest.identity
            $runtime = $manifest.runtime
            $name = $identity.name

            $agent = [PSCustomObject]@{
                PSTypeName     = 'AzAIManifest'
                Name           = $name
                Id             = $identity.id
                Description    = $identity.description
                Version        = $identity.version
                ExecutionMode  = $runtime.executionMode
                Model          = $runtime.defaultModel
                ApprovalPolicy = $runtime.approvalPolicy
                Instructions   = $runtime.instructions.text
                McpServers     = $manifest.endpoints.mcpServers
                Tools          = $manifest.tools | ForEach-Object { $_.name }
                Budgets        = $manifest.policies.defaultBudgets
                Chaining       = $manifest.chaining
                SourceFile     = $file.Name
            }

            $agents[$name] = $agent
            Write-Verbose "Loaded manifest: $name ($($runtime.executionMode)) from $($file.Name)"
        }
        catch {
            Write-Warning "Failed to parse $($file.Name): $_"
        }
    }

    Write-Verbose "Loaded $($agents.Count) manifests from $Path"
    return $agents
}
