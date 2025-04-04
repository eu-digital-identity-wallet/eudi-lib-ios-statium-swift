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

/// An extension to the `Array` type to provide a safe way to access elements by index.
///
/// This extension adds a subscript that allows you to access array elements by their index,
/// returning an optional value (`Element?`). If the index is within the valid bounds of the array,
/// the element at that index is returned. If the index is out of bounds, `nil` is returned instead
/// of causing a runtime error.
///
/// Example usage:
/// ```
/// let array = [1, 2, 3]
/// let element = array[safe: 1] // Returns 2
/// let outOfBounds = array[safe: 5] // Returns nil
/// ```
///
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
