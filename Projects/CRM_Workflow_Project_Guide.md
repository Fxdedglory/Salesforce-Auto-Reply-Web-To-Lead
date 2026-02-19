```markdown
# CRM Workflow Project Guide (v0.4.0 | 2026-02-18)

## Project: Salesforce Lead → Qualification → Account/Contact Automation (DocuSign Integrated)

---

# 1. System Purpose

## 1.1 Objective

Design and implement a deterministic, metadata-driven Salesforce CRM automation system that:

1. Captures Web-to-Lead submissions
2. Sends templated outreach + resume attachment
3. Triggers DocuSign envelope
4. Waits for DocuSign approval signal (DocuSign completion)
5. Upon approval:
   - Creates Account (Company)
   - Creates Contact (Person)
   - Assigns operational tasks
   - Launches independent data collection branches
6. Tracks workflow completion state
7. Enables conversion gating

This system must be:

- Deterministic
- Debuggable
- Reusable
- Metadata-controlled
- Deployable via CLI
- Observable via Lead.Description debug surface

---

# 2. Architectural Layers

This project follows a strict 4-layer architecture.

---

## Layer 1 — Entry Layer (Lead Create)

**Trigger:** Web-to-Lead  
**Object:** Lead  
**Trigger Type:** After Create  

Actions:

1. Write debug state: `STARTED`
2. Send Resume Email (Apex Action)
3. Send internal notification (Task + optional email)
4. Trigger DocuSign envelope (Send Envelope from Template)
5. Write debug state: `AWAITING_DOCUSIGN`
6. Set idempotency marker: `DocuSign_Email_Sent__c = TRUE` (prevents re-send)

---

## Layer 2 — DocuSign Status Ingest (Envelope Status → Lead)

**Trigger:** DocuSign managed object update  
**Primary Object:** `dfsle__EnvelopeStatus__c`  
**Trigger Type:** After Create OR After Update  

**Salesforce-correct reality:** The signer completes the signing ceremony in DocuSign (external). Salesforce receives the completion signal via DocuSign for Salesforce (“dfsle”) objects. We should not fake “approval” on Lead—Lead is updated only in response to DocuSign status.

### Condition: Envelope Completed

Use:

- `dfsle__EnvelopeStatus__c.dfsle__Completed__c` **IS NOT NULL**  
  (This field is present and labeled “Completed” per your describe output.)

Optionally also check:

- `dfsle__EnvelopeStatus__c.dfsle__Status__c = "Completed"`  
  (Status is present as `dfsle__Status__c`. Exact picklist values can be confirmed from the JSON, but the timestamp field is the most deterministic.)

### Actions

1. Resolve the related envelope:
   - From `dfsle__EnvelopeStatus__c.dfsle__EnvelopeStatus__c` relationship field(s) (your describe JSON shows relationship references exist, exact name may vary by package version).
2. Resolve the related source Salesforce record (Lead) from the envelope:
   - Envelope usually stores a “source object” reference / originating record / related record.
3. Update Lead:
   - `DocuSign_Approved__c = TRUE`
   - `Qualification_Status__c = Qualified`
   - `Qualified_At__c = NOW()`
4. Write debug state on Lead.Description: `QUALIFIED`

> Note: This layer is the “truth bridge” from DocuSign → Salesforce.

---

## Layer 3 — Qualification Layer (Lead Gate)

**Trigger:** Lead Updated  
**Condition:**  
- `DocuSign_Approved__c = TRUE`

Actions:

1. Ensure:
   - `Qualification_Status__c = Qualified`
   - `Qualified_At__c = NOW()` (if not already set)
2. Write debug: `QUALIFIED`
3. Trigger Core CRM Workflow branch (Layer 4)

This is the gate that controls downstream execution.

---

## Layer 4 — Core CRM Workflow Branch (Primary Focus)

This branch runs only if:

```

DocuSign_Approved__c = TRUE
AND
Qualification_Status__c = Qualified

```

It must execute in strict order and be idempotent.

---

# 3. Canonical Execution Sequence

```

1. Web-to-Lead
2. Email + Resume + DocuSign Envelope
3. Recipient Signs (DocuSign link in email)
4. DocuSign Completion recorded in dfsle__EnvelopeStatus__c
5. Envelope Status → Lead updated to Approved + Qualified
6. Core CRM Workflow
7. Independent Form Branches
8. Completion Checks
9. Conversion

```

---

# 4. Object Model

## 4.1 Standard Objects

| Object      | Role          |
| ----------- | ------------- |
| Lead        | Entry object  |
| Account     | Company       |
| Contact     | Person        |
| Opportunity | Optional Deal |

---

## 4.2 DocuSign Managed Objects (dfsle)

| Object                   | Role |
|--------------------------|------|
| dfsle__Envelope__c       | Envelope record (source/parent record linkage) |
| dfsle__EnvelopeStatus__c | Envelope lifecycle timeline + status + completion timestamps |
| dfsle__Recipient__c      | Recipient records/roles |
| dfsle__RecipientStatus__c| Recipient status timeline |
| dfsle__Document__c       | Document records |

**Confirmed from your org describe grep:**
- `dfsle__EnvelopeStatus__c.dfsle__Completed__c` exists (label: “Completed”)
- `dfsle__EnvelopeStatus__c.dfsle__Status__c` exists (label: “Status”)
- `dfsle__EnvelopeStatus__c.dfsle__LastStatusUpdate__c` exists

---

## 4.3 Custom Fields (Lead)

| Field                         | Type            | Purpose                   |
| ----------------------------- | --------------- | ------------------------- |
| DocuSign_Email_Sent__c        | Checkbox        | Prevent re-sending envelope/email |
| DocuSign_Approved__c          | Checkbox        | Qualification trigger (set only via DocuSign status ingest) |
| Qualification_Status__c       | Picklist        | Lifecycle state (New/Working/Qualified/Unqualified) |
| Qualified_At__c               | DateTime        | Audit marker              |
| CRM_Core_Processed__c         | Checkbox        | Idempotency for downstream execution |
| Company_Form_Completed__c     | Checkbox        | Branch A completion       |
| Contact_Form_Completed__c     | Checkbox        | Branch B completion       |
| Created_Account__c            | Lookup(Account) | Created Account reference |
| Created_Contact__c            | Lookup(Contact) | Created Contact reference |
| Workflow_Completion_Status__c | Formula/Text    | Human-readable state      |
| Workflow_Debug__c (optional)  | Long Text       | Debug surface (optional)  |

Primary debug surface remains:

- `Lead.Description`

---

# 5. Core CRM Workflow Logic (Deterministic Steps)

## STEP 0 — Entry Preconditions

Run only if:

```

DocuSign_Approved__c = TRUE
AND Qualification_Status__c = "Qualified"
AND CRM_Core_Processed__c = FALSE

```

Write debug: `CRM_CORE_START`

---

## STEP 1 — Idempotency Guard

If:

```

Created_Account__c IS NOT NULL
OR CRM_Core_Processed__c = TRUE

```

→ Exit.

Write debug: `SKIP_ALREADY_PROCESSED`

---

## STEP 2 — Create Account

Create Account using:

- Lead.Company
- Lead.Phone
- Lead.Website

Store:

```

Created_Account__c = Account.Id

```

Write debug: `ACCOUNT_CREATED`

---

## STEP 3 — Create Contact

Create Contact using:

- Lead.FirstName
- Lead.LastName
- Lead.Email
- AccountId = Created_Account__c

Store:

```

Created_Contact__c = Contact.Id

```

Write debug: `CONTACT_CREATED`

---

## STEP 4 — Task Generation (Parallel Branch Initiation)

Create 2 tasks:

### Task A

- Subject: Complete Company Information Form
- Owner: tesellwood5230@gmail.com
- Related To: Lead (WhoId = LeadId)

### Task B

- Subject: Complete Contact Information Form
- Owner: tesellwood5230@gmail.com
- Related To: Lead (WhoId = LeadId)

Write debug: `TASKS_CREATED`

---

## STEP 5 — Email Alerts / Notifications

Send alert when:

- Qualified
- Account Created
- Contact Created
- Forms Pending

Write debug: `ALERTS_SENT`

---

## STEP 6 — Closeout Marker

Set:

```

CRM_Core_Processed__c = TRUE

```

Write debug: `CRM_CORE_DONE`

---

# 6. Independent Branch Logic

Branches run independently once qualification is achieved.

---

## Branch A — Company Form

Trigger:

```

Qualification_Status__c = "Qualified"
AND Company_Form_Completed__c = FALSE

```

Form captures:

- Industry
- Website
- Phone
- Address

On completion:

```

Company_Form_Completed__c = TRUE

```

Write debug: `COMPANY_FORM_COMPLETE`

---

## Branch B — Contact Form

Trigger:

```

Qualification_Status__c = "Qualified"
AND Contact_Form_Completed__c = FALSE

```

Form captures:

- Email
- Job Title
- Phone

On completion:

```

Contact_Form_Completed__c = TRUE

```

Write debug: `CONTACT_FORM_COMPLETE`

---

# 7. Completion Gate Logic (Conversion Readiness)

When:

```

Company_Form_Completed__c = TRUE
AND Contact_Form_Completed__c = TRUE

```

Set:

```

Workflow_Completion_Status__c = "READY_TO_CONVERT"

```

Create task: Convert Lead  
Write debug: `READY_FOR_CONVERSION`

---

# 8. Governance Model

## 8.1 Metadata-as-Manifest

This project is governed by version-controlled metadata:

- Custom fields
- Permission set
- Flows
- Apex actions
- Templates / Envelope configurations (as applicable)

A “workflow-meta” document acts as orchestration manifest:

- Defines alert rules
- Defines order-of-execution
- Defines debug states
- Documents topology

> Note: The manifest does not enforce flow order. Flow execution order is controlled by Flow configuration and entry criteria.

---

## 8.2 Flow Files (Topology)

Each major branch has its own `.flow-meta.xml`:

- `Lead_Email_ResumeAttachment_OnCreate.flow-meta.xml`
- `Lead_DocuSign_Send_Envelope_OnCreate.flow-meta.xml`
- `DocuSign_EnvelopeStatus_To_Lead_Qualification.flow-meta.xml`  ← **critical integration step**
- `Lead_CRM_Core_Workflow_AfterQualification.flow-meta.xml`
- `Lead_Company_Form.flow-meta.xml`
- `Lead_Contact_Form.flow-meta.xml`

---

# 9. Observability Strategy

## Primary Debug Surface

```

Lead.Description

```

## Optional Enhanced Debug

```

Workflow_Debug__c (Long Text)

```

## Debug States (Recommended)

- STARTED
- CALLING_EMAIL
- EMAIL_SENT
- ENVELOPE_SENT
- AWAITING_DOCUSIGN
- DOCUSIGN_STATUS_UPDATED
- QUALIFIED
- CRM_CORE_START
- ACCOUNT_CREATED
- CONTACT_CREATED
- TASKS_CREATED
- ALERTS_SENT
- COMPANY_FORM_COMPLETE
- CONTACT_FORM_COMPLETE
- READY_FOR_CONVERSION
- ERROR:<message>

---

# 10. Milestones

## Phase 1 — Entry Automation

- [ ] Web-to-Lead configured
- [ ] Resume email flow active
- [ ] DocuSign envelope integrated (send envelope from template)

## Phase 2 — DocuSign Status Ingest (Critical Gate)

- [ ] `dfsle__EnvelopeStatus__c` record-triggered flow active
- [ ] Completed detected via `dfsle__Completed__c != null`
- [ ] Lead updated: `DocuSign_Approved__c = TRUE`, `Qualification_Status__c = Qualified`, `Qualified_At__c = NOW()`

## Phase 3 — Core CRM Branch

- [ ] Account creation
- [ ] Contact creation
- [ ] Task generation
- [ ] Alert system
- [ ] Idempotency: `CRM_Core_Processed__c`

## Phase 4 — Independent Forms

- [ ] Company form flow
- [ ] Contact form flow
- [ ] Validation rules

## Phase 5 — Conversion Gate

- [ ] Completion logic
- [ ] Conversion task
- [ ] End-to-end test

---

# 11. End-to-End Success Criteria

When a test Lead is created and the DocuSign envelope is completed:

1. Lead receives DocuSign envelope email link
2. Recipient signs and applies stamp in DocuSign
3. `dfsle__EnvelopeStatus__c` records completion timestamp (`dfsle__Completed__c`)
4. Lead fields update:
   - DocuSign_Approved__c = TRUE
   - Qualification_Status__c = Qualified
   - Qualified_At__c populated
5. Account created and stored in Created_Account__c
6. Contact created and stored in Created_Contact__c
7. Two operational tasks created
8. Alerts sent
9. Debug states visible and ordered
10. Workflow_Completion_Status__c updates correctly
11. Lead becomes ready for conversion only when both forms complete

---

# 12. Portfolio Framing

This project demonstrates:

- Metadata-driven CRM orchestration
- Flow-based lifecycle automation
- Deterministic execution modeling
- Integration gating (DocuSign → CRM)
- Task-based operational branching
- Conversion gating via completion criteria
- Debug-first automation design
- CLI-driven deployment
- Security/FLS awareness (permission sets required for field visibility)

---

# 13. Notes on DocuSign “Where Signing Happens”

**Signing happens in DocuSign, not inside Salesforce.**

Salesforce sends an envelope (from a template) to the Lead’s email address. The recipient completes the signing ceremony via the DocuSign email link (including the stamp tab configured on the template). Salesforce then receives the event via the DocuSign for Salesforce package and records it under `dfsle__EnvelopeStatus__c` (and related dfsle objects). Your automation must treat `dfsle__Completed__c` (and/or `dfsle__Status__c`) as the authoritative “signed” signal and only then update the Lead to Qualified.

---
```
