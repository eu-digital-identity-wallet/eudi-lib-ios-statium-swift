/*
 * Copyright (c) 2023 European Commission
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
import Foundation

public protocol DecompressibleType: Sendable {
  associatedtype Decompressed
  var data: Data { get }
  func decompress() -> Data
  mutating func setData(_ data: Data)
}

public struct Decompressible: DecompressibleType {
  
  public typealias Decompressed = Data

  public var data: Data
  
  public init(data: Data) {
    self.data = data
  }
  
  public init() {
    self.data = Data()
  }
  
  public mutating func setData(_ data: Data) {
    self.data = data
  }
  
  public func decompress() -> Data { data.decompressed }
}
