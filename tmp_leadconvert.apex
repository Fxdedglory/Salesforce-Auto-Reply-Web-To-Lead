Lead l = [SELECT Id FROM Lead WHERE Id = '00QgK00000BDAknUAH' LIMIT 1];
LeadStatus cs = [SELECT MasterLabel FROM LeadStatus WHERE IsConverted = true LIMIT 1];

Database.LeadConvert lc = new Database.LeadConvert();
lc.setLeadId(l.Id);
lc.setConvertedStatus(cs.MasterLabel);
lc.setDoNotCreateOpportunity(true);

Database.LeadConvertResult r = Database.convertLead(lc);

System.debug('LEADCONVERT_SUCCESS=' + r.isSuccess());
System.debug('LEADCONVERT_CONTACTID=' + r.getContactId());
System.debug('LEADCONVERT_ACCOUNTID=' + r.getAccountId());