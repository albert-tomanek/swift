//===--- StdlibCoreExtras.swift -------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2015 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Darwin
import Foundation

//
// These APIs don't really belong in a unit testing library, but they are
// useful in tests, and stdlib does not have such facilities yet.
//

/// Convert the given numeric value to a hexidecimal string.
public func asHex<T : IntegerType>(x: T) -> String {
  return "0x" + String(x.toIntMax(), radix: 16)
}

/// Convert the given sequence of numeric values to a string representing
/// their hexidecimal values.
public func asHex<
  S: SequenceType
where
  S.Generator.Element : IntegerType
>(x: S) -> String {
  return "[ " + ", ".join(lazy(x).map { asHex($0) }) + " ]"
}

/// Compute the prefix sum of `seq`.
func scan<
  S : SequenceType, U
>(seq: S, initial: U, combine: (U, S.Generator.Element) -> U) -> [U] {
  var result = [U]()
  result.reserveCapacity(underestimateCount(seq))
  var runningResult = initial
  for element in seq {
    runningResult = combine(runningResult, element)
    result.append(runningResult)
  }
  return result
}

public func _stdlib_randomShuffle<T>(a: [T]) -> [T] {
  var result = a
  for var i = a.count - 1; i != 0; --i {
    // FIXME: 32 bits are not enough in general case!
    let j = Int(rand32(exclusiveUpperBound: i + 1))
    swap(&result[i], &result[j])
  }
  return result
}

public func _stdlib_gather<T>(a: [T], idx: [Int]) -> [T] {
  var result = [T]()
  result.reserveCapacity(a.count)
  for i in 0..<a.count {
    result.append(a[idx[i]])
  }
  return result
}

public func _stdlib_scatter<T>(a: [T], idx: [Int]) -> [T] {
  var result = a
  for i in 0..<a.count {
    result[idx[i]] = a[i]
  }
  return result
}

func findSubstring(string: String, substring: String) -> String.Index? {
  if substring.isEmpty {
    return string.startIndex
  }
  return string.rangeOfString(substring)?.startIndex
}

func withArrayOfCStrings<R>(
  args: [String], body: (Array<UnsafeMutablePointer<CChar>>) -> R
) -> R {

  let argsLengths = Array(map(args) { countElements($0.utf8) + 1 })
  let argsOffsets = [ 0 ] + scan(argsLengths, 0, +)
  let argsBufferSize = argsOffsets.last!

  var argsBuffer = ContiguousArray<UInt8>()
  argsBuffer.reserveCapacity(argsBufferSize)
  for arg in args {
    argsBuffer.extend(arg.utf8)
    argsBuffer.append(0)
  }

  return argsBuffer.withUnsafeBufferPointer {
    (argsBuffer) in
    let ptr = UnsafeMutablePointer<CChar>(argsBuffer.baseAddress)
    var cStrings = Array(map(argsOffsets) { ptr + $0 })
    cStrings[cStrings.count - 1] = nil
    return body(cStrings)
  }
}

struct _Stderr : OutputStreamType {
  mutating func write(string: String) {
    for c in string.utf8 {
      putc(Int32(c), stderr)
    }
  }
}

struct _FDOutputStream : OutputStreamType {
  let fd: CInt

  mutating func write(string: String) {
    let utf8 = string.nulTerminatedUTF8
    utf8.withUnsafeBufferPointer {
      (utf8) -> () in
      var writtenBytes: size_t = 0
      let bufferSize = size_t(utf8.count - 1)
      while writtenBytes != bufferSize {
        let result = Darwin.write(
          self.fd, UnsafePointer(utf8.baseAddress + Int(writtenBytes)),
          bufferSize - writtenBytes)
        if result < 0 {
          fatalError("write() returned an error")
        }
        writtenBytes += result
      }
    }
  }
}

func _stdlib_mkstemps(inout template: String, suffixlen: CInt) -> CInt {
  var utf8 = template.nulTerminatedUTF8
  let (fd, fileName) = utf8.withUnsafeMutableBufferPointer {
    (utf8) -> (CInt, String) in
    let fd = mkstemps(UnsafeMutablePointer(utf8.baseAddress), suffixlen)
    let fileName = String.fromCString(UnsafePointer(utf8.baseAddress))!
    return (fd, fileName)
  }
  template = fileName
  return fd
}

public func createTemporaryFile(
  fileNamePrefix: String, fileNameSuffix: String, contents: String
) -> String {
  var fileName = NSTemporaryDirectory().stringByAppendingPathComponent(
    fileNamePrefix + "XXXXXX" + fileNameSuffix)
  let fd = _stdlib_mkstemps(
    &fileName, CInt(countElements(fileNameSuffix.utf8)))
  if fd < 0 {
    fatalError("mkstemps() returned an error")
  }
  var stream = _FDOutputStream(fd: fd)
  stream.write(contents)
  if close(fd) != 0 {
    fatalError("close() return an error")
  }
  return fileName
}

