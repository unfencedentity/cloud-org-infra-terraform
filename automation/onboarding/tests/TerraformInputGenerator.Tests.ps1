Set-StrictMode -Version Latest

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\TerraformInputGenerator.psm1'
$scriptPath = Join-Path -Path $PSScriptRoot -ChildPath '..\New-TerraformInputsFromAssessment.ps1'
$exampleProfilePath = Join-Path -Path $PSScriptRoot -ChildPath '..\onboarding-profile.example.json'
Import-Module $modulePath -Force

function New-TestGoProfile {
    param([hashtable]$Overrides = @{})

    $profileObject = Get-Content -LiteralPath $exampleProfilePath -Raw | ConvertFrom-Json
    foreach ($key in $Overrides.Keys) {
        $profileObject.$key = $Overrides[$key]
    }
    return $profileObject
}

function New-TestWorkspace {
    $root = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("tf-input-gen-tests-" + [guid]::NewGuid().ToString('N'))
    New-Item -Path $root -ItemType Directory -Force | Out-Null
    return $root
}

Describe 'TerraformInputGenerator module' {

    Context 'Assert-ValidAssessmentProfile' {
        It 'accepts a valid GO profile' {
            { Assert-ValidAssessmentProfile -Profile (New-TestGoProfile) } | Should Not Throw
        }

        It 'rejects a NO-GO profile' {
            $profileObject = New-TestGoProfile -Overrides @{ overallStatus = 'NO-GO'; assessmentOutcomeType = 'Failure' }
            { Assert-ValidAssessmentProfile -Profile $profileObject } | Should Throw 'not GO'
        }

        It 'rejects a profile with an inconsistent outcome type' {
            $profileObject = New-TestGoProfile -Overrides @{ assessmentOutcomeType = 'Failure' }
            { Assert-ValidAssessmentProfile -Profile $profileObject } | Should Throw 'inconsistent'
        }

        It 'rejects a malformed (non-object) profile' {
            { Assert-ValidAssessmentProfile -Profile 'not-a-profile' } | Should Throw 'malformed'
        }

        It 'rejects an incomplete profile missing required fields' {
            { Assert-ValidAssessmentProfile -Profile ([pscustomobject]@{ overallStatus = 'GO' }) } | Should Throw 'incomplete'
        }

        It 'rejects an unsupported schema version' {
            $profileObject = New-TestGoProfile -Overrides @{ schemaVersion = '99.0.0' }
            { Assert-ValidAssessmentProfile -Profile $profileObject } | Should Throw 'not supported'
        }

        It 'rejects a profile with an empty required field' {
            $profileObject = New-TestGoProfile -Overrides @{ workloadLocation = '' }
            { Assert-ValidAssessmentProfile -Profile $profileObject } | Should Throw 'incomplete'
        }
    }

    Context 'Get-AssessmentProfileFromFile' {
        It 'throws for a missing file' {
            { Get-AssessmentProfileFromFile -Path (Join-Path ([System.IO.Path]::GetTempPath()) 'does-not-exist.json') } | Should Throw 'was not found'
        }

        It 'throws for malformed JSON content' {
            $badFile = Join-Path ([System.IO.Path]::GetTempPath()) ('bad-' + [guid]::NewGuid().ToString('N') + '.json')
            Set-Content -Path $badFile -Value '{ this is not valid json'
            try {
                { Get-AssessmentProfileFromFile -Path $badFile } | Should Throw 'not valid JSON'
            }
            finally {
                Remove-Item -Path $badFile -Force -ErrorAction SilentlyContinue
            }
        }

        It 'parses a valid profile file' {
            $result = Get-AssessmentProfileFromFile -Path $exampleProfilePath
            $result.overallStatus | Should Be 'GO'
        }
    }

    Context 'field validators consistent with Terraform variables' {
        It 'accepts a valid application name' {
            { Assert-ValidApplicationName -Application 'core' } | Should Not Throw
        }

        It 'rejects an application name that is too long' {
            { Assert-ValidApplicationName -Application 'waytoolongapplicationname' } | Should Throw 'invalid'
        }

        It 'rejects an uppercase environment name' {
            { Assert-ValidEnvironmentName -Environment 'DEV' } | Should Throw 'invalid'
        }

        It 'rejects a region code that is not exactly 3 letters' {
            { Assert-ValidRegionCode -RegionCode 'de' -ParameterName 'workload_region_code' } | Should Throw 'invalid'
        }

        It 'rejects an instance number that is not 3 digits' {
            { Assert-ValidInstanceNumber -InstanceNumber '1' } | Should Throw 'invalid'
        }
    }

    Context 'Assert-ValidAdminSourceCidr (safe defaults and rejection rules)' {
        It 'does not require a CIDR when public access is disabled' {
            { Assert-ValidAdminSourceCidr -EnableVmPublicIp $false -AdminSourceCidr $null } | Should Not Throw
        }

        It 'requires a CIDR when public access is enabled' {
            { Assert-ValidAdminSourceCidr -EnableVmPublicIp $true -AdminSourceCidr $null } | Should Throw 'required'
        }

        It 'rejects "*" as a CIDR' {
            { Assert-ValidAdminSourceCidr -EnableVmPublicIp $true -AdminSourceCidr '*' } | Should Throw 'not allowed'
        }

        It 'rejects "0.0.0.0/0" as a CIDR' {
            { Assert-ValidAdminSourceCidr -EnableVmPublicIp $true -AdminSourceCidr '0.0.0.0/0' } | Should Throw 'not allowed'
        }

        It 'rejects "Internet" as a CIDR' {
            { Assert-ValidAdminSourceCidr -EnableVmPublicIp $true -AdminSourceCidr 'Internet' } | Should Throw 'not allowed'
        }

        It 'accepts a specific restricted CIDR' {
            { Assert-ValidAdminSourceCidr -EnableVmPublicIp $true -AdminSourceCidr '203.0.113.10/32' } | Should Not Throw
        }
    }

    Context 'Assert-ConsistentEnvironment' {
        It 'allows an unspecified requested environment' {
            { Assert-ConsistentEnvironment -RequestedEnvironment $null -ProfileEnvironment 'dev' } | Should Not Throw
        }

        It 'allows a matching requested environment' {
            { Assert-ConsistentEnvironment -RequestedEnvironment 'dev' -ProfileEnvironment 'dev' } | Should Not Throw
        }

        It 'rejects a mismatched requested environment' {
            { Assert-ConsistentEnvironment -RequestedEnvironment 'prod' -ProfileEnvironment 'dev' } | Should Throw 'does not match'
        }
    }

    Context 'New-BootstrapRemoteStateTfVars mapping' {
        It 'maps only fields present in the assessment profile' {
            $result = New-BootstrapRemoteStateTfVars -Profile (New-TestGoProfile) -InstanceNumber '001'

            $result.environment | Should Be 'dev'
            $result.workload_location | Should Be 'denmarkeast'
            $result.workload_region_code | Should Be 'deu'
            $result.instance_number | Should Be '001'
        }

        It 'rejects a NO-GO profile before mapping' {
            $profileObject = New-TestGoProfile -Overrides @{ overallStatus = 'NO-GO'; assessmentOutcomeType = 'Failure' }
            { New-BootstrapRemoteStateTfVars -Profile $profileObject -InstanceNumber '001' } | Should Throw 'not GO'
        }
    }

    Context 'New-EnvironmentDevTfVars mapping and safe defaults' {
        It 'maps profile values and required parameters correctly' {
            $result = New-EnvironmentDevTfVars -Profile (New-TestGoProfile) -Application 'core' -InstanceNumber '001' `
                -SshPublicKey 'ssh-ed25519 AAAATEST test@example' -AlertEmailAddress 'ops@example.invalid'

            $result.application | Should Be 'core'
            $result.environment | Should Be 'dev'
            $result.workload_location | Should Be 'denmarkeast'
            $result.workload_region_code | Should Be 'deu'
            $result.monitoring_location | Should Be 'swedencentral'
            $result.monitoring_region_code | Should Be 'swe'
            $result.instance_number | Should Be '001'
            $result.ssh_public_key | Should Be 'ssh-ed25519 AAAATEST test@example'
            $result.alert_email_address | Should Be 'ops@example.invalid'
        }

        It 'defaults to enable_vm_public_ip = false and admin_source_cidr = null when not specified' {
            $result = New-EnvironmentDevTfVars -Profile (New-TestGoProfile) -Application 'core' -InstanceNumber '001' `
                -SshPublicKey 'ssh-ed25519 AAAATEST test@example' -AlertEmailAddress 'ops@example.invalid'

            $result.enable_vm_public_ip | Should Be $false
            $result.admin_source_cidr | Should Be $null
        }

        It 'serializes admin_source_cidr as JSON null by default' {
            $result = New-EnvironmentDevTfVars -Profile (New-TestGoProfile) -Application 'core' -InstanceNumber '001' `
                -SshPublicKey 'ssh-ed25519 AAAATEST test@example' -AlertEmailAddress 'ops@example.invalid'

            ($result | ConvertTo-Json) | Should Match '"admin_source_cidr":\s*null'
        }

        It 'throws when SshPublicKey is empty' {
            { New-EnvironmentDevTfVars -Profile (New-TestGoProfile) -Application 'core' -InstanceNumber '001' `
                -SshPublicKey '' -AlertEmailAddress 'ops@example.invalid' } | Should Throw 'SshPublicKey'
        }

        It 'throws when AlertEmailAddress is invalid' {
            { New-EnvironmentDevTfVars -Profile (New-TestGoProfile) -Application 'core' -InstanceNumber '001' `
                -SshPublicKey 'ssh-ed25519 AAAATEST test@example' -AlertEmailAddress 'not-an-email' } | Should Throw 'valid email'
        }

        It 'throws when EnableVmPublicIp is true without a valid AdminSourceCidr' {
            { New-EnvironmentDevTfVars -Profile (New-TestGoProfile) -Application 'core' -InstanceNumber '001' `
                -SshPublicKey 'ssh-ed25519 AAAATEST test@example' -AlertEmailAddress 'ops@example.invalid' -EnableVmPublicIp $true } | Should Throw 'required'
        }

        It 'accepts EnableVmPublicIp true with a valid restricted AdminSourceCidr' {
            $result = New-EnvironmentDevTfVars -Profile (New-TestGoProfile) -Application 'core' -InstanceNumber '001' `
                -SshPublicKey 'ssh-ed25519 AAAATEST test@example' -AlertEmailAddress 'ops@example.invalid' `
                -EnableVmPublicIp $true -AdminSourceCidr '203.0.113.10/32'

            $result.enable_vm_public_ip | Should Be $true
            $result.admin_source_cidr | Should Be '203.0.113.10/32'
        }
    }

    Context 'Write-TerraformAutoTfVarsFile (atomicity and overwrite protection)' {
        It 'writes structured JSON to a new file' {
            $workspace = New-TestWorkspace
            try {
                $targetPath = Join-Path $workspace 'terraform.auto.tfvars.json'
                Write-TerraformAutoTfVarsFile -InputObject ([ordered]@{ environment = 'dev' }) -Path $targetPath

                Test-Path -LiteralPath $targetPath | Should Be $true
                (Get-Content -LiteralPath $targetPath -Raw | ConvertFrom-Json).environment | Should Be 'dev'
            }
            finally {
                Remove-Item -Path $workspace -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'refuses to overwrite an existing file without -Force' {
            $workspace = New-TestWorkspace
            try {
                $targetPath = Join-Path $workspace 'terraform.auto.tfvars.json'
                Write-TerraformAutoTfVarsFile -InputObject ([ordered]@{ environment = 'dev' }) -Path $targetPath

                { Write-TerraformAutoTfVarsFile -InputObject ([ordered]@{ environment = 'prod' }) -Path $targetPath } | Should Throw 'Refusing to overwrite'
                (Get-Content -LiteralPath $targetPath -Raw | ConvertFrom-Json).environment | Should Be 'dev'
            }
            finally {
                Remove-Item -Path $workspace -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'overwrites an existing file when -Force is specified' {
            $workspace = New-TestWorkspace
            try {
                $targetPath = Join-Path $workspace 'terraform.auto.tfvars.json'
                Write-TerraformAutoTfVarsFile -InputObject ([ordered]@{ environment = 'dev' }) -Path $targetPath
                Write-TerraformAutoTfVarsFile -InputObject ([ordered]@{ environment = 'prod' }) -Path $targetPath -Force

                (Get-Content -LiteralPath $targetPath -Raw | ConvertFrom-Json).environment | Should Be 'prod'
            }
            finally {
                Remove-Item -Path $workspace -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'leaves no temporary file behind after a successful write' {
            $workspace = New-TestWorkspace
            try {
                $targetPath = Join-Path $workspace 'terraform.auto.tfvars.json'
                Write-TerraformAutoTfVarsFile -InputObject ([ordered]@{ environment = 'dev' }) -Path $targetPath

                @(Get-ChildItem -Path $workspace -Filter '*.tmp').Count | Should Be 0
            }
            finally {
                Remove-Item -Path $workspace -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'leaves no destination or temporary file behind after a rejected overwrite' {
            $workspace = New-TestWorkspace
            try {
                $targetPath = Join-Path $workspace 'terraform.auto.tfvars.json'
                Write-TerraformAutoTfVarsFile -InputObject ([ordered]@{ environment = 'dev' }) -Path $targetPath
                $beforeHash = (Get-FileHash -LiteralPath $targetPath).Hash

                try { Write-TerraformAutoTfVarsFile -InputObject ([ordered]@{ environment = 'prod' }) -Path $targetPath } catch { }

                (Get-FileHash -LiteralPath $targetPath).Hash | Should Be $beforeHash
                @(Get-ChildItem -Path $workspace -Filter '*.tmp').Count | Should Be 0
            }
            finally {
                Remove-Item -Path $workspace -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'New-TerraformInputsFromAssessment.ps1 (end-to-end)' {

    Context 'valid GO profile generates both files' {
        It 'generates bootstrap and environment tfvars files with expected content' {
            $workspace = New-TestWorkspace
            try {
                New-Item -Path (Join-Path $workspace 'bootstrap\remote-state') -ItemType Directory -Force | Out-Null
                New-Item -Path (Join-Path $workspace 'environments\dev') -ItemType Directory -Force | Out-Null

                & $scriptPath -ProfilePath $exampleProfilePath -Application 'core' -InstanceNumber '001' `
                    -SshPublicKey 'ssh-ed25519 AAAATEST test@example' -AlertEmailAddress 'ops@example.invalid' `
                    -RepositoryRoot $workspace -InformationAction SilentlyContinue | Out-Null

                $bootstrapPath = Join-Path $workspace 'bootstrap\remote-state\terraform.auto.tfvars.json'
                $environmentPath = Join-Path $workspace 'environments\dev\terraform.auto.tfvars.json'

                Test-Path -LiteralPath $bootstrapPath | Should Be $true
                Test-Path -LiteralPath $environmentPath | Should Be $true

                $bootstrapContent = Get-Content -LiteralPath $bootstrapPath -Raw | ConvertFrom-Json
                $bootstrapContent.workload_region_code | Should Be 'deu'

                $environmentContent = Get-Content -LiteralPath $environmentPath -Raw | ConvertFrom-Json
                $environmentContent.application | Should Be 'core'
                $environmentContent.enable_vm_public_ip | Should Be $false
            }
            finally {
                Remove-Item -Path $workspace -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'NO-GO profile rejection' {
        It 'does not generate any files for a NO-GO profile' {
            $workspace = New-TestWorkspace
            try {
                $badProfilePath = Join-Path $workspace 'no-go-profile.json'
                $profileObject = New-TestGoProfile -Overrides @{ overallStatus = 'NO-GO'; assessmentOutcomeType = 'Failure' }
                $profileObject | ConvertTo-Json -Depth 12 | Set-Content -Path $badProfilePath

                { & $scriptPath -ProfilePath $badProfilePath -Application 'core' -InstanceNumber '001' `
                    -SshPublicKey 'ssh-ed25519 AAAATEST test@example' -AlertEmailAddress 'ops@example.invalid' `
                    -RepositoryRoot $workspace -InformationAction SilentlyContinue -ErrorAction Stop } | Should Throw 'Terraform input generation failed'

                Test-Path -LiteralPath (Join-Path $workspace 'bootstrap\remote-state\terraform.auto.tfvars.json') | Should Be $false
                Test-Path -LiteralPath (Join-Path $workspace 'environments\dev\terraform.auto.tfvars.json') | Should Be $false
            }
            finally {
                Remove-Item -Path $workspace -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'malformed profile rejection' {
        It 'does not generate any files for malformed JSON' {
            $workspace = New-TestWorkspace
            try {
                $badProfilePath = Join-Path $workspace 'malformed-profile.json'
                Set-Content -Path $badProfilePath -Value '{ not valid json'

                { & $scriptPath -ProfilePath $badProfilePath -Application 'core' -InstanceNumber '001' `
                    -SshPublicKey 'ssh-ed25519 AAAATEST test@example' -AlertEmailAddress 'ops@example.invalid' `
                    -RepositoryRoot $workspace -InformationAction SilentlyContinue -ErrorAction Stop } | Should Throw 'Terraform input generation failed'

                Test-Path -LiteralPath (Join-Path $workspace 'bootstrap\remote-state\terraform.auto.tfvars.json') | Should Be $false
                Test-Path -LiteralPath (Join-Path $workspace 'environments\dev\terraform.auto.tfvars.json') | Should Be $false
            }
            finally {
                Remove-Item -Path $workspace -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'missing required input' {
        It 'fails when Application is empty' {
            { & $scriptPath -ProfilePath $exampleProfilePath -Application '' -InstanceNumber '001' `
                -SshPublicKey 'ssh-ed25519 AAAATEST test@example' -AlertEmailAddress 'ops@example.invalid' `
                -ErrorAction Stop } | Should Throw 'Cannot validate argument'
        }

        It 'fails when AlertEmailAddress is empty' {
            { & $scriptPath -ProfilePath $exampleProfilePath -Application 'core' -InstanceNumber '001' `
                -SshPublicKey 'ssh-ed25519 AAAATEST test@example' -AlertEmailAddress '' `
                -ErrorAction Stop } | Should Throw 'argument is null or empty'
        }
    }

    Context '-WhatIf support' {
        It 'does not write any files when -WhatIf is specified' {
            $workspace = New-TestWorkspace
            try {
                & $scriptPath -ProfilePath $exampleProfilePath -Application 'core' -InstanceNumber '001' `
                    -SshPublicKey 'ssh-ed25519 AAAATEST test@example' -AlertEmailAddress 'ops@example.invalid' `
                    -RepositoryRoot $workspace -WhatIf -InformationAction SilentlyContinue | Out-Null

                Test-Path -LiteralPath (Join-Path $workspace 'bootstrap\remote-state\terraform.auto.tfvars.json') | Should Be $false
                Test-Path -LiteralPath (Join-Path $workspace 'environments\dev\terraform.auto.tfvars.json') | Should Be $false
            }
            finally {
                Remove-Item -Path $workspace -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'overwrite protection at the orchestration level' {
        It 'fails and leaves prior files untouched when a generated file already exists without -Force' {
            $workspace = New-TestWorkspace
            try {
                & $scriptPath -ProfilePath $exampleProfilePath -Application 'core' -InstanceNumber '001' `
                    -SshPublicKey 'ssh-ed25519 AAAATEST test@example' -AlertEmailAddress 'ops@example.invalid' `
                    -RepositoryRoot $workspace -InformationAction SilentlyContinue | Out-Null

                $environmentPath = Join-Path $workspace 'environments\dev\terraform.auto.tfvars.json'
                $beforeHash = (Get-FileHash -LiteralPath $environmentPath).Hash

                { & $scriptPath -ProfilePath $exampleProfilePath -Application 'other' -InstanceNumber '002' `
                    -SshPublicKey 'ssh-ed25519 AAAATEST test@example' -AlertEmailAddress 'ops@example.invalid' `
                    -RepositoryRoot $workspace -InformationAction SilentlyContinue -ErrorAction Stop } | Should Throw 'Terraform input generation failed'

                (Get-FileHash -LiteralPath $environmentPath).Hash | Should Be $beforeHash
            }
            finally {
                Remove-Item -Path $workspace -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'succeeds and updates content when -Force is specified' {
            $workspace = New-TestWorkspace
            try {
                & $scriptPath -ProfilePath $exampleProfilePath -Application 'core' -InstanceNumber '001' `
                    -SshPublicKey 'ssh-ed25519 AAAATEST test@example' -AlertEmailAddress 'ops@example.invalid' `
                    -RepositoryRoot $workspace -InformationAction SilentlyContinue | Out-Null

                & $scriptPath -ProfilePath $exampleProfilePath -Application 'other' -InstanceNumber '002' `
                    -SshPublicKey 'ssh-ed25519 AAAATEST test@example' -AlertEmailAddress 'ops@example.invalid' `
                    -RepositoryRoot $workspace -Force -InformationAction SilentlyContinue | Out-Null

                $environmentPath = Join-Path $workspace 'environments\dev\terraform.auto.tfvars.json'
                (Get-Content -LiteralPath $environmentPath -Raw | ConvertFrom-Json).application | Should Be 'other'
            }
            finally {
                Remove-Item -Path $workspace -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'no partial file left after a failure' {
        It 'does not create the bootstrap file when environment input validation fails' {
            $workspace = New-TestWorkspace
            try {
                { & $scriptPath -ProfilePath $exampleProfilePath -Application 'core' -InstanceNumber '001' `
                    -SshPublicKey 'ssh-ed25519 AAAATEST test@example' -AlertEmailAddress 'not-an-email' `
                    -RepositoryRoot $workspace -InformationAction SilentlyContinue -ErrorAction Stop } | Should Throw 'Terraform input generation failed'

                Test-Path -LiteralPath (Join-Path $workspace 'bootstrap\remote-state\terraform.auto.tfvars.json') | Should Be $false
                Test-Path -LiteralPath (Join-Path $workspace 'environments\dev\terraform.auto.tfvars.json') | Should Be $false
            }
            finally {
                Remove-Item -Path $workspace -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
