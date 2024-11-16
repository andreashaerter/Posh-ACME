function Get-CurrentPluginType { 'dns-01' }

function Add-DnsTxt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory,Position=0)]
        [string]$RecordName,
        [Parameter(Mandatory,Position=1)]
        [string]$TxtValue,
        [Parameter(Mandatory,Position=2)]
        [string]$INWXUsername,
        [Parameter(Mandatory,Position=3)]
        [securestring]$INWXPassword,
        [Parameter(Position=4)]
        [AllowNull()]
        [securestring]$INWXSharedSecret,
        [Parameter(ValueFromRemainingArguments)]
        $ExtraParams
    )

    # login
    Connect-INWX $INWXUsername $INWXPassword $INWXSharedSecret

    # set communication endpoint
    # production system at: https://api.domrobot.com
    # test system at: https://api.ote.domrobot.com
    $apiRoot = "https://api.domrobot.com/jsonrpc/"

    # get DNS zone (main domain) and name (sub domain) belonging to the record (assumes
    # $zoneName contains the zone name containing the record)
    $zoneName = Find-INWXZone $RecordName
    $recShort = $RecordName.Remove($RecordName.ToLower().LastIndexOf($zoneName.ToLower().TrimEnd(".")), $zoneName.TrimEnd(".").Length).TrimEnd(".");
    Write-Debug "RecordName: $RecordName"
    Write-Debug "zoneName: $zoneName"
    Write-Debug "recShort: $recShort"

    # check if the record exists
    # https://www.inwx.de/de/help/apidoc/f/ch02s15.html#nameserver.info
    $reqParams = @{}
    $reqParams.Uri = $apiRoot
    $reqParams.Method = "POST"
    $reqParams.ContentType = "application/json"
    $reqParams.WebSession = $INWXSession
    $reqParams.Body = @{
        "jsonrpc" = "2.0";
        "id" = [guid]::NewGuid()
        "method" = "nameserver.info";
        "params" = @{
            "domain" = $zoneName;
            "type" = "TXT";
            "name" = $recShort;
        };
    } | ConvertTo-Json

    $response = $False
    $responseContent = $False
    $recordIds = $False
    try {
        Write-Verbose "Checking for $RecordName record(s)."
        Write-Debug "$($reqParams.Method) $apiRoot`n$($reqParams.Body)"
        $response = Invoke-WebRequest @reqParams @script:UseBasic
    } catch {
        throw "INWX method call $(($reqParams.Body | ConvertFrom-Json).method) failed (unknown error)."
    }
    if ($response -eq $False -or
        $response.StatusCode -ne 200) {
        throw "INWX method call $(($reqParams.Body | ConvertFrom-Json).method) failed (status code $($response.StatusCode))."
    } else {
        $responseContent = $response.Content | ConvertFrom-Json
    }
    Write-Debug "Received content:`n$($response.Content)"

    switch ($responseContent.code) {
        # 1000: Command completed successfully
        # 2302: Object exists
        {($PSItem -eq 1000 -or
          $PSItem -eq 2302)} {
            Write-Debug "INWX method call $(($reqParams.Body | ConvertFrom-Json).method) was successful"
            if ($responseContent.resData.count -gt 0 -and
                $responseContent.resData.record.id) {
                $recordIds = $responseContent.resData.record.id
                if (-not $recordIds -is [array]) {
                    $recordIds = @($recordIds)
                }
                Write-Debug "Found record(s) with ID(s) $recordIds."
            }
        }
        # unexpected
        default {
            throw "Unexpected response from INWX (code: $($responseContent.code)). The plugin might need an update (Add-DnsTxt)."
        }
    }
    Remove-Variable "reqParams", "response", "responseContent"


    if ($recordIds) {
        foreach ($recordId in $recordIds) {
            Write-Verbose "DNS record is already existing, going to update it."
            # update record
            # https://www.inwx.de/de/help/apidoc/f/ch02s15.html#nameserver.updateRecord
            $reqParams = @{}
            $reqParams.Uri = $apiRoot
            $reqParams.Method = "POST"
            $reqParams.ContentType = "application/json"
            $reqParams.WebSession = $INWXSession
            $reqParams.Body = @{
                "jsonrpc" = "2.0";
                "id" = [guid]::NewGuid()
                "method" = "nameserver.updateRecord";
                "params" = @{
                    "id" = $recordId;
                    "type" = "TXT";
                    "content" = $TxtValue;
                    "ttl" = 300;
                };
            } | ConvertTo-Json

            $response = $False
            $responseContent = $False
            try {
                Write-Verbose "Adding record $RecordName with value $TxtValue."
                Write-Debug "$($reqParams.Method) $apiRoot`n$($reqParams.Body)"
                $response = Invoke-WebRequest @reqParams @script:UseBasic
            } catch {
                throw "INWX method call $(($reqParams.Body | ConvertFrom-Json).method) failed (unknown error)."
            }
            if ($response -eq $False -or
                $response.StatusCode -ne 200) {
                throw "INWX method call $(($reqParams.Body | ConvertFrom-Json).method) failed (status code $($response.StatusCode))."
            } else {
                $responseContent = $response.Content | ConvertFrom-Json
            }
            Write-Debug "Received content:`n$($response.Content)"
            # 1000: Command completed successfully
            if ($responseContent.code -eq 1000) {
                Write-Verbose "Updating the record was successful."
            } else {
                throw "Updating the record failed (code: $($responseContent.code))."
            }
            Remove-Variable "reqParams", "response", "responseContent"
        }

    } else {

        Write-Verbose "DNS record does not exist, going to create it."
        # create record
        # https://www.inwx.de/de/help/apidoc/f/ch02s15.html#nameserver.createRecord
        $reqParams = @{}
        $reqParams.Uri = $apiRoot
        $reqParams.Method = "POST"
        $reqParams.ContentType = "application/json"
        $reqParams.WebSession = $INWXSession
        $reqParams.Body = @{
            "jsonrpc" = "2.0";
            "id" = [guid]::NewGuid()
            "method" = "nameserver.createRecord";
            "params" = @{
                "domain" = $zoneName;
                "type" = "TXT";
                "name" = $recShort;
                "content" = $TxtValue;
                "ttl" = 300;
            };
        } | ConvertTo-Json

        $response = $False
        $responseContent = $False
        try {
            Write-Verbose "Adding record $RecordName with value $TxtValue."
            Write-Debug "$($reqParams.Method) $apiRoot`n$($reqParams.Body)"
            $response = Invoke-WebRequest @reqParams @script:UseBasic
        } catch {
            throw "INWX method call $(($reqParams.Body | ConvertFrom-Json).method) failed (unknown error)."
        }
        if ($response -eq $False -or
            $response.StatusCode -ne 200) {
            throw "INWX method call $(($reqParams.Body | ConvertFrom-Json).method) failed (status code $($response.StatusCode))."
        } else {
            $responseContent = $response.Content | ConvertFrom-Json
        }
        Write-Debug "Received content:`n$($response.Content)"
        # 1000: Command completed successfully
        if ($responseContent.code -eq 1000) {
            Write-Verbose "Adding the record was successful."
            if ($responseContent.resData.id -gt 0) {
                Write-Debug "Created record with ID $($responseContent.resData.id)."
            }
        } else {
            throw "Adding the record failed (code: $($responseContent.code))."
        }
        Remove-Variable "reqParams", "response", "responseContent"
    }
    Remove-Variable "recordIds"

    <#
    .SYNOPSIS
        Add a DNS TXT record to INWX.

    .DESCRIPTION
        Uses the INWX DNS API to add or update a DNS TXT record.

    .PARAMETER RecordName
        The fully qualified name of the TXT record.

    .PARAMETER TxtValue
        The value of the TXT record.

    .PARAMETER INWXUsername
        The INWX Username to access the API.

    .PARAMETER INWXPassword
        The password belonging to the username provided via -INWXUsername.

    .PARAMETER INWXSharedSecret
        To be implemented, patches welcome (if you are not using 2FA, do not define this parameter).

    .PARAMETER ExtraParams
        This parameter can be ignored and is only used to prevent errors when splatting with more parameters than this function supports.

    .EXAMPLE
        $password = Read-Host 'API Secret' -AsSecureString
        Add-DnsTxt '_acme-challenge.example.com' 'txt-value' -INWXUsername 'xxxxxx' -INWXPassword $password

        Adds or updates the specified TXT record with the specified value.
    #>
}

function Remove-DnsTxt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory,Position=0)]
        [string]$RecordName,
        [Parameter(Mandatory,Position=1)]
        [string]$TxtValue,
        [Parameter(Mandatory,Position=2)]
        [string]$INWXUsername,
        [Parameter(Mandatory,Position=3)]
        [securestring]$INWXPassword,
        [Parameter(Position=4)]
        [securestring]$INWXSharedSecret,
        [Parameter(ValueFromRemainingArguments)]
        $ExtraParams
    )

    # login
    Connect-INWX $INWXUsername $INWXPassword $INWXSharedSecret

    # set communication endpoint
    # production system at: https://api.domrobot.com
    # test system at: https://api.ote.domrobot.com
    $apiRoot = "https://api.domrobot.com/jsonrpc/"

    # get DNS zone (main domain) and name (sub domain) belonging to the record (assumes
    # $zoneName contains the zone name containing the record)
    $zoneName = Find-INWXZone $RecordName
    $recShort = $RecordName.Remove($RecordName.ToLower().LastIndexOf($zoneName.ToLower().TrimEnd(".")), $zoneName.TrimEnd(".").Length).TrimEnd(".");
    Write-Debug "RecordName: $RecordName"
    Write-Debug "zoneName: $zoneName"
    Write-Debug "recShort: $recShort"

    # check if the record exists
    # https://www.inwx.de/de/help/apidoc/f/ch02s15.html#nameserver.info
    $reqParams = @{}
    $reqParams.Uri = $apiRoot
    $reqParams.Method = "POST"
    $reqParams.ContentType = "application/json"
    $reqParams.WebSession = $INWXSession
    $reqParams.Body = @{
        "jsonrpc" = "2.0";
        "id" = [guid]::NewGuid()
        "method" = "nameserver.info";
        "params" = @{
            "domain" = $zoneName;
            "type" = "TXT";
            "name" = $recShort;
            "content" = $TxtValue;
        };
    } | ConvertTo-Json

    $response = $False
    $responseContent = $False
    $recordIds = $False
    try {
        Write-Verbose "Checking for $RecordName record(s) with value $TxtValue."
        Write-Debug "$($reqParams.Method) $apiRoot`n$($reqParams.Body)"
        $response = Invoke-WebRequest @reqParams @script:UseBasic
    } catch {
        throw "INWX method call $(($reqParams.Body | ConvertFrom-Json).method) failed (unknown error)."
    }
    if ($response -eq $False -or
        $response.StatusCode -ne 200) {
        throw "INWX method call $(($reqParams.Body | ConvertFrom-Json).method) failed (status code $($response.StatusCode))."
    } else {
        $responseContent = $response.Content | ConvertFrom-Json
    }
    Write-Debug "Received content:`n$($response.Content)"

    switch ($responseContent.code) {
        # 1000: Command completed successfully
        # 2302: Object exists
        {($PSItem -eq 1000 -or
          $PSItem -eq 2302)} {
            Write-Debug "INWX method call $(($reqParams.Body | ConvertFrom-Json).method) was successful"
            if ($responseContent.resData.count -gt 0 -and
                $responseContent.resData.record.id) {
                $recordIds = $responseContent.resData.record.id
                if (-not $recordIds -is [array]) {
                    $recordIds = @($recordIds)
                }
                Write-Debug "Found record(s) with ID(s) $recordIds."
            }
        }
        # unexpected
        default {
            throw "Unexpected response from INWX (code: $($responseContent.code)). The plugin might need an update (Remove-DnsTxt)."
        }
    }
    Remove-Variable "reqParams", "response", "responseContent"


    if ($recordIds) {
        foreach ($recordId in $recordIds) {
            Write-Verbose "DNS record is existing, going to delete it."
            # delete record
            # https://www.inwx.de/de/help/apidoc/f/ch02s15.html#nameserver.deleteRecord
            $reqParams = @{}
            $reqParams.Uri = $apiRoot
            $reqParams.Method = "POST"
            $reqParams.ContentType = "application/json"
            $reqParams.WebSession = $INWXSession
            $reqParams.Body = @{
                "jsonrpc" = "2.0";
                "id" = [guid]::NewGuid()
                "method" = "nameserver.deleteRecord";
                "params" = @{
                    "id" = $recordId;
                };
            } | ConvertTo-Json

            $response = $False
            $responseContent = $False
            try {
                Write-Verbose "Deleting record $RecordName with value $TxtValue."
                Write-Debug "$($reqParams.Method) $apiRoot`n$($reqParams.Body)"
                $response = Invoke-WebRequest @reqParams @script:UseBasic
            } catch {
                throw "INWX method call $(($reqParams.Body | ConvertFrom-Json).method) failed (unknown error)."
            }
            if ($response -eq $False -or
                $response.StatusCode -ne 200) {
                throw "INWX method call $(($reqParams.Body | ConvertFrom-Json).method) failed (status code $($response.StatusCode))."
            } else {
                $responseContent = $response.Content | ConvertFrom-Json
            }
            Write-Debug "Received content:`n$($response.Content)"
            # 1000: Command completed successfully
            if ($responseContent.code -eq 1000) {
                Write-Verbose "Deleting the record was successful."
            } else {
                throw "Deleting the record failed (code: $($responseContent.code))."
            }
            Remove-Variable "reqParams", "response", "responseContent"
        }
    } else {
        Write-Debug "Record $RecordName with value $TxtValue doesn't exist. Nothing to do."
    }
    Remove-Variable "recordIds"

    <#
    .SYNOPSIS
        Remove a DNS TXT record from INWX.

    .DESCRIPTION
        Uses the INWX DNS API to remove a DNS TXT record with a certain value.

    .PARAMETER RecordName
        The fully qualified name of the TXT record.

    .PARAMETER TxtValue
        The value of the TXT record.

    .PARAMETER INWXUsername
        The INWX Username to access the API.

    .PARAMETER INWXPassword
        The password belonging to the username provided via -INWXUsername.

    .PARAMETER INWXSharedSecret
        To be implemented, patches welcome (if you are not using 2FA, do not define this parameter).

    .PARAMETER ExtraParams
        This parameter can be ignored and is only used to prevent errors when splatting with more parameters than this function supports.

    .EXAMPLE
        Remove-DnsTxt '_acme-challenge.example.com' 'txt-value'

        Removes a TXT record for the specified site with the specified value.
    #>
}

function Save-DnsTxt {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments)]
        $ExtraParams
    )

    # set communication endpoint
    # production system at: https://api.domrobot.com
    # test system at: https://api.ote.domrobot.com
    $apiRoot = "https://api.domrobot.com/jsonrpc/"

    # There is currently no additional work to be done to save
    # or finalize changes performed by Add/Remove functions.

    # let's logout (best effort)
    # https://www.inwx.de/de/help/apidoc/f/ch02.html#account.logout
    $reqParams = @{}
    $reqParams.Uri = $apiRoot
    $reqParams.Method = "POST"
    $reqParams.ContentType = "application/json"
    $reqParams.WebSession = $INWXSession
    $reqParams.Body = @{
        "jsonrpc" = "2.0";
        "id" = [guid]::NewGuid()
        "method" = "account.logout";
    } | ConvertTo-Json
    $response = $False
    $responseContent = $False
    try {
        Write-Verbose "Starting INWX logout to end the session (best-effort)."
        Write-Debug "$($reqParams.Method) $apiRoot`n$($reqParams.Body)"
        $response = Invoke-WebRequest @reqParams @script:UseBasic
    } catch {
        Write-Debug "INWX method call $(($reqParams.Body | ConvertFrom-Json).method) failed (unknown error)."
    }
    if ($response -eq $False -or
        $response.StatusCode -ne 200) {
        Write-Debug "INWX method call $(($reqParams.Body | ConvertFrom-Json).method) failed (status code $($response.StatusCode))."
    } else {
        $responseContent = $response.Content | ConvertFrom-Json
    }
    Write-Debug "Received content:`n$($response.Content)"
    # 1000: Command completed successfully
    # 1500: Command completed successfully; ending session
    if ($responseContent.code -eq 1000 -or
        $responseContent.code -eq 1500) {
        Write-Verbose "Logout was successful."
    } else {
        Write-Debug "Logout failed (code: $($responseContent.code))."
    }
    Remove-Variable "reqParams", "response", "responseContent"

    # invalidate saved session data
    $script:INWXSession = $False

    <#
    .SYNOPSIS
        Commits changes for pending DNS TXT record modifications to INWX and closes an existing RPC session by logging out.

    .DESCRIPTION
        This function is currently a dummy which just does a clean logout as INWX does not have a "finalize" or "commit" workflow.

    .PARAMETER ExtraParams
        This parameter can be ignored and is only used to prevent errors when splatting with more parameters than this function supports.

    .EXAMPLE
        Save-DnsTxt

        Commits changes for pending DNS TXT record modifications
        and closes an existing RPC session by logging out.
    #>
}


############################
# Helper Functions
############################

# API Docs at https://www.inwx.de/en/help/apidoc
# Result codes at https://www.inwx.de/en/help/apidoc/f/ch04.html
#
# There is also an OT&E test system. It provides the usual WebUI and API using a test
# database. On the OTE system no actions will be charged. So one can test how to
# register domains etc.,# a OT&E account can be created at
# https://www.ote.inwx.de/en/customer/signup

function Connect-INWX {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory,Position=0)]
        [string]$INWXUsername,
        [Parameter(Mandatory,Position=1)]
        [securestring]$INWXPassword,
        [Parameter(Position=2)]
        [AllowNull()]
        [securestring]$INWXSharedSecret,
        [Parameter(ValueFromRemainingArguments)]
        $ExtraConnectParams
    )

    # no need to login again, we already have an authenticated session
    if ((Test-Path 'variable:script:INWXSession') -and ($script:INWXSession)) {
        Write-Debug "Login not needed, using cached INWX session."
        return
    }

    # generate needed OTP
    if ($INWXSharedSecret) {
        # If your account is secured by mobile TAN ("2FA", "2 factor authentication"),
        # you also have to define the shared secret (usually presented below the QR
        # code during mobile TAN setup) to enable this function to generate OTP codes.
        # The shared secret is NOT not the 6 digit code you need to enter when logging
        # in.

        # get shared secret as plaintext
        # $INWXSharedSecretInsecure = [pscredential]::new('a',$INWXSharedSecret).GetNetworkCredential().Password

        # FIXME to be implemented
        # Propably useful: https://github.com/acmesh-official/acme.sh/blob/master/dnsapi/dns_inwx.sh#L222C4-L263
        throw "Sorry, the INWX Shared Secret / 2FA functionality is not supported yet. Patches are welcome."
    }

    # get password as plaintext
    $INWXPasswordInsecure = [pscredential]::new('a',$INWXPassword).GetNetworkCredential().Password

    # set communication endpoint
    # production system at: https://api.domrobot.com
    # test system at: https://api.ote.domrobot.com
    $apiRoot = "https://api.domrobot.com/jsonrpc/"

    Write-Debug "Starting INWX login to get a session."
    # login
    # https://www.inwx.com/en/help/apidoc/f/ch02.html#account.login
    $reqParams = @{}
    $reqParams.Uri = $apiRoot
    $reqParams.Method = "POST"
    $reqParams.ContentType = "application/json"
    $reqParams.SessionVariable = "INWXSession"
    $reqParams.Body = @{
        "jsonrpc" = "2.0";
        "id" = [guid]::NewGuid()
        "method" = "account.login";
        "params" = @{
            "user" = $INWXUsername;
            "pass" = $INWXPasswordInsecure;
        };
    } | ConvertTo-Json

    $response = $False
    $responseContent = $False
    try {
        $response = Invoke-WebRequest @reqParams @script:UseBasic
    } catch {
        throw "INWX method call $(($reqParams.Body | ConvertFrom-Json).method) failed (unknown error)"
    }
    if ($response -eq $False -or
        $response.StatusCode -ne 200) {
        throw "INWX method call $(($reqParams.Body | ConvertFrom-Json).method) failed (status code $($response.StatusCode))."
    } else {
        $responseContent = $response.Content | ConvertFrom-Json
    }
    Write-Debug "Received content:`n$($response.Content)"

    switch ($responseContent.code) {
        # 1000: Command completed successfully
        1000 {
            Write-Verbose "INWX login was successful."
        }

        # 2200: Authentication error
        # 2400: Command failed
        {$PSItem -eq 2200 -or
         $PSItem -eq 2400} {
            Write-Verbose "INWX login failed."
        }
        # unexpected
        default {
            throw "Unexpected response from INWX (code: $($responseContent.code)). The plugin might need an update (Connect-INWX)."
        }
    }
    Remove-Variable "reqParams", "response", "responseContent"

    # save the session variable for usage in all later calls
    $script:INWXSession = $INWXSession

    <#
    .SYNOPSIS
        Internal helper function to create a session ("login") to communicate with the INWX API.

    .PARAMETER INWXUsername
        The INWX Username to access the API.

    .PARAMETER INWXPassword
        The password belonging to the username provided via -INWXUsername.

    .PARAMETER INWXSharedSecret
        To be implemented, patches welcome (if you are not using 2FA, do not define this parameter).


    .PARAMETER ExtraParams
        This parameter can be ignored and is only used to prevent errors when splatting with more parameters than this function supports.
    #>
}


function Find-INWXZone {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory,Position=0)]
        [string]$RecordName
    )

    # setup a module variable to cache the record to zone mapping
    # so it's quicker to find later
    if (!(Test-Path 'variable:script:INWXRecordZones')) {
        $script:INWXRecordZones = @{}
    }

    # check for the record in the cache
    if ($script:INWXRecordZones.ContainsKey($RecordName)) {
        return $script:INWXRecordZones.$RecordName
    }

    # set communication endpoint
    # production system at: https://api.domrobot.com
    # test system at: https://api.ote.domrobot.com
    $apiRoot = "https://api.domrobot.com/jsonrpc/"

    # Since the provider could be hosting both apex and sub-zones, we need to find the closest/deepest
    # sub-zone that would hold the record rather than just adding it to the apex. So for something
    # like _acme-challenge.site1.sub1.sub2.example.com, we'd look for zone matches in the following
    # order:
    # - site1.sub1.sub2.example.com
    # - sub1.sub2.example.com
    # - sub2.example.com
    # - example.com

    $pieces = $RecordName.Split('.')
    for ($i=0; $i -lt ($pieces.Count-1); $i++) {
        $zoneTest = $pieces[$i..($pieces.Count-1)] -join '.'

        # check if the part of the domain is the zone
        # https://www.inwx.de/de/help/apidoc/f/ch02s15.html#nameserver.info
        $reqParams = @{}
        $reqParams.Uri = $apiRoot
        $reqParams.Method = "POST"
        $reqParams.ContentType = "application/json"
        $reqParams.WebSession = $INWXSession
        $reqParams.Body = @{
            "jsonrpc" = "2.0";
            "id" = [guid]::NewGuid()
            "method" = "nameserver.info";
            "params" = @{
                "domain" = $zoneTest;
            };
        } | ConvertTo-Json

        $response = $False
        $responseContent = $False
        try {
            Write-Verbose "Checking if $zoneTest is the zone holding the records."
            Write-Debug "$($reqParams.Method) $apiRoot`n$($reqParams.Body)"
            $response = Invoke-WebRequest @reqParams @script:UseBasic
        } catch {
            throw "INWX method call $(($reqParams.Body | ConvertFrom-Json).method) failed (unknown error)."
        }
        if ($response -eq $False -or
            $response.StatusCode -ne 200) {
            throw "INWX method call $(($reqParams.Body | ConvertFrom-Json).method) failed (status code $($response.StatusCode))."
        } else {
            $responseContent = $response.Content | ConvertFrom-Json
        }
        Write-Debug "Received content:`n$($response.Content)"

        switch ($responseContent.code) {
            # 1000: Command completed successfully
            # 2302: Object exists
            {$PSItem -eq 1000 -or
             $PSItem -eq 2302} {
                Write-Verbose "$zoneTest seems to be the zone holding the records."
                $script:INWXRecordZones.$RecordName = $zoneTest
                return $zoneTest
                break
            }
            # 2303: Object does not exist
            2303 {
                Write-Debug "$zoneTest does not seem to be the zone holding the records, trying next deeper match."
            }
            # unexpected
            default {
                throw "Unexpected response from INWX (code: $($responseContent.code)). The plugin might need an update (Find-INWXZone)."
            }
        }
        Remove-Variable "reqParams", "response", "responseContent"
    }

    throw "Unable to find zone matching $RecordName."

    <#
    .SYNOPSIS
        Internal helper function to figure out which zone $RecordName needs to be added to.

    .PARAMETER RecordName
        The DNS Resource Record of which to find the belonging DNS zone.
    #>
}
