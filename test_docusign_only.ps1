# Version: v1.0 - 2026-02-19
param(
  [string]$Org = "dev",
  [int]$WaitSeconds = 20
)

$email = "tesellwood+docusign$([DateTime]::UtcNow.ToString('HHmmss'))@gmail.com"
Write-Host "Creating Lead to test DocuSign only..."
Write-Host "Org=$Org Email=$email"

# Create a Lead that matches your start criteria (LeadSource=Web, Email not null)
$create = sf data record create -o $Org -s Lead -v "FirstName=Test LastName=DocuSign Company=TestCo LeadSource=Web Email=$email" --json | ConvertFrom-Json
if ($create.status -ne 0) { throw ($create.message) }
$leadId = $create.result.id
Write-Host "Created LeadId=$leadId"

Write-Host "Waiting $WaitSeconds seconds..."
Start-Sleep -Seconds $WaitSeconds

Write-Host "`n=== Lead Debug Breadcrumbs (Description) ==="
sf data query -o $Org -q "
SELECT Id, Email, LeadSource, Status, Description, CreatedDate, LastModifiedDate
FROM Lead
WHERE Id = '$leadId'
" 

Write-Host "`n=== DocuSign Envelopes for this Lead (dfsle__SourceId__c) ==="
sf data query -o $Org -q "
SELECT Id, Name, CreatedDate, dfsle__SourceId__c, dfsle__EnvelopeConfiguration__c
FROM dfsle__Envelope__c
WHERE dfsle__SourceId__c = '$leadId'
ORDER BY CreatedDate DESC
LIMIT 20
"

Write-Host "`n=== Most Recent Envelopes (sanity) ==="
sf data query -o $Org -q "
SELECT Id, Name, CreatedDate, dfsle__SourceId__c, dfsle__EnvelopeConfiguration__c
FROM dfsle__Envelope__c
ORDER BY CreatedDate DESC
LIMIT 10
"

Write-Host "`nDONE. LeadId=$leadId Email=$email"
Write-Host "Interpretation:"
Write-Host "- If Lead.Description contains DOCUSIGN_SENT: Flow call executed successfully."
Write-Host "- If Lead.Description contains DOCUSIGN_FAULT: fix message after '| ERROR='."
Write-Host "- If dfsle__Envelope__c has rows for dfsle__SourceId__c=${leadId}: envelope creation worked."
