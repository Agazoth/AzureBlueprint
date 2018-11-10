# AxAzureBlueprint Module

## Introduction
This module connects to a given tenant and implements an Azure Blueprint based on a collection of json templates in a given folder

The cmdlets in this module can upload Blueprints and Artifacts to Azure Blueprint based on an ARM template. The template must contain a "properties" and a "name" section, it also can contain a "kind" section. If "kind" is omitted, the template is defined as the root blueprint. Only one root blueprint is allowed per Blueprint connection.

kind can be one of these 3:
* policyAssignment
* template
* roleAssignment