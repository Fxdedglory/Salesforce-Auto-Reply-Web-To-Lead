// v1.0 | 2026-02-17
// Purpose: Send an auto-reply email to a Lead with a Salesforce File attached (resume).
public with sharing class LeadAutoReplyWithAttachment {

    public class Request {
        @InvocableVariable(required=true)
        public Id leadId;

        // Optional: pass LatestPublishedVersionId or a ContentDocumentId
        @InvocableVariable(required=false)
        public Id contentVersionId;

        @InvocableVariable(required=false)
        public Id contentDocumentId;

        @InvocableVariable(required=false)
        public String subject;

        @InvocableVariable(required=false)
        public String bodyText;
    }

    public class Result {
        @InvocableVariable public Boolean success;
        @InvocableVariable public String message;
    }

    @InvocableMethod(label='Send Lead Auto Reply (With Resume Attachment)')
    public static List<Result> send(List<Request> requests) {
        List<Result> results = new List<Result>();

        // Org-wide from address
        OrgWideEmailAddress owea = [
            SELECT Id, Address, DisplayName
            FROM OrgWideEmailAddress
            WHERE Address = 'tim@teemails.com'
            LIMIT 1
        ];

        // Process each request
        for (Request req : requests) {
            Result r = new Result();
            r.success = false;

            try {
                Lead l = [
                    SELECT Id, Email, FirstName, LastName
                    FROM Lead
                    WHERE Id = :req.leadId
                    LIMIT 1
                ];

                if (String.isBlank(l.Email)) {
                    r.message = 'Lead.Email is blank.';
                    results.add(r);
                    continue;
                }

                // Resolve ContentVersion Id (priority: explicit VersionId -> DocumentId -> latest by Title)
                Id versionId = req.contentVersionId;

                if (versionId == null && req.contentDocumentId != null) {
                    ContentVersion cv = [
                        SELECT Id
                        FROM ContentVersion
                        WHERE ContentDocumentId = :req.contentDocumentId
                        ORDER BY VersionNumber DESC
                        LIMIT 1
                    ];
                    versionId = cv.Id;
                }

                if (versionId == null) {
                    // Fallback: latest file whose title starts with "Resume"
                    ContentVersion cv = [
                        SELECT Id
                        FROM ContentVersion
                        WHERE Title LIKE 'Resume%'
                        ORDER BY CreatedDate DESC
                        LIMIT 1
                    ];
                    versionId = cv.Id;
                }

                ContentVersion resume = [
                    SELECT Id, Title, FileType, VersionData
                    FROM ContentVersion
                    WHERE Id = :versionId
                    LIMIT 1
                ];

                Messaging.EmailFileAttachment efa = new Messaging.EmailFileAttachment();
                efa.setFileName(resume.Title + '.' + resume.FileType);
                efa.setBody(resume.VersionData);

                String subj = String.isBlank(req.subject)
                    ? 'Demo CRM – Application Document'
                    : req.subject;

                String body = String.isBlank(req.bodyText)
                    ? 'Hi ' + (String.isBlank(l.FirstName) ? 'there' : l.FirstName) + ',' + '\n\n'
                      + 'Thanks for your interest. Attached is a copy of my resume.' + '\n\n'
                      + 'You can schedule time here: https://calendly.com/sellwood-timm/30min' + '\n\n'
                      + 'Best,' + '\n'
                      + 'Tim Sellwood'
                    : req.bodyText;

                Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
                msg.setToAddresses(new List<String>{ l.Email });
                msg.setSubject(subj);
                msg.setPlainTextBody(body);
                msg.setOrgWideEmailAddressId(owea.Id);
                msg.setFileAttachments(new List<Messaging.EmailFileAttachment>{ efa });

                Messaging.SendEmailResult[] sendRes = Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ msg });

                if (sendRes != null && sendRes.size() == 1 && sendRes[0].isSuccess()) {
                    r.success = true;
                    r.message = 'Sent.';
                } else {
                    r.message = (sendRes != null && sendRes.size() == 1 && sendRes[0].getErrors().size() > 0)
                        ? sendRes[0].getErrors()[0].getMessage()
                        : 'Unknown sendEmail failure.';
                }

            } catch (Exception e) {
                r.message = e.getMessage();
            }

            results.add(r);
        }

        return results;
    }
}
