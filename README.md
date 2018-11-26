# AxAzureBlueprint Module

## Introduction
This module connects to a given tenant and implements an Azure Blueprint based on a collection of json templates in a given folder

The cmdlets in this module can upload Blueprints and Artifacts to Azure Blueprint based on an ARM template. The template must contain a "properties", it also can contain a "kind" section. If "kind" is omitted, the template is defined as the root blueprint. Only one root blueprint is allowed per Blueprint connection.

The name of the json file is used as the name of the Artifact. The name of the folder containing the Blueprint files is used as name for the Blueprint itself.

Artifact kind can be one of these 3:
* policyAssignment
* template
* roleAssignment

## Import ARM templates to a new or existing blueprint
By using the Import-AzureBlueprintArtifact you can import existing ARM templates and transform them to Blueprint Artifacts and add theparameters to the Blueprint.