````md
# Salesforce Auto Reply Web-to-Lead (Resume Attachment + Lead Notification)

This project implements a **reusable, template-driven** Salesforce automation system you can use to blast high-quality outbound email alerts to new Leads (or any Lead dataset) with **consistent testing + debugging**.

It supports:

1) **Auto-sends a templated email to new Leads** (e.g., `LeadSource=Web`)
2) **Attaches a PDF from Salesforce Files** (by `ContentDocumentId`)
3) **Optional internal notification** when a new Lead is created (email to you)
4) A **single-command test runner**: `test_lead_flow.ps1`

**Primary goal:** reuse the same Apex + Flow pattern to add **lots of email templates**, **lots of variants**, and iterate quickly while keeping the system stable and easy to debug.

---

## Quick Start (Run the Whole System)

From the project root:

```powershell
cd E:\Salesforce
.\test_lead_flow.ps1
````

Expected:

* Lead record is created
* `Lead.Description` shows a debug status (example: `EMAIL_SENT | LeadId=...`)
* Recipient receives the email **with the resume PDF attached**
* (Optional) you receive a separate internal notification email when the Lead is created

---

## What This Repo Does

### When a Lead is created (Web-to-Lead)

* A record-triggered Flow runs on Lead **After Create**
* It calls an Apex Invocable Action that:

  * sends a Salesforce Email Template to the Lead
  * uses an Org-Wide “From” address
  * attaches the **latest** version of a File stored in Salesforce Files (ContentVersion) by `ContentDocumentId`
  * sends the email via `Messaging.sendEmail()`

### You also (optionally) receive a notification email

* A Flow “Send Email” node can send an internal alert to `sellwood.timm@gmail.com`
* The body includes Lead details (name/email/company/source/time/id)

---

## Core Design Principles (Reusability + Maintainability)

### 1) Template-driven system

* Email content lives in Salesforce **Email Templates**
* You can add dozens of templates for different campaigns:

  * “Resume + Calendly”
  * “Portfolio Outreach”
  * “Recruiter Follow-up”
  * “Event Attendee Follow-up”
  * “Cold Outreach Variant A/B/C”
* Each campaign/variant = a new EmailTemplate + (optionally) a new Flow that points at it.

### 2) One Apex action reused everywhere

`LeadResumeEmailAction` is deliberately generic:

* Lead recipient
* Any EmailTemplate (by Id)
* Any File attachment (by ContentDocumentId)
* Any Org-Wide “From” address (by email address)

This means:

* You do **not** rewrite Apex to create new campaigns
* You reuse the same, proven “send template + attach file” implementation

### 3) Single-command test + predictable debug signals

* One script: `test_lead_flow.ps1`
* One debug surface: `Lead.Description`

You can test rapidly, and if something breaks you immediately see:

* `STARTED`
* `CALLING_EMAIL`
* `EMAIL_SENT`
* `EMAIL_FAULT | ERROR=...`

This makes it safe to add lots of templates/flows without losing confidence.

---

## Architecture (High-Level)

**Active Flow (Primary):** `Lead Email - Resume Attachment (On Create)`

```
Start (Lead Created, After Save)
↓
Assign_Init (Debug STARTED)
↓
Update_Debug_Started (writes to Lead.Description)
↓
Assign_Email_Sending (Debug CALLING_EMAIL)
↓
Update_Debug_Before_Send
↓
Send_Resume_Email_1  (Apex: LeadResumeEmailAction)
↓
Assign_Email_Sent  OR  Assign_Email_Fault
↓
Update_Debug_Final
```

**Apex Invocable Action:** `LeadResumeEmailAction`

* Inputs:

  * `leadId` (Lead Id `00Q…`)
  * `emailTemplateId` (EmailTemplate Id `00X…`)
  * `orgWideFromAddress` (e.g., `tim@teemails.com`)
  * `contentDocumentId` (ContentDocument Id `069…`)
* Behavior:

  * queries latest `ContentVersion` by `ContentDocumentId`
  * attaches `VersionData` as a `Messaging.EmailFileAttachment`
  * sends email with `Messaging.sendEmail()`

---

## Repo Layout (Where Things Are)

### Source of truth (what you edit + deploy)

* `force-app/main/default/classes/`

  * `LeadResumeEmailAction.cls`
    Apex invocable action used by Flows to send template + attachment
* `force-app/main/default/flows/`

  * `Lead_Email_ResumeAttachment_OnCreate.flow-meta.xml`
    Primary production flow (Lead created → send email with attachment)
* `force-app/main/default/email/`

  * `Leads/<Template>.email` (HTML body)
  * `Leads/<Template>.email-meta.xml` (metadata)

### Test automation (your “one command” validation)

* `test_lead_flow.ps1`

  * Creates a test Lead designed to trigger your Flow
  * Queries the Lead back to show `Description` debug output
  * This is the **only** script required for end-to-end testing

### Non-source deploy artifacts (should be ignored)

* `mdapi_deploy_*`
* `*.zip`
  These are historical packaging artifacts and should not be used as source-of-truth.

---

## Prerequisites

* Salesforce CLI installed (`sf`)
* Authenticated org set in PowerShell as `$Org` (alias or username)
* Org-Wide Email Address exists for your sender (example):

  * `tim@teemails.com`

---

## Configuration Values (IDs You’ll Reuse)

You can store these in the Flow inputs (recommended), and optionally mirror them in `test_lead_flow.ps1` to print them during debugging.

### 1) EmailTemplate Id (`00X…`)

Query:

```powershell
sf data query -o $Org -q "SELECT Id, Name, DeveloperName, FolderName FROM EmailTemplate ORDER BY LastModifiedDate DESC LIMIT 20"
```

### 2) Resume `ContentDocumentId` (`069…`)

Query:

```powershell
sf data query -o $Org -q "
SELECT Id, Title, FileType, ContentDocumentId, VersionNumber, CreatedDate
FROM ContentVersion
WHERE Title LIKE '%Resume%'
ORDER BY CreatedDate DESC
LIMIT 10
"
```

Use the `ContentDocumentId` (069…).

### 3) Org-Wide Email Address

Query:

```powershell
sf data query -o $Org -q "SELECT Id, Address, DisplayName, IsAllowAllProfiles FROM OrgWideEmailAddress ORDER BY Address"
```

---

## How to Modify Email Wording (Template Editing)

You have two options:

### Option A — Modify in Salesforce Setup (UI)

Setup → Email Templates → open the template → edit Subject/Body

### Option B — Modify in this repo (recommended for versioning)

Edit:

* `force-app/main/default/email/Leads/<Template>.email`
* `force-app/main/default/email/Leads/<Template>.email-meta.xml`

Deploy:

```powershell
sf project deploy start -o $Org -m "EmailTemplate:Leads/<DeveloperName>"
```

---

## How to Add Lots of Templates (Campaign / Variant System)

This is the recommended reusable pattern for scaling to many templates:

### Pattern A (Recommended): One Flow, switch template via criteria

Use one “router” flow that:

* checks Lead fields (LeadSource, Company, Campaign tag, etc.)
* chooses which EmailTemplateId + ContentDocumentId to send

Pros:

* fewer flows to maintain
* centralized debugging

Cons:

* your flow becomes a “dispatcher” (still manageable)

### Pattern B: One Flow per campaign/variant

For each campaign:

* create a new EmailTemplate
* clone the base flow
* update just action inputs (template id + attachment id)
* deploy
* test with `test_lead_flow.ps1`

Pros:

* very easy mental model
* isolated changes

Cons:

* many flows in the org (clutter if you go wild)

---

## Adding a New Email Template + Flow (Reusable Pattern)

### Step 1 — Create/Clone a new EmailTemplate

Add to:

* `force-app/main/default/email/Leads/`

Deploy:

```powershell
sf project deploy start -o $Org -m "EmailTemplate:Leads/<YourTemplateDeveloperName>"
```

### Step 2 — Clone the flow

Copy:

* `force-app/main/default/flows/Lead_Email_ResumeAttachment_OnCreate.flow-meta.xml`

Rename (file name + internal `<label>` and API name):

* `Lead_Email_<CampaignName>_OnCreate.flow-meta.xml`

### Step 3 — Update only the Apex Action inputs

Inside the flow’s Apex Action call:

* `emailTemplateId = <new 00X...>`
* `contentDocumentId = <new 069...>` (optional)
* `orgWideFromAddress = tim@teemails.com`

Deploy:

```powershell
sf project deploy start -o $Org -d "force-app/main/default/flows"
```

### Step 4 — Validate with one command

```powershell
.\test_lead_flow.ps1
```

---

## How to Swap the Attached Resume (New File)

Upload a new resume PDF to Salesforce Files, then update the Flow input:

* `contentDocumentId = <new 069...>`

Verify latest version:

```powershell
$Doc="069xxxxxxxxxxxxxxx"
sf data query -o $Org -q "
SELECT Id, Title, ContentSize, FileType, VersionNumber, CreatedDate
FROM ContentVersion
WHERE ContentDocumentId = '$Doc'
ORDER BY VersionNumber DESC
LIMIT 1
"
```

---

## Internal Notification (Email Me When a Lead Is Created)

You confirmed this is already working and you received:

> “New Lead Created: Tim Sellwood ([tesellwood5230@gmail.com](mailto:tesellwood5230@gmail.com))”

Recommended implementation:

* Add a “Send Email” action node inside the **same active flow** (`Lead Email - Resume Attachment (On Create)`)

**Send Email action inputs:**

* Recipient Addresses: `sellwood.timm@gmail.com`
* Sender Type: `OrgWideEmailAddress`
* Sender Email Address: `tim@teemails.com`
* Subject:

  * `New Lead Created: {!$Record.FirstName} {!$Record.LastName} ({!$Record.Email})`
* Body:

  * Name: `{!$Record.FirstName} {!$Record.LastName}`
  * Email: `{!$Record.Email}`
  * Company: `{!$Record.Company}`
  * Lead Source: `{!$Record.LeadSource}`
  * Created: `{!$Record.CreatedDate}`
  * Lead Id: `{!$Record.Id}`

Placement:

* **before** resume send = you get notified even if attachment send fails
* **after** resume send = notification implies success

---

## Testing & Debugging Workflow (Best Practice)

### 1) Always test with the same command

```powershell
.\test_lead_flow.ps1
```

### 2) Always verify the debug status in Lead.Description

If anything fails, you’ll see `EMAIL_FAULT | ERROR=...`

### 3) If a new template/flow is added:

* deploy template
* deploy flow
* run test script
* confirm:

  * resume email arrives w/ attachment
  * internal notification arrives (if enabled)

---

## Troubleshooting (Common)

### “Org-Wide Email provided is not valid”

* Your Flow/Apex must use an **Address** that exists in OrgWideEmailAddress
* Verify:

```powershell
sf data query -o $Org -q "SELECT Id, Address FROM OrgWideEmailAddress"
```

* Make sure Flow input matches exactly (e.g., `tim@teemails.com`).

### Lead created but no attachment

* Flow must pass **ContentDocumentId (069...)**, not ContentVersionId (068...)
* Verify ContentVersion exists:

```powershell
$Doc="069..."
sf data query -o $Org -q "
SELECT Id, Title, ContentSize, FileType, VersionNumber
FROM ContentVersion
WHERE ContentDocumentId = '$Doc'
ORDER BY VersionNumber DESC
LIMIT 1"
```

### Debugging quickly

* Debug statuses are written to `Lead.Description`:

  * `STARTED`
  * `CALLING_EMAIL`
  * `EMAIL_SENT`
  * `EMAIL_FAULT | ERROR=...`

---

## Glossary (Salesforce Terms Used Here)

* **Flow (Record-Triggered)**: automation that runs when a record is created/updated
* **Email Template**: subject/body template with merge fields
* **Org-Wide Email Address**: verified sender address usable by automations
* **ContentDocumentId (069...)**: File container id in Salesforce Files
* **ContentVersionId (068...)**: specific version id of a file
* **Apex Invocable Action**: Apex method callable from Flow

---

## Deployment Commands (Cheat Sheet)

Deploy Apex:

```powershell
sf project deploy start -o $Org -d "force-app/main/default/classes"
```

Deploy Flows:

```powershell
sf project deploy start -o $Org -d "force-app/main/default/flows"
```

Deploy Email Templates:

```powershell
sf project deploy start -o $Org -d "force-app/main/default/email"
```

Run end-to-end test:

```powershell
.\test_lead_flow.ps1
```

---

## GitHub “Done” Definition

Per project policy: this project is complete only when the final state is pushed to:
[https://github.com/Fxdedglory/Salesforce-Auto-Reply-Web-To-Lead](https://github.com/Fxdedglory/Salesforce-Auto-Reply-Web-To-Lead)

You’ve got two “this file” candidates in your output:

* **`force-app/main/default/flows/Opp_CRM_Router_AfterSave.flow-meta.xml`** (the real flow)
* **`force-app/main/default/flows/Opp_CRM_Router_AfterSave.flow-meta.xml.localbak_20260218_201714`** (a stray backup artifact that **should NOT** be committed)

I’m going to assume you mean the **real router flow** (`Opp_CRM_Router_AfterSave`), because that’s the orchestrator and it’s what’s generating your `[SF_Log_Run] ... MILESTONE_ROUTER_FIRED` tasks.

Below is (A) what it impacts / connects to, (B) the exact PowerShell commands to prove it from your repo, and (C) a README you can paste that documents “how to use this system next time” + “how to get any info you need”.

---

# A) What files / components are impacted by `Opp_CRM_Router_AfterSave`

## Direct runtime dependencies (what must exist + be Active)

1. **`force-app/main/default/flows/SF_Log_Run.flow-meta.xml`**

* Your router emits tasks via `SF_Log_Run` (your Task table output confirms it).

2. **`force-app/main/default/flows/Opp_Reapproval_Guardrail.flow-meta.xml`**

* Your guardrail flow is being invoked and logging:

  * `MILESTONE_REAPPROVAL_GUARDRAIL_NOTLATESTAGE`
  * `MILESTONE_REAPPROVAL_GUARDRAIL_LATESTAGE`

3. **Opportunity object + the fields referenced**

* At minimum `Opportunity.Id` and `Opportunity.StageName` (you fixed the “StageName doesn’t exist” errors earlier by ensuring the record lookup pulls StageName and using a non-conflicting variable name).

## Indirect dependencies (commonly used alongside)

4. **`force-app/main/default/flows/SF_Notify_Milestone.flow-meta.xml`** (if router uses it)

* You deployed it; whether router calls it depends on references inside `Opp_CRM_Router_AfterSave`.

5. **`force-app/main/default/workflows/Opportunity.workflow-meta.xml`** (if you still have classic workflow rules)

* Not necessarily called by Flow directly, but it’s part of the same object automation surface area and can “also fire” when the same record changes happen.

## Logging output (downstream data)

6. **Tasks in Salesforce (`Task` object)**

* Your logging is persisted as `Task` records. That is a “data dependency”: your “observability” depends on Task creation permissions and field availability.

---

# B) Prove the connections from your repo (dependency scan commands)

Run these exactly (they’ll tell you what else `Opp_CRM_Router_AfterSave` references).

## 1) Find subflow calls / referenced flows

```powershell
$router="E:\Salesforce\force-app\main\default\flows\Opp_CRM_Router_AfterSave.flow-meta.xml"

# show any referenced flows by name
Select-String -Path $router -Pattern "<flowName>|<subflow>|<subflows>|<flowReference>|<flow>" -Context 0,3
```

## 2) Find what sObjects + fields it touches

```powershell
Select-String -Path $router -Pattern "<object>|<sobject>|<field>|<fieldReference>|<elementReference>|StageName|Opportunity\." -Context 0,2
```

## 3) Find every place it writes logs (SF_Log_Run usage)

```powershell
Select-String -Path $router -Pattern "SF_Log_Run|MILESTONE_|PipelineKey|Severity|Message|RecordId" -Context 0,3
```

## 4) Build a “who references who” view across *all* flows

This shows which flows call `SF_Log_Run`, which call `Opp_Reapproval_Guardrail`, etc.

```powershell
$flows="E:\Salesforce\force-app\main\default\flows\*.flow-meta.xml"

# Who calls SF_Log_Run?
"`n=== Flows that call SF_Log_Run ==="
Select-String -Path $flows -Pattern "<flowName>SF_Log_Run</flowName>" |
  Select Path,LineNumber,Line

# Who calls Opp_Reapproval_Guardrail?
"`n=== Flows that call Opp_Reapproval_Guardrail ==="
Select-String -Path $flows -Pattern "<flowName>Opp_Reapproval_Guardrail</flowName>" |
  Select Path,LineNumber,Line
```

## 5) Identify the “stray backup” that must be removed from staging

You already found:

* `Opp_CRM_Router_AfterSave.flow-meta.xml.localbak_20260218_201714`

Fix it now (do **not** commit it):

```powershell
git restore --staged force-app/main/default/flows/Opp_CRM_Router_AfterSave.flow-meta.xml.localbak_20260218_201714 2>$null
Remove-Item force-app/main/default/flows/Opp_CRM_Router_AfterSave.flow-meta.xml.localbak_20260218_201714 -Force
```

Then prevent it forever:

```powershell
Add-Content .gitignore "`n# local flow backups`n*.localbak_*`n"
git add .gitignore
```

---

# C) README you want (system usage + how to retrieve info next time)

Paste this into `README.md` (or replace the CRM section with it).

````md
# Salesforce CRM Automation (Opp CRM v1)

## What this repo contains
This repo stores Salesforce metadata for:
- Lead intake + DocuSign flows (Lead pipeline)
- Opportunity routing + guardrails (Opp CRM v1)
- Centralized logging via Task creation (`SF_Log_Run`)

Everything is deployable via `sf project deploy start` from this repo.

---

## Key Automation: Opportunity Router + Guardrail

### Primary flows
| Flow | Type | Purpose |
|---|---|---|
| `Opp_CRM_Router_AfterSave` | Record-Triggered Flow (Opportunity) | Orchestrates downstream milestone actions when an Opportunity updates (e.g., stage changes). |
| `Opp_Reapproval_Guardrail` | Auto-Launched Flow | Validates if Opportunity is in a “late stage” and logs the result. |
| `SF_Log_Run` | Auto-Launched Flow | Writes observability logs to the **Task** object (Subject + Description). |
| `SF_Notify_Milestone` | (Optional) | Notification helper if referenced by router. |

### How the router logs
All runtime telemetry is written to `Task` records in Salesforce.

Subject format:
`[SF_Log_Run] <LEVEL> | <PIPELINE> | <MILESTONE>`

Description format includes:
- `RecordId=<OpportunityId>`
- `Message=<free text>`
- `MilestoneKey=<constant>`

---

## How to verify the system is working

### 1) Confirm flows are Active in the org
```sql
-- Tooling API SOQL
SELECT DeveloperName, ActiveVersionId, LatestVersionId
FROM FlowDefinition
WHERE DeveloperName IN ('Opp_CRM_Router_AfterSave','Opp_Reapproval_Guardrail','SF_Log_Run')
````

Expected:

* `ActiveVersionId == LatestVersionId` for each flow.

### 2) Trigger the router (example: update StageName)

Update an Opportunity stage:

* non-late stage → should log NOTLATESTAGE
* late stage (e.g., Contracting) → should log LATESTAGE

### 3) Query logs (Task records created today)

```sql
SELECT Id, Subject, Description, CreatedDate
FROM Task
WHERE CreatedDate = TODAY
ORDER BY CreatedDate DESC
LIMIT 50
```

Common milestones you should see:

* `MILESTONE_ROUTER_FIRED`
* `MILESTONE_REAPPROVAL_GUARDRAIL_NOTLATESTAGE`
* `MILESTONE_REAPPROVAL_GUARDRAIL_LATESTAGE`

---

## How to find dependencies next time (flow → flow + flow → field mapping)

### Flow-to-flow references (subflows)

Search for subflow calls:

```powershell
Select-String -Path force-app/main/default/flows/*.flow-meta.xml -Pattern "<flowName>" |
  Select Path,LineNumber,Line
```

To locate who calls `SF_Log_Run`:

```powershell
Select-String -Path force-app/main/default/flows/*.flow-meta.xml -Pattern "<flowName>SF_Log_Run</flowName>" |
  Select Path,LineNumber,Line
```

### Field usage (what objects/fields a flow depends on)

Example:

```powershell
Select-String -Path force-app/main/default/flows/Opp_CRM_Router_AfterSave.flow-meta.xml `
  -Pattern "Opportunity|StageName|<object>|<queriedFields>|<fieldReference>" -Context 0,2
```

---

## Deploying from this repo

### Deploy flows only

```powershell
sf project deploy start --source-dir force-app/main/default/flows --test-level NoTestRun -o <orgAliasOrUsername>
```

### Deploy everything under force-app

```powershell
sf project deploy start --source-dir force-app --test-level NoTestRun -o <orgAliasOrUsername>
```

---

## Repo hygiene rules (IMPORTANT)

### Do not commit local backups / temp files

Never commit:

* `*.bak*`
* `*.localbak_*`
* `_archive*`, `_disabled_*`, `tmp*`, `mdapi_tmp*`, raw `apexlog_*.txt`

If a backup file appears, delete it or move it outside `force-app/`.

---

## Troubleshooting

### Router triggers but no logs show up

* Confirm `SF_Log_Run` is Active
* Confirm the running user has permission to create Tasks
* Query Task records for today to verify telemetry

### Flow activation errors (InvalidDraft)

* Pull the flow XML (`sf project retrieve start`)
* Fix references to missing fields / invalid variables
* Redeploy and confirm `FlowDefinition.ActiveVersionId` updates
