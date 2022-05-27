<#
    .SYNOPSIS
        This is a build task that generates conceptual help.

    .PARAMETER ProjectPath
        The root path to the project. Defaults to $BuildRoot.

    .PARAMETER OutputDirectory
        The base directory of all output. Defaults to folder 'output' relative to
        the $BuildRoot.

    .PARAMETER ProjectName
        The project name.

    .PARAMETER SourcePath
        The path to the source folder name.

    .PARAMETER BuildInfo
        The build info object from ModuleBuilder. Defaults to an empty hashtable.

    .NOTES
        This is a build task that is primarily meant to be run by Invoke-Build but
        wrapped by the Sampler project's build.ps1 (https://github.com/gaelcolas/Sampler).
#>
param
(
    [Parameter()]
    [System.String]
    $BuiltModuleSubdirectory = (property BuiltModuleSubdirectory ''),

    [Parameter()]
    [System.Management.Automation.SwitchParameter]
    $VersionedOutputDirectory = (property VersionedOutputDirectory $true),

    [Parameter()]
    [System.String]
    $ProjectName = (property ProjectName ''),

    [Parameter()]
    [System.String]
    $SourcePath = (property SourcePath ''),

    [Parameter()]
    $SkipPublish = (property SkipPublish ''),

    [Parameter()]
    $MainGitBranch = (property MainGitBranch 'main'),

    [Parameter()]
    $RepositoryPAT = (property RepositoryPAT ''),

    [Parameter()]
    [string]
    $GitConfigUserEmail = (property GitConfigUserEmail ''),

    [Parameter()]
    [string]
    $GitConfigUserName = (property GitConfigUserName ''),

    [Parameter()]
    $BuildInfo = (property BuildInfo @{ })
)

# Synopsis: Creates a git tag for the release that is published to a Gallery
task Create_Release_Git_Tag {
    . Set-SamplerTaskVariable

    function Invoke-Git
    {
        param
        (
            $Arguments
        )

        # catch is triggered ONLY if $exe can't be found, never for errors reported by $exe itself
        try { & git $Arguments } catch { throw $_ }

        if ($LASTEXITCODE)
        {
            throw "git returned exit code $LASTEXITCODE indicated failure."
        }
    }

    <#
        This will return the tag on the HEAD commit, or blank if it
        fails (the error that is catched to $null).

        This call should not use Invoke-Git since it should not throw
        on error.
    #>
    $isCurrentTag = git describe --contains 2> $null

    if ($isCurrentTag)
    {
        Write-Build Green ('Found a tag. Assuming a full release has been pushed for module version ''{0}''. Exiting.' -f $ModuleVersion)
    }
    elseif ($SkipPublish) {
        Write-Build Yellow ('Skipping the creating of a tag for module version ''{0}'' since ''$SkipPublish'' was set to ''$true''.' -f $ModuleVersion)
    }
    else
    {
        Write-Build DarkGray ('About to create the tag ''{0}'' for module version ''{1}''.' -f $releaseTag, $ModuleVersion)

        foreach ($gitConfigKey in @('UserName', 'UserEmail'))
        {
            $gitConfigVariableName = 'GitConfig{0}' -f $gitConfigKey

            if (-not (Get-Variable -Name $gitConfigVariableName -ValueOnly -ErrorAction 'SilentlyContinue'))
            {
                # Variable is not set in context, use $BuildInfo.ChangelogConfig.<varName>
                $configurationValue = $BuildInfo.GitConfig.($gitConfigKey)

                Set-Variable -Name $gitConfigVariableName -Value $configurationValue

                Write-Build DarkGray "`t...Set property $gitConfigVariableName to the value $configurationValue"
            }
        }

        Write-Build DarkGray "`tSetting git configuration."

        Invoke-Git @('config', 'user.name', $GitConfigUserName)
        Invoke-Git @('config', 'user.email', $GitConfigUserEmail)

        # Make empty line in output
        ""

        $releaseTag = 'v{0}' -f $ModuleVersion

        Write-Build DarkGray ("`tGetting HEAD commit for the default branch '{0}." -f $MainGitBranch)

        $defaultBranchHeadCommit = Invoke-Git @('rev-parse', "origin/$MainGitBranch")

        Write-Build DarkGray ("`tCreating tag '{0}' on the commit '{1}'." -f $releaseTag, $defaultBranchHeadCommit)

        Invoke-Git @('tag', $releaseTag, $defaultBranchHeadCommit)

        Write-Build DarkGray ("`tPushing created tag '{0}' to the default branch '{1}'." -f $releaseTag, $MainGitBranch)

        $pushArguments = @()

        if ($RepositoryPAT)
        {
            Write-Build DarkGray "`t`tUsing personal access token to push the tag."

            $patBase64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(('{0}:{1}' -f 'PAT', $RepositoryPAT)))

            $pushArguments += @('-c', ('http.extraheader="AUTHORIZATION: basic {0}"' -f $patBase64))
        }

        $pushArguments += @('-c', 'http.sslbackend="schannel"', 'push', 'origin', '--tags')

        Invoke-Git $pushArguments

        <#
            Wait for a few seconds so the tag have time to propegate.
            This way next task have chance to find the tag.
        #>
        Start-Sleep -Seconds 5

        Write-Build Green 'Tag created and pushed.'
    }
}