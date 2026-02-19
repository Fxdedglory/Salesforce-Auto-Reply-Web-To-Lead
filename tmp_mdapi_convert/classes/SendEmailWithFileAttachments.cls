// v0.1.0 | 2026-02-17
// Purpose: Invocable action for Flow to send an email to a Lead and attach up to 2 Salesforce Files
// (by ContentDocumentId). Uses LatestPublishedVersionId to get actual binary data.
//
// Notes:
// - Flow cannot reliably attach Salesforce Files (ContentVersion) without Apex.
// - We attach ContentVersion.VersionData to Messaging.EmailFileAttachment.

public with sharing class SendEmailWithFileAttachments {

    public class Request {
        @InvocableVariable(required=true)
        public Id leadId;

        @InvocableVariable(required=true)
        public String subject;

        @InvocableVariable(required=true)
        public String bodyPlainText;

        // ContentDocument.Id values (069...) – optional
        @InvocableVariable(required=false)
        public Id contentDocumentId1;

        @InvocableVariable(required=false)
        public Id contentDocumentId2;
    }

    public class Response {
        @InvocableVariable
        public Boolean success;

        @InvocableVariable
        public String message;
    }

    @InvocableMethod(label='Send Email With File Attachments' description='Send an email to a Lead and attach up to 2 Salesforce Files by ContentDocumentId.')
    public static List<Response> send(List<Request> requests) {
        List<Response> out = new List<Response>();
        if (requests == null || requests.isEmpty()) return out;

        // Collect Lead IDs
        Set<Id> leadIds = new Set<Id>();
        Set<Id> docIds = new Set<Id>();

        for (Request r : requests) {
            if (r != null && r.leadId != null) leadIds.add(r.leadId);
            if (r != null && r.contentDocumentId1 != null) docIds.add(r.contentDocumentId1);
            if (r != null && r.contentDocumentId2 != null) docIds.add(r.contentDocumentId2);
        }

        // Query Leads
        Map<Id, Lead> leadById = new Map<Id, Lead>();
        if (!leadIds.isEmpty()) {
            for (Lead l : [
                SELECT Id, Email, Name
                FROM Lead
                WHERE Id IN :leadIds
            ]) {
                leadById.put(l.Id, l);
            }
        }

        // Query ContentDocuments -> LatestPublishedVersionId
        Map<Id, ContentDocument> docById = new Map<Id, ContentDocument>();
        if (!docIds.isEmpty()) {
            for (ContentDocument cd : [
                SELECT Id, Title, FileType, LatestPublishedVersionId
                FROM ContentDocument
                WHERE Id IN :docIds
            ]) {
                docById.put(cd.Id, cd);
            }
        }

        // Query ContentVersions for the latest versions
        Set<Id> versionIds = new Set<Id>();
        for (ContentDocument cd : docById.values()) {
            if (cd.LatestPublishedVersionId != null) versionIds.add(cd.LatestPublishedVersionId);
        }

        Map<Id, ContentVersion> verById = new Map<Id, ContentVersion>();
        if (!versionIds.isEmpty()) {
            for (ContentVersion cv : [
                SELECT Id, Title, FileExtension, VersionData
                FROM ContentVersion
                WHERE Id IN :versionIds
            ]) {
                verById.put(cv.Id, cv);
            }
        }

        // Send messages (one per request)
        for (Request r : requests) {
            Response resp = new Response();
            resp.success = false;

            try {
                if (r == null) {
                    resp.message = 'Null request.';
                    out.add(resp);
                    continue;
                }

                Lead l = leadById.get(r.leadId);
                if (l == null) {
                    resp.message = 'Lead not found: ' + String.valueOf(r.leadId);
                    out.add(resp);
                    continue;
                }
                if (String.isBlank(l.Email)) {
                    resp.message = 'Lead has no Email: ' + l.Id;
                    out.add(resp);
                    continue;
                }
                if (String.isBlank(r.subject) || String.isBlank(r.bodyPlainText)) {
                    resp.message = 'Subject/body is required.';
                    out.add(resp);
                    continue;
                }

                Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
                msg.setToAddresses(new String[] { l.Email });
                msg.setSubject(r.subject);
                msg.setPlainTextBody(r.bodyPlainText);

                List<Messaging.EmailFileAttachment> atts = new List<Messaging.EmailFileAttachment>();

                // helper to attach a doc by ContentDocumentId
                attachDoc(r.contentDocumentId1, docById, verById, atts);
                attachDoc(r.contentDocumentId2, docById, verById, atts);

                if (!atts.isEmpty()) {
                    msg.setFileAttachments(atts);
                }

                // Send (not using setTargetObjectId since this is Lead and we want raw email)
                Messaging.SendEmailResult[] results = Messaging.sendEmail(new Messaging.SingleEmailMessage[] { msg }, false);
                if (results != null && !results.isEmpty() && results[0].isSuccess()) {
                    resp.success = true;
                    resp.message = 'Email sent to ' + l.Email + ' (Lead ' + l.Id + '). Attachments=' + atts.size();
                } else {
                    String err = 'Unknown sendEmail failure.';
                    if (results != null && !results.isEmpty() && results[0].getErrors() != null && !results[0].getErrors().isEmpty()) {
                        err = results[0].getErrors()[0].getMessage();
                    }
                    resp.message = 'Send failed: ' + err;
                }
            } catch (Exception e) {
                resp.message = 'Exception: ' + e.getMessage();
            }

            out.add(resp);
        }

        return out;
    }

    private static void attachDoc(
        Id contentDocumentId,
        Map<Id, ContentDocument> docById,
        Map<Id, ContentVersion> verById,
        List<Messaging.EmailFileAttachment> atts
    ) {
        if (contentDocumentId == null) return;

        ContentDocument cd = docById.get(contentDocumentId);
        if (cd == null || cd.LatestPublishedVersionId == null) return;

        ContentVersion cv = verById.get(cd.LatestPublishedVersionId);
        if (cv == null || cv.VersionData == null) return;

        Messaging.EmailFileAttachment att = new Messaging.EmailFileAttachment();

        String ext = cv.FileExtension;
        String filename = cv.Title;
        if (!String.isBlank(ext)) filename = filename + '.' + ext;

        att.setFileName(filename);
        att.setBody(cv.VersionData);
        atts.add(att);
    }
}