metadata title = 'Block URL - Palo Alto PAN-OS'
metadata description = 'This playbook allows blocking/allowing of URLs in PAN-OS, using an address object group. The address object group itself should be attached to a pre-defined security policy rule.'
metadata mainSteps = [
  '1.For each URL in the incident, check if URL is already a member of a security policy rule or of the predefined object group.'
  '2. If it isn\'t, an adaptive card is sent to a Teams channel with information about the incident and giving the option to block/unblock the URL by adding/removing it to/from the address object group.'
]
metadata prerequisites = [
  '1. Palo Alto PAN-OS custom connector needs to be deployed prior to the deployment of this playbook, in the same resource group and region (link below).'
  '2. Generate an API key. [Refer this link on how to generate the API Key](https://paloaltolactest.trafficmanager.net/restapi-doc/#tag/key-generation)'
  '3. Address group should be created for PAN-OS, and supply as a deployment parameter.'
]
metadata prerequisitesDeployTemplateFile = '../../PaloAltoCustomConnector/azuredeploy.json'
metadata lastUpdateTime = '2021-07-28T00:00:00.000Z'
metadata entities = [
  'Url'
]
metadata tags = [
  'Remediation'
  'Response from teams'
]
metadata support = {
  tier: 'community'
}
metadata author = {
  name: 'Accenture'
}

@description('Name of the Logic App/Playbook')
param PlaybookName string = 'PaloAlto-PAN-OS-BlockURL'

@description('Name of the custom connector which interacts with PAN-OS')
param CustomConnectorName string = 'PAN-OSCustomConnector'

@description('GroupId of the Team channel')
param Teams_GroupId string = 'TeamgroupId'

@description('Team ChannelId')
param Teams_ChannelId string = 'TeamChannelId'

@description('Address Group')
param Address_Group string = 'AddressGroup'
param workspace string

var AzureSentinelConnectionName = 'azuresentinel-${PlaybookName}'
var TeamsConnectionName = 'teamsconnector-${PlaybookName}'
var PaloAltoConnectorConnectionName = 'PaloAltoConnector-${PlaybookName}'

resource PaloAltoConnectorConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: PaloAltoConnectorConnectionName
  location: resourceGroup().location
  properties: {
    customParameterValues: {}
    api: {
      id: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Web/customApis/${CustomConnectorName}'
    }
  }
}

resource AzureSentinelConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: AzureSentinelConnectionName
  location: resourceGroup().location
  kind: 'V1'
  properties: {
    displayName: AzureSentinelConnectionName
    customParameterValues: {}
    parameterValueType: 'Alternative'
    api: {
      id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/azuresentinel'
    }
  }
}

resource TeamsConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: TeamsConnectionName
  location: resourceGroup().location
  properties: {
    customParameterValues: {}
    api: {
      id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/teams'
    }
  }
}

resource Playbook 'Microsoft.Logic/workflows@2017-07-01' = {
  name: PlaybookName
  location: resourceGroup().location
  tags: {
    'hidden-SentinelTemplateName': 'BlockURL-PAN-OS-ResponseFromTeams'
    'hidden-SentinelTemplateVersion': '1.0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
      }
      triggers: {
        'When_Azure_Sentinel_incident_creation_rule_was_triggered_(Private_Preview_only)': {
          type: 'ApiConnectionWebhook'
          inputs: {
            body: {
              callback_url: '@{listCallbackUrl()}'
            }
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azuresentinel\'][\'connectionId\']'
              }
            }
            path: '/incident-creation'
          }
        }
      }
      actions: {
        Compose_product_name: {
          runAfter: {
            Select_alert_product_names: [
              'Succeeded'
            ]
          }
          type: 'Compose'
          inputs: '@body(\'Select_alert_product_names\')?[0]?[\'text\']'
          description: 'compose to select the incident alert product name'
        }
        Condition_based_on_the_incident_configuration_from_adaptive_card: {
          actions: {
            'Add_comment_to_incident_(V3)': {
              runAfter: {}
              type: 'ApiConnection'
              inputs: {
                body: {
                  incidentArmId: '@triggerBody()?[\'object\']?[\'id\']'
                  message: '<p>PAN-OS Playbook ran and performed the following actions:<br>\n@{variables(\'URLAddressAction\')}<br>\n<br>\n<br>\n<br>\nActions taken on Sentinel : Add comment to incident and closure with classification reason &nbsp;@{body(\'Post_an_Adaptive_Card_to_a_Teams_channel_and_wait_for_a_response\')[\'data\']?[\'incidentStatus\']}</p>'
                }
                host: {
                  connection: {
                    name: '@parameters(\'$connections\')[\'azuresentinel\'][\'connectionId\']'
                  }
                }
                method: 'post'
                path: '/Incidents/Comment'
              }
            }
            Update_incident: {
              runAfter: {
                'Add_comment_to_incident_(V3)': [
                  'Succeeded'
                ]
              }
              type: 'ApiConnection'
              inputs: {
                body: {
                  classification: {
                    ClassificationAndReason: '@{body(\'Post_an_Adaptive_Card_to_a_Teams_channel_and_wait_for_a_response\')[\'data\']?[\'incidentStatus\']}'
                  }
                  incidentArmId: '@triggerBody()?[\'object\']?[\'id\']'
                  severity: '@{body(\'Post_an_Adaptive_Card_to_a_Teams_channel_and_wait_for_a_response\')[\'data\']?[\'incidentSeverity\']}'
                  status: 'Closed'
                }
                host: {
                  connection: {
                    name: '@parameters(\'$connections\')[\'azuresentinel\'][\'connectionId\']'
                  }
                }
                method: 'put'
                path: '/Incidents'
              }
            }
          }
          runAfter: {
            Post_an_Adaptive_Card_to_a_Teams_channel_and_wait_for_a_response: [
              'Succeeded'
            ]
          }
          expression: {
            and: [
              {
                equals: [
                  '@body(\'Post_an_Adaptive_Card_to_a_Teams_channel_and_wait_for_a_response\')[\'submitActionId\']'
                  'Change incident configuration'
                ]
              }
            ]
          }
          type: 'If'
          description: 'This decides the action taken on the summarized adaptive card'
        }
        'Entities_-_Get_URLs': {
          runAfter: {}
          type: 'ApiConnection'
          inputs: {
            body: '@triggerBody()?[\'object\']?[\'properties\']?[\'relatedEntities\']'
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azuresentinel\'][\'connectionId\']'
              }
            }
            method: 'post'
            path: '/entities/url'
          }
        }
        For_each_malicious_URL: {
          foreach: '@body(\'Entities_-_Get_URLs\')?[\'URLs\']'
          actions: {
            Condition_based_on_user_inputs_from_the_adaptive_card: {
              actions: {
                Condition__to_check_if_user_chosen_Block_URL: {
                  actions: {
                    Create_an_address_object: {
                      runAfter: {}
                      type: 'ApiConnection'
                      inputs: {
                        body: {
                          entry: [
                            {
                              '@@name': '@items(\'For_each_malicious_URL\')?[\'Url\']'
                              description: '@items(\'For_each_malicious_URL\')?[\'Url\']'
                              fqdn: '@items(\'For_each_malicious_URL\')?[\'Url\']'
                            }
                          ]
                        }
                        host: {
                          connection: {
                            name: '@parameters(\'$connections\')[\'PaloAltoConnector\'][\'connectionId\']'
                          }
                        }
                        method: 'post'
                        path: '/restapi/v10.0/Objects/Addresses'
                        queries: {
                          'address type': ''
                          location: 'vsys'
                          name: '@items(\'For_each_malicious_URL\')?[\'Url\']'
                          vsys: 'vsys1'
                        }
                      }
                      description: 'This creates a new address object for the malicious URL'
                    }
                  }
                  runAfter: {}
                  expression: {
                    and: [
                      {
                        equals: [
                          '@body(\'Post_an_Adaptive_Card_to_a_Teams_channel_and_wait_for_a_response_3\')[\'submitActionId\']'
                          'Block URL ( add to @{outputs(\'Configured_address_group\')} address group )'
                        ]
                      }
                      {
                        equals: [
                          '@length(body(\'Filter_array_of_URL_address_from_list_of_address_objects\'))'
                          0
                        ]
                      }
                    ]
                  }
                  type: 'If'
                  description: 'This check if user chooses Block URL'
                }
                Condition_to_check_the_edit_an_address_object_group_status: {
                  actions: {
                    Condition_to_check_the_action_of_adaptive_card_to_set_the_action_summary: {
                      actions: {
                        Append_success_status_Blocked_URL_status_to_summary_card: {
                          runAfter: {}
                          type: 'AppendToArrayVariable'
                          inputs: {
                            name: 'URLAddressAction'
                            value: 'URL Address : @{items(\'For_each_malicious_URL\')?[\'Url\']} ,  Action Taken :  Blocked  by               \n                       adding to @{outputs(\'Configured_address_group\')}  ,  Status  :  Success'
                          }
                          description: 'append action taken to summarize on the adaptive card'
                        }
                      }
                      runAfter: {}
                      else: {
                        actions: {
                          Append_success_status_UnBlocked_URL_status_to_summary_card: {
                            runAfter: {}
                            type: 'AppendToArrayVariable'
                            inputs: {
                              name: 'URLAddressAction'
                              value: 'URL Address : @{items(\'For_each_malicious_URL\')?[\'Url\']} ,  Action Taken :  UnBlocked  by               \n                       adding to @{outputs(\'Configured_address_group\')}  ,  Status  :  Success'
                            }
                            description: 'append action taken to summarize on the adaptive card'
                          }
                        }
                      }
                      expression: {
                        and: [
                          {
                            equals: [
                              '@body(\'Post_an_Adaptive_Card_to_a_Teams_channel_and_wait_for_a_response_3\')[\'submitActionId\']'
                              'Block URL ( add to @{outputs(\'Configured_address_group\')} address group )'
                            ]
                          }
                        ]
                      }
                      type: 'If'
                    }
                  }
                  runAfter: {
                    Update_an_address_object_group: [
                      'Succeeded'
                    ]
                  }
                  else: {
                    actions: {
                      Append_failure_status_to_summary_card: {
                        runAfter: {}
                        type: 'AppendToArrayVariable'
                        inputs: {
                          name: 'URLAddressAction'
                          value: 'URL Address : @{items(\'For_each_malicious_URL\')?[\'Url\']}  ,  Action Taken :  @{body(\'Post_an_Adaptive_Card_to_a_Teams_channel_and_wait_for_a_response_3\')[\'submitActionId\']} ,  Status :  Failure'
                        }
                        description: 'append action taken to summarize on the adaptive card'
                      }
                    }
                  }
                  expression: {
                    and: [
                      {
                        equals: [
                          '@body(\'Update_an_address_object_group\')?[\'@status\']'
                          'success'
                        ]
                      }
                    ]
                  }
                  type: 'If'
                }
                Update_an_address_object_group: {
                  runAfter: {
                    Condition__to_check_if_user_chosen_Block_URL: [
                      'Succeeded'
                    ]
                  }
                  type: 'ApiConnection'
                  inputs: {
                    body: {
                      entry: {
                        '@@name': Address_Group
                        static: {
                          member: '@{variables(\'AddressGroupMembers\')}'
                        }
                      }
                    }
                    host: {
                      connection: {
                        name: '@parameters(\'$connections\')[\'PaloAltoConnector\'][\'connectionId\']'
                      }
                    }
                    method: 'put'
                    path: '/restapi/v10.0/Objects/AddressGroups'
                    queries: {
                      location: 'vsys'
                      name: Address_Group
                      vsys: 'vsys1'
                    }
                  }
                }
              }
              runAfter: {
                Post_an_Adaptive_Card_to_a_Teams_channel_and_wait_for_a_response_3: [
                  'Succeeded'
                ]
              }
              else: {
                actions: {
                  Append_to_array_variable_URL_address_action_chosen: {
                    runAfter: {}
                    type: 'AppendToArrayVariable'
                    inputs: {
                      name: 'URLAddressAction'
                      value: 'URL Address : @{items(\'For_each_malicious_URL\')?[\'Url\']},  Action Taken :  @{body(\'Post_an_Adaptive_Card_to_a_Teams_channel_and_wait_for_a_response_3\')[\'submitActionId\']} ,  Status :  Success                                               '
                    }
                    description: 'This appends the action taken on URL to the list of existing actions'
                  }
                }
              }
              expression: {
                and: [
                  {
                    not: {
                      equals: [
                        '@body(\'Post_an_Adaptive_Card_to_a_Teams_channel_and_wait_for_a_response_3\')[\'submitActionId\']'
                        'Ignore'
                      ]
                    }
                  }
                ]
              }
              type: 'If'
              description: 'condition to check the submit action is block / unblock or Ignore'
            }
            Condition_to_check_if_URL_address_already_present_in_list_of_address_objects: {
              actions: {
                Condition_to_check_if_URL_already_present_in_predefined_address_group: {
                  actions: {
                    Append_address_group_text: {
                      runAfter: {}
                      type: 'AppendToArrayVariable'
                      inputs: {
                        name: 'AdaptiveCardBody'
                        value: {
                          text: 'The URL @{items(\'For_each_malicious_URL\')?[\'Url\']}  is already a member of the blocked address group @{outputs(\'Configured_address_group\')}'
                          type: 'TextBlock'
                          wrap: true
                        }
                      }
                      description: 'append address group text to adaptive card dynamically'
                    }
                    Filter_array_URL_address_from_the_list_of_address_objects_to_unreference: {
                      runAfter: {
                        Set_dynamic_action_name: [
                          'Succeeded'
                        ]
                      }
                      type: 'Query'
                      inputs: {
                        from: '@variables(\'AddressGroupMembers\')'
                        where: '@not(equals(item(), items(\'For_each_malicious_URL\')?[\'Url\']))'
                      }
                      description: 'This filters the URL address from predefined address group to unreference/unblock URL'
                    }
                    Set_dynamic_action_name: {
                      runAfter: {
                        Append_address_group_text: [
                          'Succeeded'
                        ]
                      }
                      type: 'SetVariable'
                      inputs: {
                        name: 'ActionName'
                        value: 'UnBlock URL'
                      }
                      description: 'variable to set action name dynamically'
                    }
                    unreference_URL_address_from_the_existing_group_members: {
                      runAfter: {
                        Filter_array_URL_address_from_the_list_of_address_objects_to_unreference: [
                          'Succeeded'
                        ]
                      }
                      type: 'SetVariable'
                      inputs: {
                        name: 'AddressGroupMembers'
                        value: '@body(\'Filter_array_URL_address_from_the_list_of_address_objects_to_unreference\')'
                      }
                      description: 'unreference URL address from the group members and update'
                    }
                  }
                  runAfter: {}
                  else: {
                    actions: {
                      Append_URL_address_to_the_address_group_members: {
                        runAfter: {
                          Append_address_group_text_to_adaptive_card_body: [
                            'Succeeded'
                          ]
                        }
                        type: 'AppendToArrayVariable'
                        inputs: {
                          name: 'AddressGroupMembers'
                          value: '@items(\'For_each_malicious_URL\')?[\'Url\']'
                        }
                        description: 'append URL address to the address group members'
                      }
                      Append_address_group_text_to_adaptive_card_body: {
                        runAfter: {}
                        type: 'AppendToArrayVariable'
                        inputs: {
                          name: 'AdaptiveCardBody'
                          value: {
                            text: 'The URL @{items(\'For_each_malicious_URL\')?[\'Url\']}  is not a member of the blocked address group @{outputs(\'Configured_address_group\')}'
                            type: 'TextBlock'
                            wrap: true
                          }
                        }
                        description: 'append address group text to adaptive card dynamically'
                      }
                      Set_dynamic_action_name_to_variable_Action_name: {
                        runAfter: {
                          Append_URL_address_to_the_address_group_members: [
                            'Succeeded'
                          ]
                        }
                        type: 'SetVariable'
                        inputs: {
                          name: 'ActionName'
                          value: 'Block URL'
                        }
                        description: 'set action name dynamically'
                      }
                    }
                  }
                  expression: {
                    and: [
                      {
                        contains: [
                          '@variables(\'AddressGroupMembers\')'
                          '@items(\'For_each_malicious_URL\')?[\'Url\']'
                        ]
                      }
                    ]
                  }
                  type: 'If'
                  description: 'condition to check the malicious URL address is present in the predefined address group and the URL is part of static member'
                }
              }
              runAfter: {
                Condition_to_check_if_the_URL_is_a_part_of_security_policy_rules: [
                  'Succeeded'
                ]
              }
              else: {
                actions: {
                  Append_URL_to_array_of_address_group_members: {
                    runAfter: {
                      Append_to_array_variable_text_if_URL_is_not_a_member_of_blocked_address_group: [
                        'Succeeded'
                      ]
                    }
                    type: 'AppendToArrayVariable'
                    inputs: {
                      name: 'AddressGroupMembers'
                      value: '@items(\'For_each_malicious_URL\')?[\'Url\']'
                    }
                    description: 'append the Malicious URL address to the existing group members to block / unblock from the predefined address group'
                  }
                  Append_to_array_variable_text_if_URL_is_not_a_member_of_blocked_address_group: {
                    runAfter: {}
                    type: 'AppendToArrayVariable'
                    inputs: {
                      name: 'AdaptiveCardBody'
                      value: {
                        text: 'The URL @{items(\'For_each_malicious_URL\')?[\'Url\']}  is not a member of the blocked address group @{outputs(\'Configured_address_group\')}'
                        type: 'TextBlock'
                        wrap: true
                      }
                    }
                    description: 'This appends the text to display If URL is not a member of security policy rules'
                  }
                  Set_variable_to_Block_URL: {
                    runAfter: {
                      Append_URL_to_array_of_address_group_members: [
                        'Succeeded'
                      ]
                    }
                    type: 'SetVariable'
                    inputs: {
                      name: 'ActionName'
                      value: 'Block URL'
                    }
                    description: 'This sets the variable block URL'
                  }
                }
              }
              expression: {
                and: [
                  {
                    greater: [
                      '@length(body(\'Filter_array_of_URL_address_from_list_of_address_objects\'))'
                      0
                    ]
                  }
                ]
              }
              type: 'If'
              description: 'This checks if URL is a member of any of the list of address objects'
            }
            Condition_to_check_if_the_URL_is_a_part_of_security_policy_rules: {
              actions: {
                Append_policy_text: {
                  runAfter: {}
                  type: 'AppendToArrayVariable'
                  inputs: {
                    name: 'AdaptiveCardBody'
                    value: {
                      text: 'It is also member of the following security policy rules'
                      type: 'TextBlock'
                    }
                  }
                  description: 'dynamic policy text based on security policies'
                }
                Append_security_policies: {
                  runAfter: {
                    Append_policy_text: [
                      'Succeeded'
                    ]
                  }
                  type: 'AppendToArrayVariable'
                  inputs: {
                    name: 'AdaptiveCardBody'
                    value: {
                      columns: [
                        {
                          items: '@body(\'Select_security_policy_rules\')'
                          type: 'Column'
                        }
                      ]
                      type: 'ColumnSet'
                    }
                  }
                  description: 'append security policies which the URL address is exist'
                }
              }
              runAfter: {
                Select_security_policy_rules: [
                  'Succeeded'
                ]
              }
              else: {
                actions: {
                  Append_policy_text_to_adaptive_card_body_variable: {
                    runAfter: {}
                    type: 'AppendToArrayVariable'
                    inputs: {
                      name: 'AdaptiveCardBody'
                      value: {
                        text: 'It is not a member of any other Policy Rules'
                        type: 'TextBlock'
                      }
                    }
                    description: 'dynamic policy text based on security policies'
                  }
                  Append_security_policies_to_adaptive_card_body_variable: {
                    runAfter: {
                      Append_policy_text_to_adaptive_card_body_variable: [
                        'Succeeded'
                      ]
                    }
                    type: 'AppendToArrayVariable'
                    inputs: {
                      name: 'AdaptiveCardBody'
                      value: {}
                    }
                    description: 'append security policies which the URL address is exist'
                  }
                }
              }
              expression: {
                and: [
                  {
                    greater: [
                      '@length(body(\'Select_security_policy_rules\'))'
                      0
                    ]
                  }
                ]
              }
              type: 'If'
              description: 'condition to check if the URL address is present in the existing security policy rules to conditionally apply the policy text and security policy rules'
            }
            Configured_address_group: {
              runAfter: {
                Set_variable_address_group_members: [
                  'Succeeded'
                ]
              }
              type: 'Compose'
              inputs: '@body(\'List_address_groups\')?[\'result\']?[\'entry\']?[0]?[\'@name\']'
              description: 'compose predefined address group'
            }
            Filter_array_URL_from_list_of_security_rules: {
              runAfter: {
                Configured_address_group: [
                  'Succeeded'
                ]
              }
              type: 'Query'
              inputs: {
                from: '@body(\'List_security_rules\')?[\'result\']?[\'entry\']'
                where: '@contains(item()?[\'destination\']?[\'member\'], items(\'For_each_malicious_URL\')?[\'Url\'])'
              }
              description: 'This filters all the security rules in which this URL is a member'
            }
            Filter_array_of_URL_address_from_list_of_address_objects: {
              runAfter: {
                Set_variable_adaptive_card_body: [
                  'Succeeded'
                ]
              }
              type: 'Query'
              inputs: {
                from: '@body(\'List_address_objects\')?[\'result\']?[\'entry\']'
                where: '@equals(item()?[\'fqdn\'], items(\'For_each_malicious_URL\')?[\'Url\'])'
              }
              description: 'This filters the list of address objects in which this URL is a member '
            }
            List_address_groups: {
              runAfter: {
                Filter_array_of_URL_address_from_list_of_address_objects: [
                  'Succeeded'
                ]
              }
              type: 'ApiConnection'
              inputs: {
                host: {
                  connection: {
                    name: '@parameters(\'$connections\')[\'PaloAltoConnector\'][\'connectionId\']'
                  }
                }
                method: 'get'
                path: '/restapi/v10.0/Objects/AddressGroups'
                queries: {
                  location: 'vsys'
                  name: Address_Group
                  vsys: 'vsys1'
                }
              }
              description: 'This gets complete list of address object groups present in the PAN-OS'
            }
            Post_an_Adaptive_Card_to_a_Teams_channel_and_wait_for_a_response_3: {
              runAfter: {
                Condition_to_check_if_URL_address_already_present_in_list_of_address_objects: [
                  'Succeeded'
                ]
              }
              type: 'ApiConnectionWebhook'
              inputs: {
                body: {
                  body: {
                    messageBody: '{\n    "type": "AdaptiveCard",\n    "body":@{variables(\'AdaptiveCardBody\')} ,\n     "actions": [\n  {\n    "title": "@{variables(\'ActionName\')} ( add to @{outputs(\'Configured_address_group\')} address group )",\n    "type": "Action.Submit"\n  },\n  {\n    "title": "Ignore",\n    "type": "Action.Submit"\n  }\n],\n    "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",\n    "version": "1.2"\n}'
                    recipient: {
                      channelId: Teams_ChannelId
                    }
                    shouldUpdateCard: true
                  }
                  notificationUrl: '@{listCallbackUrl()}'
                }
                host: {
                  connection: {
                    name: '@parameters(\'$connections\')[\'teams\'][\'connectionId\']'
                  }
                }
                path: '/flowbot/actions/flowcontinuation/recipienttypes/channel/$subscriptions'
                queries: {
                  groupId: Teams_GroupId
                }
              }
            }
            Select_security_policy_rules: {
              runAfter: {
                Filter_array_URL_from_list_of_security_rules: [
                  'Succeeded'
                ]
              }
              type: 'Select'
              inputs: {
                from: '@body(\'Filter_array_URL_from_list_of_security_rules\')'
                select: {
                  text: ' @{item()?[\'@name\']}, action :  @{item()?[\'action\']}'
                  type: 'TextBlock'
                  weight: 'bolder'
                }
              }
              description: 'prepare columns list to show the security policy rules in the adaptive card if URL address is present'
            }
            Set_variable_adaptive_card_body: {
              runAfter: {}
              type: 'SetVariable'
              inputs: {
                name: 'AdaptiveCardBody'
                value: [
                  {
                    size: 'Large'
                    text: 'Suspicious URL - Azure Sentinel'
                    type: 'TextBlock'
                    weight: 'Bolder'
                    wrap: true
                  }
                  {
                    text: 'Possible Comprised URL @{items(\'For_each_malicious_URL\')?[\'Url\']} detected by the provider : @{outputs(\'Compose_product_name\')}'
                    type: 'TextBlock'
                    wrap: true
                  }
                  {
                    text: '@{triggerBody()?[\'object\']?[\'properties\']?[\'severity\']}  Incident  @{triggerBody()?[\'object\']?[\'properties\']?[\'title\']}'
                    type: 'TextBlock'
                    weight: 'Bolder'
                    wrap: true
                  }
                  {
                    text: ' Incident No : @{triggerBody()?[\'object\']?[\'properties\']?[\'incidentNumber\']}  '
                    type: 'TextBlock'
                    weight: 'Bolder'
                    wrap: true
                  }
                  {
                    text: 'Incident description'
                    type: 'TextBlock'
                    weight: 'Bolder'
                    wrap: true
                  }
                  {
                    text: '@{triggerBody()?[\'object\']?[\'properties\']?[\'description\']}'
                    type: 'TextBlock'
                    wrap: true
                  }
                  {
                    text: '[[[Click here to view the Incident](@{triggerBody()?[\'object\']?[\'properties\']?[\'incidentUrl\']})'
                    type: 'TextBlock'
                    wrap: true
                  }
                  {
                    size: 'Medium'
                    text: 'Response in PAN-OS'
                    type: 'TextBlock'
                    weight: 'Bolder'
                  }
                  {
                    size: 'Small'
                    style: 'Person'
                    type: 'Image'
                    url: 'https://avatars2.githubusercontent.com/u/4855743?s=280&v=4'
                  }
                ]
              }
              description: 'variable to hold adaptive card body'
            }
            Set_variable_address_group_members: {
              runAfter: {
                List_address_groups: [
                  'Succeeded'
                ]
              }
              type: 'SetVariable'
              inputs: {
                name: 'AddressGroupMembers'
                value: '@body(\'List_address_groups\')?[\'result\']?[\'entry\']?[0]?[\'static\']?[\'member\']'
              }
              description: 'assign list of address group members'
            }
          }
          runAfter: {
            List_security_rules: [
              'Succeeded'
            ]
          }
          type: 'Foreach'
          runtimeConfiguration: {
            concurrency: {
              repetitions: 1
            }
          }
        }
        Initialize_variable_URL_address_action: {
          runAfter: {
            Initialize_variable_address_group_members: [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'URLAddressAction'
                type: 'array'
              }
            ]
          }
          description: 'This holds the action taken on each URL '
        }
        Initialize_variable_action_name: {
          runAfter: {
            'Entities_-_Get_URLs': [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'ActionName'
                type: 'string'
              }
            ]
          }
          description: 'variable to store action name to be displayed on adaptive card'
        }
        Initialize_variable_adaptive_card_body: {
          runAfter: {
            Initialize_variable_action_name: [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'AdaptiveCardBody'
                type: 'array'
              }
            ]
          }
          description: 'variable to store adaptive card body json'
        }
        Initialize_variable_address_group_members: {
          runAfter: {
            Initialize_variable_adaptive_card_body: [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'AddressGroupMembers'
                type: 'array'
              }
            ]
          }
          description: 'variable to store the list of address group members'
        }
        List_address_objects: {
          runAfter: {
            Compose_product_name: [
              'Succeeded'
            ]
          }
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'PaloAltoConnector\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/restapi/v10.0/Objects/Addresses'
            queries: {
              location: 'vsys'
              vsys: 'vsys1'
            }
          }
          description: 'This gets complete list of address object present in the PAN-OS'
        }
        List_security_rules: {
          runAfter: {
            List_address_objects: [
              'Succeeded'
            ]
          }
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'PaloAltoConnector\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/restapi/v10.0/Policies/SecurityRules'
            queries: {
              location: 'vsys'
              vsys: 'vsys1'
            }
          }
          description: 'This gets complete list of security policy rules present in the PAN-OS'
        }
        Post_an_Adaptive_Card_to_a_Teams_channel_and_wait_for_a_response: {
          runAfter: {
            Set_variable_actions_on_URL_to_be_displayed_on_adaptive_card: [
              'Succeeded'
            ]
          }
          type: 'ApiConnectionWebhook'
          inputs: {
            body: {
              body: {
                messageBody: '{\n    "type": "AdaptiveCard",\n    "body": [\n        {\n            "type": "TextBlock",\n           \n            "weight": "Bolder",\n            "text": "Below is the summary of actions taken on URL\'s by SOC",\n            "wrap": true\n        },\n    {\n  "columns": [\n    {\n      "items":@{body(\'Set_variable_actions_on_URL_to_be_displayed_on_adaptive_card\')} ,\n      "type": "Column",\n      "wrap": true\n    }\n  ],\n  "separator": "true",\n  "type": "ColumnSet",\n  "width": "stretch"\n},\n {\n    "text": " Incident No : @{triggerBody()?[\'object\']?[\'properties\']?[\'incidentNumber\']}  ",\n    "type": "TextBlock",\n    "weight": "Bolder",\n    "wrap": true\n  },\n        {\n            "type": "TextBlock",\n            "text": "[Click here to view the Incident](@{triggerBody()?[\'object\']?[\'properties\']?[\'incidentUrl\']})",\n            "wrap": true\n        },\n\n        {\n            "type": "ColumnSet",\n            "columns": [\n                {\n                    "type": "Column",\n                    "items": [\n                        {\n                            "type": "TextBlock",\n                            "size": "Medium",\n                            "weight": "Bolder",\n                            "text": "Incident configuration :",\n                            "wrap": true\n                        }\n                    ],\n                    "width": "auto"\n                }\n            ]\n        },\n        {\n            "type": "ColumnSet",\n            "columns": [\n                {\n                    "type": "Column",\n                    "items": [\n                        {\n                            "type": "Image",\n                            "style": "Person",\n                            "url": "https://connectoricons-prod.azureedge.net/releases/v1.0.1391/1.0.1391.2130/azuresentinel/icon.png",\n                            "size": "Small"\n                        }\n                    ],\n                    "width": "auto"\n                }\n            ]\n        },\n        {\n            "type": "TextBlock",\n            "text": "Close Azure Sentinal incident?"\n        },\n        {\n            "choices": [\n                {\n                    "isSelected": true,\n                    "title": "False Positive - Inaccurate Data",\n                    "value": "False Positive - Inaccurate Data"\n                },\n                {\n                    "isSelected": true,\n                    "title": "False Positive - Incorrect Alert Logic",\n                    "value": "False Positive - Incorrect Alert Logic"\n                },\n                {\n                    "title": "True Positive - Suspicious Activity",\n                    "value": "True Positive - Suspicious Activity"\n                },\n                {\n                    "title": "Benign Positive - Suspicious But Expected",\n                    "value": "Benign Positive - Suspicious But Expected"\n                },\n                {\n                    "title": "Undetermined",\n                    "value": "Undetermined"\n                }\n            ],\n            "id": "incidentStatus",\n            "style": "compact",\n            "type": "Input.ChoiceSet",\n            "value": "Benign Positive - Suspicious But Expected"\n        },\n        {\n            "type": "TextBlock",\n            "text": "Change Azure Sentinel Incident Severity?"\n        },\n        {\n            "choices": [\n                {\n                  \n                    "title": "High",\n                    "value": "High"\n                },\n                {\n                    "title": "Medium",\n                    "value": "Medium"\n                },\n                {\n                    "title": "Low",\n                    "value": "Low"\n                },\n                {\n                    "title": "Don\'t change",\n                    "value": "same"\n                }\n            ],\n            "id": "incidentSeverity",\n            "style": "compact",\n            "type": "Input.ChoiceSet",\n            "value": "@{triggerBody()?[\'object\']?[\'properties\']?[\'severity\']}"\n        }\n       \n     \n        \n    ],\n"width":"auto",\n   "actions": [\n                    {\n                        "type": "Action.Submit",\n                        "title": "Change incident configuration"\n                    },\n  {\n                        "type": "Action.Submit",\n                        "title": "Ignore"\n                    }\n   ],\n    "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",\n    "version": "1.2"\n}'
                recipient: {
                  channelId: Teams_ChannelId
                }
                shouldUpdateCard: true
              }
              notificationUrl: '@{listCallbackUrl()}'
            }
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'teams\'][\'connectionId\']'
              }
            }
            path: '/flowbot/actions/flowcontinuation/recipienttypes/channel/$subscriptions'
            queries: {
              groupId: Teams_GroupId
            }
          }
        }
        Select_alert_product_names: {
          runAfter: {
            Initialize_variable_URL_address_action: [
              'Succeeded'
            ]
          }
          type: 'Select'
          inputs: {
            from: '@triggerBody()?[\'object\']?[\'properties\']?[\'additionalData\']?[\'alertProductNames\']'
            select: {
              text: '@item()'
            }
          }
          description: 'data operator to select the alert product name'
        }
        Set_variable_actions_on_URL_to_be_displayed_on_adaptive_card: {
          runAfter: {
            For_each_malicious_URL: [
              'Succeeded'
            ]
          }
          type: 'Select'
          inputs: {
            from: '@variables(\'URLAddressAction\')'
            select: {
              text: '@item()'
              type: 'TextBlock'
            }
          }
          description: 'This is used to compose the list of actions taken by SOC on respective URL addresses'
        }
      }
      outputs: {}
    }
    parameters: {
      '$connections': {
        value: {
          PaloAltoConnector: {
            connectionId: PaloAltoConnectorConnection.id
            connectionName: PaloAltoConnectorConnectionName
            id: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Web/customApis/${CustomConnectorName}'
          }
          azuresentinel: {
            connectionId: AzureSentinelConnection.id
            connectionName: AzureSentinelConnectionName
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/azuresentinel'
            connectionProperties: {
              authentication: {
                type: 'ManagedServiceIdentity'
              }
            }
          }
          teams: {
            connectionId: TeamsConnection.id
            connectionName: TeamsConnectionName
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/teams'
          }
        }
      }
    }
  }
}
