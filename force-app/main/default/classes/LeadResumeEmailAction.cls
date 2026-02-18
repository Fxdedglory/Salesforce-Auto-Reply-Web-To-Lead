// v1.2 | 2026-02-17
// Purpose: Flow-invocable action to send an EmailTemplate to a Lead and attach a File (Salesforce Files).
// Inputs:
//  - leadId: Lead Id (00Q...)
//  - emailTemplateId: EmailTemplate Id (00X...)
//  - orgWideFromAddress: org-wide from email address (e.g., tim@teemails.com)
//  - contentDocumentId: ContentDocument Id (069...) to attach (latest ContentVersion is attached)
//
// Notes:
//  - Uses Messaging.SingleEmailMessage + setTemplateId + setTargetObjectId(Lead)
//  - Attaches latest ContentVersion via msg.setEntityAttachments(new Id[]{ContentVersionId})

public with sharing class LeadResumeEmailAction {

    public class Request {
        @InvocableVariable(required=true)
        public Id leadId;

        @InvocableVariable(required=true)
        public Id emailTemplateId;

        @InvocableVariable(required=true)
        public String orgWideFromAddress;

        @InvocableVariable(required=true)
        public Id contentDocumentId;
    }

    public class Response {
        @InvocableVariable
        public Boolean success;

        @InvocableVariable
        public String message;
    }

    @InvocableMethod(
        label='Send Lead Email Template + Attach File'
        description='Send EmailTemplate to Lead and attach latest File version by ContentDocumentId.'
    )
    public static List<Response> send(List<Request> requests) {
        List<Response> results = new List<Response>();

        if (requests == null || requests.isEmpty()) {
            Response r0 = new Response();
            r0.success = false;
            r0.message = 'No requests provided.';
            results.add(r0);
            return results;
        }

        for (Request req : requests) {
            Response r = new Response();
            r.success = false;

            try {
                // Validate inputs (no throwing custom exceptions; return clean message)
                if (req == null) {
                    r.message = 'Request is null.';
                    results.add(r);
                    continue;
                }
                if (req.leadId == null) {
                    r.message = 'Missing leadId.';
                    results.add(r);
                    continue;
                }
                if (req.emailTemplateId == null) {
                    r.message = 'Missing emailTemplateId.';
                    results.add(r);
                    continue;
                }
                if (String.isBlank(req.orgWideFromAddress)) {
                    r.message = 'Missing orgWideFromAddress.';
                    results.add(r);
                    continue;
                }
                if (req.contentDocumentId == null) {
                    r.message = 'Missing contentDocumentId.';
                    results.add(r);
                    continue;
                }

                // Confirm lead exists and has email
                Lead l = [
                    SELECT Id, Email
                    FROM Lead
                    WHERE Id = :req.leadId
                    LIMIT 1
                ];
                if (String.isBlank(l.Email)) {
                    r.message = 'Lead has no Email value; cannot send.';
                    results.add(r);
                    continue;
                }

                // Find Org-Wide Email Address by actual address
                List<OrgWideEmailAddress> oweaList = [
                    SELECT Id, Address
                    FROM OrgWideEmailAddress
                    WHERE Address = :req.orgWideFromAddress
                    LIMIT 1
                ];
                if (oweaList.isEmpty()) {
                    r.message = 'OrgWideEmailAddress not found for: ' + req.orgWideFromAddress;
                    results.add(r);
                    continue;
                }
                OrgWideEmailAddress owea = oweaList[0];

                // Get latest ContentVersion for the ContentDocument
                List<ContentVersion> cvList = [
                    SELECT Id, Title, FileType, ContentDocumentId, ContentSize, VersionNumber
                    FROM ContentVersion
                    WHERE ContentDocumentId = :req.contentDocumentId
                    ORDER BY VersionNumber DESC
                    LIMIT 1
                ];
                if (cvList.isEmpty()) {
                    r.message = 'No ContentVersion found for ContentDocumentId: ' + String.valueOf(req.contentDocumentId);
                    results.add(r);
                    continue;
                }
                ContentVersion cv = cvList[0];

                // Build email
                Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
                msg.setOrgWideEmailAddressId(owea.Id);

                // Template + Lead recipient
                msg.setTemplateId(req.emailTemplateId);
                msg.setTargetObjectId(l.Id);
                msg.setTreatTargetObjectAsRecipient(true);

                // No activity/task
                msg.setSaveAsActivity(false);

                // Attach Salesforce File (ContentVersion)
                msg.setEntityAttachments(new Id[] { cv.Id });

                // Send
                Messaging.SendEmailResult[] sendResults =
                    Messaging.sendEmail(new Messaging.SingleEmailMessage[] { msg }, false);

                if (sendResults == null || sendResults.isEmpty()) {
                    r.message = 'sendEmail returned no results.';
                    results.add(r);
                    continue;
                }

                if (!sendResults[0].isSuccess()) {
                    String err = 'sendEmail failed.';
                    Messaging.SendEmailError[] errs = sendResults[0].getErrors();
                    if (errs != null && !errs.isEmpty()) {
                        err = errs[0].getMessage();
                    }
                    r.message = err;
                    results.add(r);
                    continue;
                }

                r.success = true;
                r.message =
                    'EMAIL_SENT_WITH_ENTITY_ATTACHMENT'
                    + ' | ContentVersionId=' + String.valueOf(cv.Id)
                    + ' | Title=' + String.valueOf(cv.Title)
                    + ' | Size=' + String.valueOf(cv.ContentSize);

            } catch (Exception e) {
                // Catch-all for unexpected Apex/SOQL/Messaging errors
                r.success = false;
                r.message = 'Apex error: ' + e.getMessage();
            }

            results.add(r);
        }

        return results;
    }
}
