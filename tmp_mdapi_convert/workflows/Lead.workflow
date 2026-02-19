<?xml version="1.0" encoding="UTF-8"?>
<!--
v0.3.0 | 2026-02-18
Lead Workflow Manifest (repo-governed intended order)

INTENDED PIPELINE ORDER (documentation + script-run order):
  1) Lead Email + Resume + DocuSign Envelope (Flow: Lead_Email_ResumeAttachment_OnCreate)
  2) Lead Qualification After DocuSign (Flow: Lead_Qualification_AfterDocuSign)
  3) Core CRM Branch After Qualification (Flow: Lead_CRM_Core_Workflow_AfterQualification)

NOTES:
  - Salesforce Workflow metadata does not enforce Flow execution ordering.
  - Runtime gating is enforced by Flow entry criteria + idempotency guard fields.
-->
<Workflow xmlns="http://soap.sforce.com/2006/04/metadata">

    <alerts>
        <fullName>Lead_Auto_Response_TeeEmails</fullName>
        <description>Lead Auto Response - TeeEmails</description>
        <protected>false</protected>
        <recipients>
            <field>Email</field>
            <type>email</type>
        </recipients>
        <senderAddress>tim@teemails.com</senderAddress>
        <senderType>OrgWideEmailAddress</senderType>
        <template>Leads/Web_to_lead_Auto_Response_v5_1771283904635</template>
    </alerts>

    <!-- TODO (optional):
         - Add additional alerts for "Qualified Lead", "Account Created", "Contact Created"
         - Or keep all notifications inside Flows for easier iteration
    -->
</Workflow>
