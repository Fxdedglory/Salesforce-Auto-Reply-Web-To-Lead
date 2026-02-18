# Version: v1.0 - 2026-02-18
$TestEmail = "tesellwood+resume$([DateTime]::UtcNow.ToString('HHmmss'))@gmail.com"
Write-Host "Creating test lead for flow trigger: $TestEmail"

sf data record create -o $Org -s Lead -v "FirstName=Test LastName=Resume Email=$TestEmail Company=TestCo LeadSource=Web"

sf data query -o $Org -q "
SELECT Id, Email, Description, CreatedDate
FROM Lead
WHERE Email='$TestEmail'
ORDER BY CreatedDate DESC
LIMIT 1
"
