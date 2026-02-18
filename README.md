Got it. Below are **(1) a solid `.gitignore`** for this repo and **(2) a much more extensive `README.md`** focused on **reusability**, **where things live**, and **how to add/modify templates, flows, and notifications**—with the explicit goal that you can keep validating everything using **only `test_lead_flow.ps1`**.

---

## 1) `.gitignore` (drop into `E:\Salesforce\.gitignore`)

```gitignore
# =========================
# OS / Editor
# =========================
.DS_Store
Thumbs.db
.vscode/
.idea/
*.swp

# =========================
# Salesforce CLI / Local state
# =========================
.sf/
.sfdx/
.localdevserver/
**/*.log

# =========================
# Node / Python (if you ever add tooling)
# =========================
node_modules/
dist/
build/
coverage/
__pycache__/
.venv/
venv/

# =========================
# Archives / exports
# =========================
*.zip
*.tar
*.gz
*.7z

# =========================
# MDAPI deploy artifacts (NOT source-of-truth)
# =========================
mdapi_deploy_*/
unpackaged/
**/unpackaged/
**/deployments/
*_deploy_*/
*_unpackaged_*/

# =========================
# Secrets (never commit)
# =========================
.env
.env.*
*.pem
*.key
*.crt
```

**Why this matters:** your **source-of-truth** is `force-app/**` + scripts + docs. The `mdapi_deploy_*` and zip bundles will bloat your repo and create noise.

---

## 2) Full `README.md` (replace `E:\Salesforce\README.md` with this)

```md
# Salesforce Auto Reply Web-to-Lead (Resume Attachment + Lead Notification)

This project implements a reusable Salesforce automation system that:

1) **Auto-sends a templated email to new Leads** (LeadSource=Web)  
2) **Attaches a resume PDF from Salesforce Files** (ContentDocumentId)  
3) **Optionally notifies you (internal alert)** when a new Lead is created  
4) Includes a **single-command test runner**: `test_lead_flow.ps1`

This repo is designed to be easy to extend: swap templates, swap attachments, add new flows, and reuse the Apex action across workflows.

---

## What This Repo Does

### When a Lead is created (Web-to-Lead)
- A record-triggered Flow runs on Lead **After Create**
- It calls an Apex Invocable Action that:
  - renders a Salesforce Email Template to the Lead
  - sets Org-Wide “From” email
  - attaches the latest file version from Salesforce Files (ContentVersion) by ContentDocumentId
  - sends the email

### You also (optionally) receive a notification email
- A simple Flow “Send Email” node can email `sellwood.timm@gmail.com`
- The body includes Lead name/email/company/source/time/id

---

## Architecture (High-Level)

**Flow: `Lead Email - Resume Attachment (On Create)`**
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

````

**Apex: `LeadResumeEmailAction`**
- Inputs:
  - `leadId` (Lead Id 00Q…)
  - `emailTemplateId` (EmailTemplate Id 00X…)
  - `orgWideFromAddress` (e.g. `tim@teemails.com`)
  - `contentDocumentId` (ContentDocument Id 069…)
- Behavior:
  - Queries latest `ContentVersion` for the `ContentDocumentId`
  - Attaches `VersionData` as `EmailFileAttachment`
  - Sends via `Messaging.sendEmail()`

---

## Repo Layout (Where Things Are)

### Source of truth
- `force-app/main/default/classes/`
  - `LeadResumeEmailAction.cls` (Apex invocable that sends template + attachment)
- `force-app/main/default/flows/`
  - `Lead_Email_ResumeAttachment_OnCreate.flow-meta.xml` (primary production flow)
- `force-app/main/default/email/`
  - `Leads/<your email template>.email` (HTML)
  - `Leads/<your email template>.email-meta.xml` (metadata)

### Test automation
- `test_lead_flow.ps1`
  - Creates a test Lead and prints the resulting Lead Description debug line
  - This is the **only script you need** to validate the system end-to-end

### Docs
- `README.md` (this file)

### What is intentionally ignored (not source-of-truth)
- `mdapi_deploy_*`
- `*.zip`
These are deploy artifacts and should not be versioned for long-term maintainability.

---

## Prerequisites

- Salesforce CLI installed (`sf`)
- Authenticated org set in PowerShell as `$Org` (alias or username)
- Org-Wide Email Address configured in Salesforce for:
  - `tim@teemails.com` (or your preferred sender)

---

## How to Run a Test (Single Command)

From the project root:
```powershell
cd E:\Salesforce
.\test_lead_flow.ps1
````

Expected outcome:

* A Lead is created
* Lead.Description becomes `EMAIL_SENT | LeadId=...` (or `EMAIL_FAULT | ...`)
* You receive the email with the resume attached

---

## Configuration Values (IDs You’ll Reuse)

You will typically store these values in one place (either inside the Flow action inputs, or inside `test_lead_flow.ps1` as constants if you want portability):

### 1) Email Template Id (00X…)

Query:

```powershell
sf data query -o $Org -q "SELECT Id, Name, DeveloperName, FolderName FROM EmailTemplate ORDER BY LastModifiedDate DESC LIMIT 20"
```

### 2) Resume ContentDocumentId (069…)

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

## How to Modify Email Wording

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

## How to Swap the Attached Resume (New File)

Upload a new resume PDF to Salesforce Files, then update the Flow’s input:

* `contentDocumentId = <new 069...>`

Confirm latest version:

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

## Adding a New Email Template + Flow (Reusable Pattern)

### Step 1 — Create / Clone a new EmailTemplate

* Add a new email template file under:

  * `force-app/main/default/email/Leads/`

Deploy it:

```powershell
sf project deploy start -o $Org -m "EmailTemplate:Leads/<YourTemplateDeveloperName>"
```

### Step 2 — Clone the main flow file

Copy:

* `force-app/main/default/flows/Lead_Email_ResumeAttachment_OnCreate.flow-meta.xml`

Rename it (label + api name inside the file) to something like:

* `Lead_Email_<CampaignName>_OnCreate.flow-meta.xml`

### Step 3 — Update only the action inputs

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

## Internal Notification (Email Me When a Lead Is Created)

You already received a working example:

> “New Lead Created: Tim Sellwood ([tesellwood5230@gmail.com](mailto:tesellwood5230@gmail.com))”

To keep this reusable, add the notification inside your **same active flow** (`Lead Email - Resume Attachment (On Create)`) as a separate branch/action.

### Recommended: use a “Send Email” core action with these inputs

**Recipient Addresses**

* `sellwood.timm@gmail.com`

**Sender Type**

* `OrgWideEmailAddress` (recommended)

**Sender Email Address**

* `tim@teemails.com` (must exist as Org-Wide Email)

**Subject**

* Example:

  * `New Lead Created: {!$Record.FirstName} {!$Record.LastName} ({!$Record.Email})`

**Body**

* Plain text or rich text, example:

  * Name: {!$Record.FirstName} {!$Record.LastName}
  * Email: {!$Record.Email}
  * Company: {!$Record.Company}
  * Lead Source: {!$Record.LeadSource}
  * Created: {!$Record.CreatedDate}
  * Lead Id: {!$Record.Id}

If you want, you can place this notification action:

* **before** the resume send (so you’re notified even if resume send fails)
* or **after** the resume send (so notification implies successful send)

---

## Troubleshooting (Common)

### “Org-Wide Email provided is not valid”

* Ensure the Flow/Apex is using the **email address** that exists in OrgWideEmailAddress
* Verify:

```powershell
sf data query -o $Org -q "SELECT Id, Address FROM OrgWideEmailAddress"
```

* If your flow passes `tim@teemails.com`, that must match exactly.

### Lead created but no attachment

* Confirm the Flow input is a **ContentDocumentId (069...)**, not ContentVersionId (068...)
* Confirm the doc has a valid latest ContentVersion:

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

* This system writes status into `Lead.Description`:

  * `STARTED`
  * `CALLING_EMAIL`
  * `EMAIL_SENT`
  * `EMAIL_FAULT | ERROR=...`

---

## Glossary (Salesforce Terms Used Here)

* **Flow (Record-Triggered)**: Salesforce automation that runs when a record is created/updated
* **Email Template**: stored template for subject/body with merge fields
* **Org-Wide Email Address**: verified “From” address usable by automation
* **ContentDocumentId (069...)**: the “File” object id (Salesforce Files container)
* **ContentVersionId (068...)**: a specific file version
* **Apex Invocable Action**: Apex method callable from Flow

---

## GitHub “Done” Definition

Per project policy: this project is complete only when the final state is pushed to:
`https://github.com/Fxdedglory/Salesforce-Auto-Reply-Web-To-Lead`

---

## Typical Deployment Commands (Cheat Sheet)

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