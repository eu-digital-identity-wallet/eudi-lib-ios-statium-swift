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
import XCTest
import Compression

@testable import eudi_lib_ios_statium_swift

final class CompressionsTests: XCTestCase {
  
  func testDecomressionShorter() {
    
    let bytes: [UInt8] = [0x78, 0xda, 0xdb, 0xb9, 0x18, 0x00, 0x02, 0x17, 0x01, 0x5d]
    let decodedBytes = Data.fromBase64URL("eNrbuRgAAhcBXQ")
    
    XCTAssertEqual(bytes, decodedBytes!)
    
    let decompressed = Decompressible(data: Data(bytes)).decompress()
    
    XCTAssertEqual(decompressed[0], 0xb9)
    XCTAssertEqual(decompressed[1], 0xa3)
  }
  
  func testDecomressionLonger() {
    
    let bytes: [UInt8] = [0x78, 0xda, 0x3b, 0xe9, 0xf2, 0x13, 0x00, 0x03, 0xdf, 0x02, 0x07]
    let decodedBytes = Data.fromBase64URL("eNo76fITAAPfAgc")
    
    XCTAssertEqual(bytes, decodedBytes!)
    
    let decompressed = Decompressible(data: Data(bytes)).decompress()

    XCTAssertEqual(decompressed[0], 0xc9)
    XCTAssertEqual(decompressed[1], 0x44)
    XCTAssertEqual(decompressed[2], 0xf9)
  }
}
