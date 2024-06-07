# HelloID-Conn-Prov-Target-Medicore

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-Medicore](#helloid-conn-prov-target-Medicore)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Getting started](#getting-started)
    - [Provisioning PowerShell V2 connector](#provisioning-powershell-connector)
      - [Correlation configuration](#correlation-configuration)
      - [Field mapping](#field-mapping)
    - [Connection settings](#connection-settings)
    - [Prerequisites](#prerequisites)
    - [Remarks](#remarks)
  - [Setup the connector](#setup-the-connector)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-Medicore_ is a _target_ connector. _Medicore_ provides a set of REST API's that allow you to programmatically interact with its data.
This connector manages users in Medicore, including templates and locations.

The following lifecycle actions are available:

| Action                     | Description                                                                             |
| -------------------------- | --------------------------------------------------------------------------------------- |
| create.ps1                 | Default PowerShell _create_ lifecycle action, including location and template mapping   |
| disable.ps1                | Default PowerShell _disable_ lifecycle action                                           |
| enable.ps1                 | Default PowerShell _enable_ lifecycle action                                            |
| update.ps1                 | Default PowerShell _update_ lifecycle action, including updating locations and template |
| configuration.json         | Default _configuration.json_                                                            |
| fieldMapping.json          | Default _fieldMapping.json_                                                             |
| Assets/LocationMapping.csv | Default example _LocationMapping.json_                                                  |
| Assets/TemplateMapping.csv | Default example _TemplateMapping.json_                                                  |

## Getting started

### Provisioning PowerShell V2 connector

#### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _Medicore_ to a person in _HelloID_.

To properly setup the correlation:

1. Open the `Correlation` tab.

2. Specify the following configuration:

   | Setting                   | Value                             |
   | ------------------------- | --------------------------------- |
   | Enable correlation        | `True`                            |
   | Person correlation field  | `PersonContext.Person.ExternalId` |
   | Account correlation field | `hrNumber`                        |

> [!TIP] > _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-target-systems/correlation.html) pages_.

#### Field mapping

The field mapping can be imported by using the _fieldMapping.json_ file.

### Connection settings

The following settings are required to connect to the API.

| Setting                | Description                                | Mandatory |
| ---------------------- | ------------------------------------------ | --------- |
| UserName               | The UserName to connect to the API         | Yes       |
| Password               | The Password to connect to the API         | Yes       |
| client_id              | The client ID to connect to the API        | Yes       |
| client_secret          | The client secret to connect to the API    | Yes       |
| OcpApimSubscriptionKey | The subscription key to connect to the API | Yes       |
| BaseUrl                | The URL to the API                         | Yes       |
| TokenUrl               | The URL to generate the bearer token       | Yes       |

### Prerequisites

### Remarks

> Due to the limitations of the field mapping, which can only return strings or an array of strings, it is necessary to perform type conversions for the properties: 'gender', 'isAttendingPhysician' and 'isPatientBound' to correctly send them to the API.

> The comparison process during updates has a different approach for the 'locations' property because it is an array.


### Remarks CSV Mapping

> To prevent having a large number of business rules, the connector comes with two csv mapping files. One for the template (templatemapping.csv) and one for locations (locationMapping.csv), these can be found in the Assets folder. Each person can be linked to one template but multiple locations, allowing for flexible and efficient management of user access.

In the mapping files, you will find the properties HelloIdDepartment and HelloIdTitle. The values of these properties should match the values in your HelloID contract. The last two properties, LocationName and LocationId (or the corresponding properties for the template), refer to the MediCore location or template needed for that specific department or title.

> The connector is designed with the assumption that the fields 'abbreviations' and 'username' are populated with the User Principal Name (UPN) from Active Directory (AD). This ensures uniqueness for each entry, eliminating the need for an additional uniqueness script. If you want to populate these properties with different values, remember to also create a uniqueness script.

> In the create and update scripts, you will find the following two lines of code:

```
$locationLookupField1 = { $_.Department.ExternalId } # Mandatory
$locationLookupField2 = { $_.Title.ExternalId }      # Not mandatory
```

These lines are used to select the properties on which we loop through for every single contract that falls within the scope of the business rules. This process results in a list of departments and titles, which need to exist in the `LocationMapping.csv` file to obtain the corresponding MediCore location ID.



## Setup the connector

> _How to setup the connector in HelloID._ Are special settings required. Like the _primary manager_ settings for a source connector.

## Getting help

> [!TIP] > _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-target-systems.html) pages_.

> [!TIP] > _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
