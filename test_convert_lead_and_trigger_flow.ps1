# test_convert_lead_and_trigger_flow.ps1
# v0.5.2 | 2026-02-17
<#
PURPOSE (Visible Debug / CRM Narrative)
--------------------------------------
This script forces a realistic CRM lifecycle so your Flow can safely create Tasks:

- BEFORE conversion: Lead tasks (WhoId=LeadId) are allowed, but MUST NOT have WhatId=Opportunity.
- AFTER conversion: Opportunity tasks must use WhoId=ContactId and WhatId=OpportunityId.

This script PROVES whether your Flow violates the platform rule by triggering it with a Lead + Opportunity present.

KEY PLATFORM RULE
-----------------
You cannot create Task(WhoId=LeadId, WhatId=OpportunityId).
Salesforce throws: FIELD_INTEGRITY_EXCEPTION: cannot specify whatID with lead whoID

WHAT THIS SCRIPT DOES
---------------------
A) Create Lead
B) Convert Lead via Anonymous Apex (Database.convertLead) -> Account + Contact
C) Create Opportunity under Account
D) Update dfsle__EnvelopeStatus__c with Lead + Opportunity and toggle Status to trigger Flow
E) Query Tasks since $since to validate what the Flow created

#>

param(
    [string]$Org = "demo",
    [string]$EnvId = "a0GgK000007sN8TUAU",
    [int]$LookbackMinutes = 15,

    [string]$LeadEmail = "",
    [string]$LeadFirstName = "Tim",
    [string]$LeadLastName = "Sellwood",
    [string]$Company = "TE Emails Demo Co",

    [string]$OppName = "Demo DocuSign Opportunity",
    [decimal]$OppAmount = 5000
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([Parameter(Mandatory=$true)][string]$Msg)
    Write-Host ""
    Write-Host ("=== {0} ===" -f $Msg) -ForegroundColor Cyan
}

function Assert-Tool {
    param([Parameter(Mandatory=$true)][string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required tool not found on PATH: $Name"
    }
}

function Escape-SfValue {
    param([Parameter(Mandatory=$true)][string]$Value)
    return ($Value -replace "'", "''")
}

function KV {
    param(
        [Parameter(Mandatory=$true)][string]$Key,
        [Parameter(Mandatory=$true)][AllowNull()][string]$Value
    )
    if ($null -eq $Value) { $Value = "" }
    $v = Escape-SfValue $Value
    return ("{0}='{1}'" -f $Key, $v)
}

function KVNum {
    param(
        [Parameter(Mandatory=$true)][string]$Key,
        [Parameter(Mandatory=$true)][string]$Value
    )
    return ("{0}={1}" -f $Key, $Value)
}

function Sf-Json {
    param([Parameter(Mandatory=$true)][string[]]$Args)

    $out = & sf @Args --json 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "sf failed ($LASTEXITCODE):`n$out"
    }
    return ($out | ConvertFrom-Json)
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Text
    )
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $utf8NoBom)
}

function Sf-ApexRun {
    param([Parameter(Mandatory=$true)][string]$ApexBody)

    $tmp = Join-Path $env:TEMP ("lead_convert_{0}.apex" -f ([Guid]::NewGuid().ToString("N")))
    Write-Utf8NoBom -Path $tmp -Text $ApexBody

    $out = & sf apex run --target-org $Org --file $tmp 2>&1
    $code = $LASTEXITCODE

    Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue | Out-Null

    if ($code -ne 0) {
        throw "sf apex run failed ($code):`n$out"
    }

    return $out
}

function Fix-Mojibake {
    <#
    Some terminals show smart quotes as ΓÇ£ / ΓÇ¥ etc due to encoding mismatch.
    This attempts a best-effort fix for readability.
    #>
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $Text }
    try {
        $bytes = [System.Text.Encoding]::GetEncoding(1252).GetBytes($Text)
        return [System.Text.Encoding]::UTF8.GetString($bytes)
    } catch {
        return $Text
    }
}

function Try-SfUpdateEnvelope {
    param(
        [Parameter(Mandatory=$true)][string]$ValuesString,
        [Parameter(Mandatory=$true)][string]$Label
    )

    try {
        Sf-Json @(
            'data','record','update',
            '--target-org', $Org,
            '--sobject', 'dfsle__EnvelopeStatus__c',
            '--record-id', $EnvId,
            '--values', $ValuesString
        ) | Out-Null

        Write-Host ("SUCCESS: {0}" -f $Label)
        return $true
    }
    catch {
        $msg = $_.Exception.Message
        $pretty = Fix-Mojibake $msg

        Write-Host ""
        Write-Host "=== FLOW TRIGGER FAILED (expected if Flow is wrong) ===" -ForegroundColor Yellow
        Write-Host $pretty
        Write-Host ""
        Write-Host "DIAGNOSIS:" -ForegroundColor Yellow
        Write-Host " - Your Flow attempted to create a Task with WhoId=Lead AND WhatId=Opportunity."
        Write-Host " - That is not allowed by Salesforce: cannot specify whatID with lead whoID."
        Write-Host ""
        Write-Host "FLOW FIX (in the Opportunity branch):" -ForegroundColor Yellow
        Write-Host " - Set Task.WhoId to Lead.ConvertedContactId (or another ContactId)"
        Write-Host " - Keep Task.WhatId = OpportunityId"
        Write-Host " - Do NOT use LeadId as WhoId when WhatId is an Opportunity."
        Write-Host ""
        return $false
    }
}

# -----------------------------
# Pre-flight
# -----------------------------
Assert-Tool "sf"

# -----------------------------
# 0) Time window
# -----------------------------
$since = (Get-Date).ToUniversalTime().AddMinutes(-$LookbackMinutes).ToString("yyyy-MM-ddTHH:mm:ss.000Z")

Write-Step ("0) Setup: We'll query Tasks created since UTC {0}" -f $since)
Write-Host "CRM Narrative:"
Write-Host " - We'll follow Lead -> Convert -> Account+Contact -> Opportunity."
Write-Host " - Then we simulate DocuSign via dfsle__EnvelopeStatus__c updates to trigger your Flow."
Write-Host " - Finally we query Tasks created by the Flow for validation."

# -----------------------------
# 1) Create Lead
# -----------------------------
if ([string]::IsNullOrWhiteSpace($LeadEmail)) {
    $stamp = (Get-Date).ToString("HHmmss")
    $LeadEmail = "tesellwood+flow$stamp@gmail.com"
}

Write-Step "1) Create Lead (pre-customer)"
Write-Host "CRM Narrative:"
Write-Host " - A Lead is an unqualified prospect record (person + company)."
Write-Host " - BEFORE conversion: Tasks can be WhoId=LeadId (no Opportunity WhatId allowed)."
Write-Host ("Creating Lead with Email = {0}" -f $LeadEmail)

$leadValues = @(
    (KV 'FirstName' $LeadFirstName),
    (KV 'LastName'  $LeadLastName),
    (KV 'Company'   $Company),
    (KV 'Email'     $LeadEmail)
) -join ' '

$leadCreate = Sf-Json @(
    'data','record','create',
    '--target-org', $Org,
    '--sobject', 'Lead',
    '--values', $leadValues
)

$leadId = $leadCreate.result.id
Write-Host ("Created LeadId = {0}" -f $leadId)

$leadSoql1 = "SELECT Id, IsConverted, ConvertedContactId, ConvertedAccountId FROM Lead WHERE Id='$leadId'"
$leadCheck1 = Sf-Json @('data','query','--target-org',$Org,'--query',$leadSoql1)
$leadRow1 = $leadCheck1.result.records[0]
Write-Host ("Lead IsConverted = {0}, ConvertedContactId = {1}, ConvertedAccountId = {2}" -f $leadRow1.IsConverted, $leadRow1.ConvertedContactId, $leadRow1.ConvertedAccountId)

# -----------------------------
# 2) Convert Lead via Apex
# -----------------------------
Write-Step "2) Convert Lead (Apex) -> Account + Contact"
Write-Host "CRM Narrative:"
Write-Host " - Conversion creates the Account + Contact (customer entities)."
Write-Host " - AFTER conversion: Opportunity Tasks should use WhoId=Contact + WhatId=Opportunity."

$statusSoql = "SELECT MasterLabel FROM LeadStatus WHERE IsConverted = true ORDER BY SortOrder LIMIT 1"
$statuses = Sf-Json @('data','query','--target-org',$Org,'--query',$statusSoql)
if (-not $statuses.result.records -or $statuses.result.records.Count -lt 1) {
    throw "Could not find a converted LeadStatus (LeadStatus.IsConverted=true)."
}
$convertedStatus = $statuses.result.records[0].MasterLabel
Write-Host ("Using Converted Status = '{0}'" -f $convertedStatus)

$apex = @"
Database.LeadConvert lc = new Database.LeadConvert();
lc.setLeadId('$leadId');
lc.setConvertedStatus('$convertedStatus');
lc.setDoNotCreateOpportunity(true);

Database.LeadConvertResult res = Database.convertLead(lc);
if (!res.isSuccess()) {
    System.assert(false, 'LeadConvert failed: ' + res);
}
System.debug('LEAD_CONVERT_SUCCESS AccountId=' + res.getAccountId() + ' ContactId=' + res.getContactId());
"@

Write-Host "Running conversion via: sf apex run (Anonymous Apex Database.convertLead)"
Sf-ApexRun -ApexBody $apex | Out-Null

$leadSoql2 = "SELECT Id, IsConverted, ConvertedContactId, ConvertedAccountId FROM Lead WHERE Id='$leadId'"
$leadCheck2 = Sf-Json @('data','query','--target-org',$Org,'--query',$leadSoql2)
$leadRow2 = $leadCheck2.result.records[0]

$acctId    = $leadRow2.ConvertedAccountId
$contactId = $leadRow2.ConvertedContactId

Write-Host ("Post-Convert Lead IsConverted = {0}, ConvertedAccountId = {1}, ConvertedContactId = {2}" -f $leadRow2.IsConverted, $acctId, $contactId)

# -----------------------------
# 3) Create Opportunity
# -----------------------------
Write-Step "3) Create Opportunity (deal) under the converted Account"
Write-Host "CRM Narrative:"
Write-Host " - Opportunities represent revenue pipeline and belong to Accounts."
Write-Host " - Task.WhatId should point to the Opportunity."
Write-Host " - Task.WhoId should point to the Contact (NOT the Lead)."

$stageSoql = "SELECT MasterLabel FROM OpportunityStage ORDER BY SortOrder LIMIT 1"
$stageQuery = Sf-Json @('data','query','--target-org',$Org,'--query',$stageSoql)
$stageName = $stageQuery.result.records[0].MasterLabel
$closeDate = (Get-Date).AddDays(14).ToString("yyyy-MM-dd")

Write-Host ("Using StageName='{0}', CloseDate={1}, Amount={2}" -f $stageName, $closeDate, $OppAmount)

$oppValues = @(
    (KV 'Name'      $OppName),
    (KV 'AccountId' $acctId),
    (KV 'StageName' $stageName),
    (KV 'CloseDate' $closeDate),
    (KVNum 'Amount' ([string]$OppAmount))
) -join ' '

$oppCreate = Sf-Json @(
    'data','record','create',
    '--target-org', $Org,
    '--sobject', 'Opportunity',
    '--values', $oppValues
)
$oppId = $oppCreate.result.id
Write-Host ("Created OpportunityId = {0}" -f $oppId)

# -----------------------------
# 4) Trigger Flow
# -----------------------------
Write-Step "4) Trigger Flow via dfsle__EnvelopeStatus__c updates"
Write-Host "CRM Narrative:"
Write-Host " - DocuSign updates Envelope Status records."
Write-Host " - Your Flow listens to those updates and creates Tasks / updates Lead status."
Write-Host "Platform rule reminder:"
Write-Host " - NEVER create Task(WhoId=Lead, WhatId=Opportunity)."
Write-Host (" - For Opp branch: use WhoId=ContactId ({0}) + WhatId=OppId ({1})" -f $contactId, $oppId)

$envValues1 = @(
    (KV 'dfsle__Lead__c'        $leadId),
    (KV 'dfsle__Opportunity__c' $oppId),
    (KV 'dfsle__Status__c'      'Declined')
) -join ' '

$ok1 = Try-SfUpdateEnvelope -ValuesString $envValues1 -Label "EnvelopeStatus set Lead+Opp+Declined"

if ($ok1) {
    $envValues2 = (KV 'dfsle__Status__c' 'Completed')
    $null = Try-SfUpdateEnvelope -ValuesString $envValues2 -Label "EnvelopeStatus set Completed"
}

# -----------------------------
# 5) Query tasks (even if flow failed)
# -----------------------------
Write-Step ("5) Query Tasks created by Flow (since {0})" -f $since)
Write-Host "CRM Narrative: Expectations"
Write-Host (" - Opportunity-related Tasks should be WhatId={0} and WhoId={1} (Contact)" -f $oppId, $contactId)
Write-Host (" - Lead-only Tasks should be WhoId={0} (Lead) and WhatId blank" -f $leadId)

$taskSoql = "SELECT Id, Subject, WhoId, WhatId, CreatedDate, Description FROM Task WHERE CreatedDate >= $since AND Subject LIKE '[DocuSign]%' ORDER BY CreatedDate DESC LIMIT 50"
$taskRows = Sf-Json @('data','query','--target-org',$Org,'--query',$taskSoql)
$tasks = $taskRows.result.records

if (-not $tasks -or $tasks.Count -eq 0) {
    Write-Host "No matching tasks found in the window." -ForegroundColor Yellow
    Write-Host "Try increasing -LookbackMinutes or confirm Flow entry criteria."
} else {
    Write-Host ("Found {0} Task(s) in window:" -f $tasks.Count)
    $tasks | Select-Object Id, Subject, WhoId, WhatId, CreatedDate | Format-Table -AutoSize
}

# -----------------------------
# 6) Output IDs
# -----------------------------
Write-Step "6) Output IDs (for click-through debugging)"
Write-Host ("LeadId      = {0}" -f $leadId)
Write-Host ("AccountId   = {0}" -f $acctId)
Write-Host ("ContactId   = {0}" -f $contactId)
Write-Host ("OppId       = {0}" -f $oppId)
Write-Host ("EnvStatusId = {0}" -f $EnvId)
Write-Host ""
Write-Host "Done."
