# Version: v1.1 - 2026-02-19
param(
  [string]$Org = "dev",
  [int]$WaitSeconds = 10,
  [string]$LeadSource = "Web"
)

$ts = [DateTime]::UtcNow.ToString("HHmmss")
$TestEmail = "tesellwood+flowall$ts@gmail.com"

Write-Host "Creating Lead to trigger ALL active Lead On-Create flows..."
Write-Host "Org=$Org Email=$TestEmail"

function Show-JsonTable($jsonText) {
  try {
    $o = $jsonText | ConvertFrom-Json
    if ($o.status -ne 0) { $o | ConvertTo-Json -Depth 6; return }
    $o.result.records | Format-Table -AutoSize | Out-Host
  } catch {
    $jsonText | Out-Host
  }
}

# 0) Active Flow snapshot (Tooling API) - works when FlowDefinitionView doesn't
Write-Host "`n=== Active Flow Snapshot (Tooling API: FlowDefinition + Latest Flow Version) ==="
# FlowDefinition has active version id; Flow has version details. We'll show definitions first.
$fdJson = sf data query -o $Org --use-tooling-api -q "
SELECT Id, DeveloperName, ActiveVersionId
FROM FlowDefinition
WHERE DeveloperName LIKE '%Lead%' OR DeveloperName LIKE '%DocuSign%' OR DeveloperName LIKE '%Docusign%' OR DeveloperName LIKE '%Email%'
ORDER BY DeveloperName
" --json
Show-JsonTable $fdJson

# If ActiveVersionId is present, show the actual active Flow versions
Write-Host "`n=== Active Flow Versions (Tooling API: Flow) ==="
$fJson = sf data query -o $Org --use-tooling-api -q "
SELECT Id, Definition.DeveloperName, VersionNumber, Status, ProcessType, LastModifiedDate
FROM Flow
WHERE Status = 'Active'
AND (Definition.DeveloperName LIKE '%Lead%' OR Definition.DeveloperName LIKE '%DocuSign%' OR Definition.DeveloperName LIKE '%Docusign%' OR Definition.DeveloperName LIKE '%Email%')
ORDER BY Definition.DeveloperName
" --json
Show-JsonTable $fJson

# 1) Create the Lead (single trigger point)
$createJson = sf data record create -o $Org -s Lead -v "FirstName=Test LastName=FlowAll Company=TestCo LeadSource=$LeadSource Email=$TestEmail" --json
$create = $createJson | ConvertFrom-Json
if ($create.status -ne 0) { Write-Error "Lead create failed: $($create.message)"; exit 1 }
$LeadId = $create.result.id
Write-Host "`nCreated LeadId=$LeadId"

# 2) Wait for downstream automations
Write-Host "`nWaiting $WaitSeconds seconds..."
Start-Sleep -Seconds $WaitSeconds

# 3) Lead debug state
Write-Host "`n=== Lead Debug State ==="
$leadJson = sf data query -o $Org -q "
SELECT Id, Email, LeadSource, Status, Description,
       DocuSign_Email_Sent__c, DocuSign_Approved__c,
       Contact_Form_Completed__c, Company_Form_Completed__c,
       CreatedDate, LastModifiedDate
FROM Lead
WHERE Id = '$LeadId'
LIMIT 1
" --json
Show-JsonTable $leadJson

# 4) DocuSign envelope(s) for this Lead
Write-Host "`n=== DocuSign Envelope(s) for this Lead ==="
$envJson = sf data query -o $Org -q "
SELECT Id, Name, CreatedDate, dfsle__SourceId__c, dfsle__EnvelopeConfiguration__c
FROM dfsle__Envelope__c
WHERE dfsle__SourceId__c = '$LeadId'
ORDER BY CreatedDate DESC
LIMIT 20
" --json
Show-JsonTable $envJson

# 5) Recent envelopes sanity check
Write-Host "`n=== Most Recent DocuSign Envelopes (sanity check) ==="
$envRecentJson = sf data query -o $Org -q "
SELECT Id, Name, CreatedDate, dfsle__SourceId__c, dfsle__EnvelopeConfiguration__c
FROM dfsle__Envelope__c
ORDER BY CreatedDate DESC
LIMIT 10
" --json
Show-JsonTable $envRecentJson

Write-Host "`nDONE. LeadId=$LeadId Email=$TestEmail"
Write-Host "Interpretation:"
Write-Host "- If Lead.Description contains EMAIL_SENT / DOCUSIGN_SENT markers: flow stamped success."
Write-Host "- If dfsle__Envelope__c returns rows for this LeadId: DocuSign trigger is working."
Write-Host "- If Description contains EMAIL_ALERT_FAULT Recipient: your Email Alert template is still broken."
