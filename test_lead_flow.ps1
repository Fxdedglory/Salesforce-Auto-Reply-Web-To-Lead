# Version: v1.1 - 2026-02-18
$TestEmail = "tesellwood+resume$([DateTime]::UtcNow.ToString('HHmmss'))@gmail.com"
Write-Host "Creating test lead for flow trigger: $TestEmail"

sf data create record `
  --sobject Lead `
  --values "FirstName=Test LastName=Resume Email=$TestEmail Company=TestCo LeadSource=Web"

sf data query -q "
SELECT Id, Email, Description, CreatedDate
FROM Lead
WHERE Email='$TestEmail'
ORDER BY CreatedDate DESC
LIMIT 1
"
