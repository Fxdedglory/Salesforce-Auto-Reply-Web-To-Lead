Database.LeadConvert lc = new Database.LeadConvert();
lc.setLeadId('00QgK00000BD7OjUAL');
lc.setConvertedStatus('Closed - Converted');
lc.setDoNotCreateOpportunity(true);
Database.LeadConvertResult res = Database.convertLead(lc);
System.debug('Converted=' + res.isSuccess() + ' ContactId=' + res.getContactId() + ' AccountId=' + res.getAccountId());
