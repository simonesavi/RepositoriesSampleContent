param workspace string

resource workspace_ASimDnsMicrosoftOMS 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  name: '${workspace}/ASimDnsMicrosoftOMS'
  location: resourceGroup().location
  properties: {
    etag: '*'
    displayName: 'Microsoft DNS'
    category: 'Security'
    functionAlias: 'ASimDnsMicrosoftOMS'
    query: 'let RCodeTable=datatable(ResponseCode:int,ResponseCodeName:string)[\n   0, \'NOERROR\'\n , 1, "FORMERR"\n , 2,"SERVFAIL"\n , 3,\'NXDOMAIN\'\n , 4,\'NOTIMP\'\n , 5,\'REFUSED\'\n , 6,\'YXDOMAIN\'\n , 7,\'YXRRSET\'\n , 8,\'NXRRSET\'\n , 9,\'NOTAUTH\'\n , 10,\'NOTZONE\'\n , 11,\'DSOTYPENI\'\n , 16,\'BADVERS\'\n , 16,\'BADSIG\'\n , 17,\'BADKEY\'\n , 18,\'BADTIME\'\n , 19,\'BADMODE\'\n , 20,\'BADNAME\'\n , 21,\'BADALG\'\n , 22,\'BADTRUNC\'\n , 23,\'BADCOOKIE\'];\nlet DNSQuery_MS=(disabled:bool=false){\n  DnsEvents | where not(disabled)\n|  where EventId in (257,258)\n| project-rename\n       Dvc=Computer ,\n       SrcIpAddr = ClientIP,\n       DnsQueryTypeName=QueryType,\n       EventMessage = Message,\n       EventReportUrl = ReportReferenceLink,\n       DnsResponseName = IPAddresses,\n       DnsQuery = Name,\n       ResponseCode = ResultCode\n| extend\n// ******************* Mandatory\n       EventCount=int(1),\n       EventStartTime=TimeGenerated,\n       EventVendor = "Microsoft",\n       EventProduct = "Microsoft DNS Server",\n       EventSchemaVersion="0.1.1",\n       //\n       EventEndTime=TimeGenerated,\n       EventSubType=\'response\',\n       EventSeverity = tostring(Severity),\n       EventType = \'lookup\',\n       DvcHostname = Dvc,\n       EventResult = iff(EventId==257 and ResponseCode==0 ,\'Success\',\'Failure\')\n   | lookup RCodeTable on ResponseCode\n   | extend EventResultDetails = case (isnotempty(ResponseCodeName), ResponseCodeName\n                                  , ResponseCode between (3841 .. 4095), \'Reserved for Private Use\'\n                                  , \'Unassigned\')\n  // **************Aliases\n  | extend\n      ResponseCodeName=EventResultDetails,\n      Domain=DnsQuery,\n      IpAddr=SrcIpAddr,\n  // Backward Competability\n    Query=DnsQuery\n    , QueryTypeName=DnsQueryTypeName\n    , ResponseName=DnsResponseName\n  // OSSEM \n    , DnsResponseCode=ResponseCode\n    , DnsResponseCodeName=ResponseCodeName\n      };\nDNSQuery_MS(disabled)'
    version: 1
    functionParameters: 'disabled:bool=False'
  }
}
