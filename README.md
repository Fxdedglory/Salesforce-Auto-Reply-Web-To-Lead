````md
# Salesforce Automation Runbook

## Overview

This project implements a **template-driven, reusable** automation system for
Salesforce Leads. When a Lead is created (for example from a Web-to-Lead
form), a record-triggered Flow sends a templated email to the new Lead with a
PDF attachment and optionally notifies internal users. A PowerShell test
script provides deterministic end-to-end validation and writes debug
information to the Lead record so you can rapidly diagnose issues without
manually inspecting logs.

The primary design goals are:

- **Reusability** – one Apex action and one Flow pattern can drive many
  campaigns by swapping template IDs and attachment IDs. You do **not** need
  to change Apex code when you add more email campaigns.
- **Maintainability** – email content lives in Salesforce Email Templates,
  flows are declarative, and all IDs and settings are passed into the Apex
  action. This keeps the codebase small and easy to audit.
- **Debuggability** – the system surfaces its progress directly on the Lead
  record (`Lead.Description`) with predictable status tokens (see
  [Debugging & Test Workflow](#debugging--test-workflow)). A single test
  script exercises the entire pipeline and prints the debug field back to the
  console.

Use this runbook to understand, operate, and extend the system. It documents
how the components fit together, how to configure your org, how to add new
campaigns, and how to troubleshoot common problems.

---

## Quick Start

These steps run the entire pipeline and verify that a Lead triggers the
automation.

1. Open a terminal in the project root.
2. Navigate to your local Salesforce project directory (for example
   `E:\Salesforce`). The runbook assumes PowerShell on Windows but you can
   adapt the commands for other shells.

   ```powershell
   cd E:\Salesforce
````

3. Execute the test runner script. It will create a test Lead in your
   authenticated org, wait for the Flow and Apex action to run, and then
   query back the Lead to print its debug status.

   ```powershell
   .\test_lead_flow.ps1
   ```

4. Expected outcomes:

   * A new Lead record is created.
   * `Lead.Description` contains a status value (e.g. `EMAIL_SENT | LeadId=...`).
   * The Lead receives an email that uses the specified template and includes
     the attached PDF file.
   * If you enabled internal notification, the configured internal user
     receives an alert email with Lead details.

If any of these outcomes fail, use the debug status and the
[Troubleshooting](#troubleshooting) section to isolate the issue.

---

## Architecture Overview

### Flow & Apex Interaction

When a Lead is inserted, a record-triggered Flow (`After Save`) runs. The
Flow calls an Apex **Invocable Action** named
`LeadResumeEmailAction`. This action accepts several inputs:

| Input                | Description                                       |
| -------------------- | ------------------------------------------------- |
| `leadId`             | The Id of the Lead being processed.               |
| `emailTemplateId`    | Id of the Email Template to send (00X…).          |
| `orgWideFromAddress` | Email address from your Org-Wide Email Addresses. |
| `contentDocumentId`  | Id of the File to attach (069…).                  |

The Apex action performs the following steps:

1. Query the latest `ContentVersion` for the supplied `ContentDocumentId`.
2. Convert the file’s binary into a `Messaging.EmailFileAttachment`.
3. Send an email using `Messaging.sendEmail()` with the template and
   attachment.
4. Return control back to the Flow.

The Flow also updates `Lead.Description` at multiple points to expose a
deterministic status. The status values, in order, are:

* `STARTED` – Flow has begun processing.
* `CALLING_EMAIL` – Apex action invocation is about to occur.
* `EMAIL_SENT` – Apex action successfully sent the email.
* `EMAIL_FAULT | ERROR=<details>` – An exception occurred during send. The
  error message is appended after `ERROR=`.

An optional **Send Email** node in the Flow can dispatch an internal
notification. This sends an alert from an Org-Wide Email Address to a
configured recipient (no personal addresses are stored in code; set this
value in the Flow builder).

### File & Template Reuse

The Apex action is deliberately generic. By passing in the Ids of the
template, file, and sender, you can reuse the same Flow and Apex code for
many campaigns. To add a new campaign, you create a new Email Template and
update the Flow inputs (see
[Extending the System](#extending-the-system)).

---

## Repository Layout

The repository is organized so that all source of truth lives in the
`force-app/main/default` directory. Only modify files in this tree and
deploy them with Salesforce CLI.

| Directory / File                                                                  | Purpose                                                             |
| --------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| `force-app/main/default/classes/LeadResumeEmailAction.cls`                        | Apex invocable action used by the Flow.                             |
| `force-app/main/default/flows/Lead_Email_ResumeAttachment_OnCreate.flow-meta.xml` | Primary Flow that triggers on Lead creation.                        |
| `force-app/main/default/email/Leads/<Template>.email`                             | HTML body of your Email Template.                                   |
| `force-app/main/default/email/Leads/<Template>.email-meta.xml`                    | Metadata for the corresponding template.                            |
| `test_lead_flow.ps1`                                                              | PowerShell script that creates a test Lead and prints debug output. |

Files such as `mdapi_deploy_*` and `*.zip` are historical deployment
artifacts and are **not** source of truth; ignore them.

---

## Prerequisites & Setup

Before running the system, ensure the following:

1. **Salesforce CLI** (`sf`) is installed and available in your shell.
2. You have an authenticated org alias or username stored in a PowerShell
   variable (e.g. `$Org`). For example, run `sf org login web` or `sf org
   display` to confirm.
3. An **Org-Wide Email Address** exists in your org for the sender address you
   intend to use (e.g. `noreply@yourdomain.com`).
4. You have created at least one Email Template and uploaded the PDF you
   intend to attach via Salesforce Files.

---

## Configuration Values

Several Ids must be provided to the Flow and test script. Use the
Salesforce CLI to find them. The sample queries below assume you have your
org alias stored in `$Org`.

### EmailTemplate Id (00X…)

Run the following to list your most recently modified Email Templates:

```powershell
sf data query -o $Org -q "SELECT Id, Name, DeveloperName, FolderName FROM EmailTemplate ORDER BY LastModifiedDate DESC LIMIT 20"
```

Choose the `Id` for the template you want to send. This value is passed to
the Flow as `emailTemplateId`.

### Resume ContentDocumentId (069…)

To find the file that will be attached, query Salesforce Files (ContentVersion):

```powershell
sf data query -o $Org -q "SELECT Id, Title, FileType, ContentDocumentId, VersionNumber, CreatedDate FROM ContentVersion WHERE Title LIKE '%Resume%' ORDER BY CreatedDate DESC LIMIT 10"
```

Use the `ContentDocumentId` value (the field starting with `069`), not the
`ContentVersion` Id (`068…`). This Id is passed to the Flow as
`contentDocumentId`.

### Org-Wide Email Address

List your Org-Wide Email Addresses:

```powershell
sf data query -o $Org -q "SELECT Id, Address, DisplayName, IsAllowAllProfiles FROM OrgWideEmailAddress ORDER BY Address"
```

Use the `Address` field (e.g. `noreply@yourdomain.com`). This string
becomes the `orgWideFromAddress` input to the Apex action.

---

## Changing Email Content

Email content lives in Salesforce Email Templates. You have two ways to
modify it:

### Option A — Salesforce Setup UI

1. Go to **Setup → Email Templates**.
2. Open the template → edit Subject/Body.
3. Save changes.

### Option B — Repository (recommended for version control)

1. Edit:

   * `force-app/main/default/email/Leads/<Template>.email`
   * `force-app/main/default/email/Leads/<Template>.email-meta.xml`

2. Deploy:

   ```powershell
   sf project deploy start -o $Org -m "EmailTemplate:Leads/<TemplateDeveloperName>"
   ```

---

## Extending the System

There are two common patterns for adding new campaigns or variants.

### Pattern A — Single Flow, Template Switch (Recommended)

Create one “router” Flow that inspects Lead fields such as `LeadSource`,
`Company`, `Campaign` flags, or any custom metadata. Based on these values,
the Flow chooses which `emailTemplateId` and `contentDocumentId` to pass to
the Apex action.

Pros:

* Fewer flows to maintain; centralized debugging.

Cons:

* Flow becomes a dispatcher and can grow complex.

### Pattern B — One Flow per Campaign

Clone the base Flow for each campaign and hard-code different template and
attachment IDs inside each copy.

Pros:

* Very simple mental model; isolated changes.

Cons:

* Many flows in the org can become clutter.

### Adding a New Template + Flow (Step-by-Step)

1. **Create a Template** – add a new file under `force-app/main/default/email/Leads/`
   and deploy it:

   ```powershell
   sf project deploy start -o $Org -m "EmailTemplate:Leads/<TemplateDeveloperName>"
   ```

2. **Clone the Flow** – copy:

   * `force-app/main/default/flows/Lead_Email_ResumeAttachment_OnCreate.flow-meta.xml`

   Rename (file name + internal `<label>` and API name) to:

   * `Lead_Email_<CampaignName>_OnCreate.flow-meta.xml`

3. **Update only the Apex Action inputs** inside the flow:

   * `emailTemplateId = <new 00X...>`
   * `contentDocumentId = <new 069...>` (optional)
   * `orgWideFromAddress = <your org-wide address>`

4. **Deploy the Flow**:

   ```powershell
   sf project deploy start -o $Org -d "force-app/main/default/flows"
   ```

5. **Test**:

   ```powershell
   .\test_lead_flow.ps1
   ```

---

## Swapping the Attached Resume

To change which file is attached:

1. Upload a new resume PDF to Salesforce Files.
2. Update the Flow input:

   * `contentDocumentId = <new 069...>`

Verify latest version:

```powershell
$Doc="069xxxxxxxxxxxxxxx"
sf data query -o $Org -q "SELECT Id, Title, ContentSize, FileType, VersionNumber, CreatedDate FROM ContentVersion WHERE ContentDocumentId = '$Doc' ORDER BY VersionNumber DESC LIMIT 1"
```

The Apex action always selects the newest `ContentVersion` for the given `ContentDocumentId`.

---

## Internal Notification

To send an internal alert each time a Lead triggers the Flow:

1. Add a **Send Email** element to the same Flow.
2. Configure:

   * **Recipient Addresses**: internal email(s)

   * **Sender Type**: `OrgWideEmailAddress`

   * **Sender Email Address**: choose your org-wide sender

   * **Subject**:

     ```
     New Lead Created: {!$Record.FirstName} {!$Record.LastName} ({!$Record.Email})
     ```

   * **Body**:

     ```
     Name: {!$Record.FirstName} {!$Record.LastName}
     Email: {!$Record.Email}
     Company: {!$Record.Company}
     Lead Source: {!$Record.LeadSource}
     Created: {!$Record.CreatedDate}
     Lead Id: {!$Record.Id}
     ```

Placement:

* Put it **before** resume send if you want notification even if attachment send fails.
* Put it **after** resume send if notification implies success.

---

## Debugging & Test Workflow

### Always test with the same command

```powershell
.\test_lead_flow.ps1
```

### Always verify the debug status in Lead.Description

The Flow writes deterministic debug tokens to `Lead.Description`:

| Status          | Meaning                 |                         |
| --------------- | ----------------------- | ----------------------- |
| `STARTED`       | Flow began running      |                         |
| `CALLING_EMAIL` | About to call Apex      |                         |
| `EMAIL_SENT`    | Email successfully sent |                         |
| `EMAIL_FAULT    | ERROR=<details>`        | Failure; error appended |

If you see `EMAIL_FAULT`, use the error details and the troubleshooting section below.

---

## Troubleshooting

### “Org-Wide Email provided is not valid”

* The Flow/Apex must use an Address that exists in OrgWideEmailAddress.

Verify:

```powershell
sf data query -o $Org -q "SELECT Id, Address FROM OrgWideEmailAddress"
```

* Ensure Flow input matches exactly (e.g. `tim@teemails.com`).

### Lead created but no attachment

* Flow must pass **ContentDocumentId (069...)**, not ContentVersionId (068...).
* Verify ContentVersion exists:

```powershell
$Doc="069..."
sf data query -o $Org -q "SELECT Id, Title, ContentSize, FileType, VersionNumber FROM ContentVersion WHERE ContentDocumentId = '$Doc' ORDER BY VersionNumber DESC LIMIT 1"
```

### Debugging quickly

* Debug statuses are written to `Lead.Description`:

  * `STARTED`
  * `CALLING_EMAIL`
  * `EMAIL_SENT`
  * `EMAIL_FAULT | ERROR=...`

---

## Glossary

* **Flow (Record-Triggered)**: automation that runs when a record is created/updated
* **Email Template**: subject/body template with merge fields
* **Org-Wide Email Address**: verified sender address usable by automations
* **ContentDocumentId (069...)**: File container id in Salesforce Files
* **ContentVersionId (068...)**: specific version id of a file
* **Apex Invocable Action**: Apex method callable from Flow

---

## Deployment Commands

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

## Repo Hygiene

* Do **not** commit local backups / temp files (e.g. `*.bak*`, `*.localbak_*`, `_archive*`, `_disabled_*`, temp zip artifacts, Apex logs).
* Prefer adding ignore patterns to `.gitignore` to prevent accidental commits.

---

## Final Notes

This runbook is designed to preserve the two core strengths of this system:

1. **Reusability**: add templates/campaigns without rewriting Apex.
2. **Debuggability**: deterministic, visible progress via `Lead.Description` plus a single-command test runner.

```
