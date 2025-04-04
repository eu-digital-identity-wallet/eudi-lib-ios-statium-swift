# EUDI Statium

**Important!** Before you proceed, please read
the [EUDI Wallet Reference Implementation project description](https://github.com/eu-digital-identity-wallet/.github/blob/main/profile/reference-implementation.md)

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://www.apache.org/licenses/LICENSE-2.0)


## Table of contents

* [Overview](#overview)
* [Disclaimer](#disclaimer)
* [Installation](#installation)
* [Use cases supported](#use-cases-supported)
* [How to contribute](#how-to-contribute)
* [License](#license) 

## Overview

Statium is a Swift library for iOS and macOS. 
It implements the Token Status List Specification [draft 10](https://www.ietf.org/archive/id/draft-ietf-oauth-status-list-10.html), 
and allows callers to check the status of a "Referenced Token" as defined in the specification, 
effectively enabling applications to verify if tokens are valid, revoked, or in other states.

> [!NOTE]
> Currently, Statium supports JWT format for the Status List Token.

## Disclaimer

The released software is an initial development release version:
-  The initial development release is an early endeavor reflecting the efforts of a short time-boxed period, and by no means can be considered as the final product.
-  The initial development release may be changed substantially over time, might introduce new features but also may change or remove existing ones, potentially breaking compatibility with your existing code.
-  The initial development release is limited in functional scope.
-  The initial development release may contain errors or design flaws and other problems that could cause system or other failures and data loss.
-  The initial development release has reduced security, privacy, availability, and reliability standards relative to future releases. This could make the software slower, less reliable, or more vulnerable to attacks than mature software.
-  The initial development release is not yet comprehensively documented.
-  Users of the software must perform sufficient engineering and additional testing to properly evaluate their application and determine whether any of the open-sourced components is suitable for use in that application.
-  We strongly recommend not putting this version of the software into production use.
-  Only the latest version of the software will be supported

## Installation

You can add the library to your project using Swift Package Manager.

## Use cases supported

- [Get Status List Token](#get-status-list-token)
- [Read a Status List](#read-a-status-list)
- [Get Status](#get-status) 

### Get Status List Token

As a `Relying Party` fetch a `Status List Token`.

Library provides for this use case the interface [GetStatusListToken](Sources/Status/GetStatusToken.swift)

```swift
// Create an instance of GetStatusListToken

let getStatusToken = GetStatusListToken(
    verifier: VerifyStatusListTokenSignatureFactory.make(),
    date: Date()
)

// Use the GetStatusListToken instance to fetch a status list token
let result = await getStatusToken.getStatusClaims(url: statusReference.uri)

// Handle the result
switch result {
    case .success(let claims):
      ...
    case .failure:
      ...
    }
```

> [!IMPORTANT]
> Statium doesn't verify the signature of the JWT, given that Token Status List specification lets 
> ecosystems define their own processing rules. For this reason, you need to provide an implementation
> of [VerifyStatusListTokenSignature](Sources/Types/VerifyStatusListTokenSignature.swift).
> This will be used to verify the signature of the Status List Token after it has been fetched.
 
### Read a Status List

As a `Relying Party` be able to read a `Status List` at a specific index.

It is assumed that the caller has already [fetched](#get-status-list-token) 
the `Status List` (via a `Status List Token`)

Library provides for this use case the interface [ReadStatus](Sources/Status/ReadStatus.swift)

```swift
// Assuming you have already obtained a StatusListTokenClaims
let claims: StatusListTokenClaims = ...
let readStatus = ReadStatus(bitsPerStatus: .one, byteArray: [0xaa])
let result = await readStatus.readStatus(at: 1)

// Handle the result
switch status {

case .valid:
  ...
case .invalid:
  ...
case .suspended:
  ...
case .applicationSpecific(_):
  ...
case .reserved(_):
  ...
}
```
### Get Status

As a `Relying Party` [fetch](#get-status-list-token) the corresponding `Status List Token` 
to validate the status of that `Referenced Token`

It is assumed that the caller has extracted from the `Referenced Token` 
a reference to a `status_list`.

Library provides for this use case the interface [GetStatus](Sources/Status/GetStatus.kt)

```swift
// Create an instance of GetStatusListToken (as shown in the Get Status List Token section)
val getStatusListToken: GetStatusListToken = ...

// Create an instance of GetStatus
val getStatus: GetStatus = GetStatus()

// Assuming you have a StatusReference from a Referenced Token
let statusReference: StatusReference = .init(
    idx: 1,
    uriString: TestsConstants.testStatusUrlString
)

// Use the GetStatus instance to check the status of the Referenced Token
let result = await getStatus.getStatus(
    index: statusReference.idx,
    url: statusReference.uri,
    fetchClaims: getStatusToken.getStatusClaims
)

// Handle the result
switch status {

case .valid:
  ...
case .invalid:
  ...
case .suspended:
  ...
case .applicationSpecific(_):
  ...
case .reserved(_):
  ...
}
```

## How to contribute

We welcome contributions to this project. To ensure that the process is smooth for everyone
involved, follow the guidelines found in [CONTRIBUTING.md](CONTRIBUTING.md).

## License

### License details

Copyright (c) 2023 European Commission

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

