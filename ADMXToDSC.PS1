#requires -version 4.0
#requires -Module GroupPolicy

function Recurse_PolicyKeys {

    [cmdletbinding()]
    param (

        [string]$key,

        [string]$gpoName

    )

    Begin {

        Write-Verbose "Starting: $($MyInvocation.Mycommand)"

    }

    Process {

        # This function goes through the registry.pol data and finds entries associated with the
        # two policy hives mentioned above. Consider rename of the function to be more modular and
        # powershell'ish
        Write-Verbose "Getting GPRegistry value $key from $gponame"
        $current = Get-GPRegistryValue -Name $gpo -Key $key  -ErrorAction SilentlyContinue
        if ($null -eq $current) {

            #means we didn't get a reference to the key being called
            #probably beause there's no pol settings under it
            return

        }

        $returnVal = New-Object -TypeName System.Collections.ArrayList

        foreach ($item in $current) {

            if ($null -ne $item.ValueName) {

                $returnVal.Add($item)

            } else {

                #this handles the case where we're on a container (i.e. keypath) that doesn't have a value
                Recurse_PolicyKeys -Key $item.FullKeyPath -gpoName $gpo

            }

        }

        Write-Output -InputObject $returnVal

    }

    End {}

}


function New-DSCDoc {

    [cmdletbinding()]
    param (

        [string] $path,

        [string] $gpo,

        [array] $policies

    )

    Begin {

        # consider rename of function - New-DSCDoc
        # add verbose output, error handling and debugging

        Write-Verbose "Starting: $($MyInvocation.Mycommand)"

        #parse the spaces out of the GPO name, since we use it for the Configuration name
        $gpo = $gpo -replace " ","_"
        $outputFile = "$path\$gpo.ps1"
        $Splat = @{

            'FilePath' = $outputFile
            'Encoding' = 'Unicode'

        }

    }

    Process {

        Write-Verbose "Saving config to $outputFile"
        $String = "Configuration `"$gpo`""
        $String | out-file @splat

        #add append = $true key to splat hash for remaining out-file calls
        $splat.Add('Append', $true)

        $String = '{'
        $String | out-file @splat

        $String = "   Import-DscResource -ModuleName PSDesiredStateConfiguration"
        $String | out-file @splat

        $String = 'Node localhost'
        $String | out-file @splat

        $String = '  {'
        $String | out-file @splat

        foreach ($regItem in $policies) {

            if ($null -eq $regItem.FullKeyPath) {

                #throw away any blank entries
                continue

            }

            #this next bit guarantees a unique DSC resource name by adding each registry resource name to a hashtable.
            #If found, we increment the key index and append to resource name
            $resourceName = ""
            if ($script:valueNameHashTable.ContainsKey($regItem.ValueName)) {

                $script:valueNameHashTable[$regItem.ValueName] = $script:valueNameHashTable[$regItem.ValueName]+1
                $resourceName = $regItem.ValueName+$script:valueNameHashTable[$regItem.ValueName]

            } else {

                $script:valueNameHashTable.Add($regItem.ValueName,0)
                $resourceName = $regItem.ValueName

            }

            # now build the resources
            # exploring other ways to create the resource info.
            # added unicode encoding to valuename and data to support that type for certain policies
            #(e.g. SRP/Applocker)

            $String = "    Registry '" + $resourceName + "'"
            $String | out-file @splat

            $String = '    {'
            $String | out-file @splat

            $String = "      Ensure = 'Present'"
            $String | out-file @splat

            $String = "      Key = '"+ $regItem.FullKeyPath + "'"
            $String | out-file @splat

            $String = "      ValueName = '" + $regItem.ValueName + "'"
            $String | out-file @splat

            $String = "      ValueType = '" +$regItem.Type + "'"
            $String | out-file @splat

            # need to trim any null characters from ValueData (mostly an Applocker issue)
            $trimValue = $regItem.Value.ToString().Trim("`0")

            $String = "      ValueData = '" +$trimValue + "'"
            $String | out-file @splat

            $String = '    }'
            $String | out-file @splat

        }

        $String = '  }'
        $String | out-file @splat

        $String = '}'
        $String | out-file @splat

        $String = $gpo
        $String | out-file @splat

    }

    End {}

}


function ADMtoDSC {
    [cmdletbinding()]
    param (

        [String] $gpo,

        [String] $path

    )

    Write-Verbose "Starting: $($MyInvocation.Mycommand)"
    #get policy keys for two main per-computer keys where policy is stored
    #NOTE that this script could be extended to add HKCU per-user keys but as of today--no good mechanisms exist
    #for triggering per-user configuration in DSC
    $policies = Recurse_PolicyKeys -key "HKLM\Software\Policies" -gpo $gpo

    $policies += Recurse_PolicyKeys -key "HKLM\Software\Microsoft\Windows NT\CurrentVersion" -gpo $gpo

    # build the DSC configuration doc
    New-DSCDoc -path $path -gpo $gpo -policies $policies
    # add error/debug and verbose.

}


function ConvertTo-ADMXtoDSC {

    <#
    .Synopsis
    ConvertTo-ADMXtoDSC allows you to get registry keys and values configured within the registry.pol file in existing
    GPOs and use that information to create DSC docuemnts.

    .DESCRIPTION
    Group Policy Objects have been created, managed, configured, re-configured, deleted,
    backed up, imported, exported, inspected, detected, neglected and rejected for many years.
    Now with the advent of Desired State Configuration (DSC) ensuring that the work previously
    done with regards to configuring registry policy is not lost, is key. ConvertTo-ADMXtoDSC is a cmdlet
    (advanced function) that was created to address this sceanario. The ConvertTo-ADMXtoDSC cmdlet
    requires the GroupPolicy PowerShell Module. The GP cmdlets are avaialbe on machines where
    the GPMC is installed. The <gponame>.ps1 file will be opened in the PowerShell ISE as a
    convenience.

    .EXAMPLE
    ConvertTo-ADMXtoDSC -GPOName <gpo> -OutputFolder <folder where to create DSC .ps1 file>

    .EXAMPLE
    GP2DSC -GPOName <GPO> -OutputFolder <folder>

    .LINK
        Http://www.github.com/gpoguy

    .NOTES
        # add additional cmdletBinding information to make the experience more robust.

        # possibly re-work parameter names.

        # possible new scenarios... optional open in ISE when complete.
        # optional create of .mof file, including target test machine. This scenario would
        # be an e2e test where the GPO is selected, Registry data is converted to .ps1 config
        # the configuration is called and .mof is created and DSC configuration is started targeting
        # a test machine.
    #>

    [CmdletBinding()]
    [Alias("GP2DSC")]
    [OutputType([int])]
    Param (

        [Parameter(Mandatory=$true)]
        [string]$gpoName,

        [Parameter(Mandatory=$true)]
        [Alias("Path")]
        [string] $outputFolder

    )

    Begin {

        Write-Verbose "Starting: $($MyInvocation.Mycommand)"
        #display PSBoundparameters formatted nicely for Verbose output
        [string]$pb = ($PSBoundParameters | Format-Table -AutoSize | Out-String).TrimEnd()
        Write-Verbose "PSBoundparameters: `n$($pb.split("`n").Foreach({"$("`t"*4)$_"}) | Out-String) `n"

    }

    Process {

        #this hash table holds valuename, which we use to name registry resources--guarantees that they are unique
        $script:valueNameHashTable = @{}

        Write-Verbose "Analyzing GPO $gponame and saving results to $outputfolder"
        ADMToDSC -gpo $gpoName -path $outputFolder
        #ISE "$outputfolder\$gponame.ps1"

    }

    End {

        Write-Verbose "Ending: $($MyInvocation.Mycommand)"

    }

}