import unittest, deques, sequtils, strformat
import chronos
import ../libp2p/stream/bufferstream

when defined(nimHasUsed): {.used.}

suite "BufferStream":
  test "push data to buffer":
    proc testPushTo(): Future[bool] {.async.} =
      proc writeHandler(data: seq[byte]) {.async, gcsafe.} = discard
      let buff = newBufferStream(writeHandler, 16)
      check buff.len == 0
      var data: seq[char]
      data.add(@"12345")
      await buff.pushTo(cast[seq[byte]](data))
      check buff.len == 5
      result = true

    check:
      waitFor(testPushTo()) == true

  test "push and wait":
    proc testPushTo(): Future[bool] {.async.} =
      proc writeHandler(data: seq[byte]) {.async, gcsafe.} = discard
      let buff = newBufferStream(writeHandler, 4)
      check buff.len == 0

      let fut = buff.pushTo(cast[seq[byte]](@"12345"))
      check buff.len == 4
      check buff.popFirst() == byte(ord('1'))
      await fut
      check buff.len == 4

      result = true

    check:
      waitFor(testPushTo()) == true

  test "read":
    proc testRead(): Future[bool] {.async.} =
      proc writeHandler(data: seq[byte]) {.async, gcsafe.} = discard
      let buff = newBufferStream(writeHandler, 10)
      check buff.len == 0

      await buff.pushTo(cast[seq[byte]](@"12345"))
      check @"12345" == cast[string](await buff.read())

      result = true

    check:
      waitFor(testRead()) == true

  test "read with size":
    proc testRead(): Future[bool] {.async.} =
      proc writeHandler(data: seq[byte]) {.async, gcsafe.} = discard
      let buff = newBufferStream(writeHandler, 10)
      check buff.len == 0

      await buff.pushTo(cast[seq[byte]](@"12345"))
      let data = cast[string](await buff.read(3))
      check ['1', '2', '3'] == data

      result = true

    check:
      waitFor(testRead()) == true

  test "read and wait":
    proc testRead(): Future[bool] {.async.} =
      proc writeHandler(data: seq[byte]) {.async, gcsafe.} = discard
      let buff = newBufferStream(writeHandler, 10)
      check buff.len == 0

      await buff.pushTo(cast[seq[byte]](@"123"))
      check buff.len == 3
      let readFut = buff.read(5)
      await buff.pushTo(cast[seq[byte]](@"45"))
      check buff.len == 2

      check cast[string](await readFut) == ['1', '2', '3', '4', '5']

      result = true

    check:
      waitFor(testRead()) == true

  test "readExactly":
    proc testReadExactly(): Future[bool] {.async.} =
      proc writeHandler(data: seq[byte]) {.async, gcsafe.} = discard
      let buff = newBufferStream(writeHandler, 10)
      check buff.len == 0

      await buff.pushTo(cast[seq[byte]](@"12345"))
      check buff.len == 5
      var data: seq[byte] = newSeq[byte](2)
      await buff.readExactly(addr data[0], 2)
      check cast[string](data) == @['1', '2']
      result = true

    check:
      waitFor(testReadExactly()) == true

  test "readLine":
    proc testReadLine(): Future[bool] {.async.} =
      proc writeHandler(data: seq[byte]) {.async, gcsafe.} = discard
      let buff = newBufferStream(writeHandler, 16)
      check buff.len == 0

      await buff.pushTo(cast[seq[byte]](@"12345\n67890"))
      check buff.len == 11
      check "12345" == await buff.readLine(0, "\n")
      result = true

    check:
      waitFor(testReadLine()) == true

  test "readOnce":
    proc testReadOnce(): Future[bool] {.async.} =
      proc writeHandler(data: seq[byte]) {.async, gcsafe.} = discard
      let buff = newBufferStream(writeHandler, 10)
      check buff.len == 0

      var data: seq[byte] = newSeq[byte](3)
      let readFut = buff.readOnce(addr data[0], 5)
      await buff.pushTo(cast[seq[byte]](@"123"))
      check buff.len == 3

      check (await readFut) == 3
      check cast[string](data) == @['1', '2', '3']
      result = true

    check:
      waitFor(testReadOnce()) == true

  test "readUntil":
    proc testReadUntil(): Future[bool] {.async.} =
      proc writeHandler(data: seq[byte]) {.async, gcsafe.} = discard
      let buff = newBufferStream(writeHandler, 10)
      check buff.len == 0

      var data: seq[byte] = newSeq[byte](3)
      await buff.pushTo(cast[seq[byte]](@"123$45"))
      check buff.len == 6
      let readFut = buff.readUntil(addr data[0], 5, @[byte('$')])

      check (await readFut) == 4
      check cast[string](data) == @['1', '2', '3']
      result = true

    check:
      waitFor(testReadUntil()) == true

  test "write ptr":
    proc testWritePtr(): Future[bool] {.async.} =
      proc writeHandler(data: seq[byte]) {.async, gcsafe.} =
        check cast[string](data) == "Hello!"

      let buff = newBufferStream(writeHandler, 10)
      check buff.len == 0

      var data = "Hello!"
      await buff.write(addr data[0], data.len)
      result = true

    check:
      waitFor(testWritePtr()) == true

  test "write string":
    proc testWritePtr(): Future[bool] {.async.} =
      proc writeHandler(data: seq[byte]) {.async, gcsafe.} =
        check cast[string](data) == "Hello!"

      let buff = newBufferStream(writeHandler, 10)
      check buff.len == 0

      await buff.write("Hello!", 6)
      result = true

    check:
      waitFor(testWritePtr()) == true

  test "write bytes":
    proc testWritePtr(): Future[bool] {.async.} =
      proc writeHandler(data: seq[byte]) {.async, gcsafe.} =
        check cast[string](data) == "Hello!"

      let buff = newBufferStream(writeHandler, 10)
      check buff.len == 0

      await buff.write(cast[seq[byte]]("Hello!"), 6)
      result = true

    check:
      waitFor(testWritePtr()) == true

  test "write should happen in order":
    proc testWritePtr(): Future[bool] {.async.} =
      var count = 1
      proc writeHandler(data: seq[byte]) {.async, gcsafe.} =
        check cast[string](data) == &"Msg {$count}"
        count.inc

      let buff = newBufferStream(writeHandler, 10)
      check buff.len == 0

      await buff.write("Msg 1")
      await buff.write("Msg 2")
      await buff.write("Msg 3")
      await buff.write("Msg 4")
      await buff.write("Msg 5")
      await buff.write("Msg 6")
      await buff.write("Msg 7")
      await buff.write("Msg 8")
      await buff.write("Msg 9")
      await buff.write("Msg 10")
      result = true

    check:
      waitFor(testWritePtr()) == true

  test "reads should happen in order":
    proc testWritePtr(): Future[bool] {.async.} =
      var count = 1
      proc writeHandler(data: seq[byte]) {.async, gcsafe.} = discard
      let buff = newBufferStream(writeHandler, 10)
      check buff.len == 0

      await buff.pushTo(cast[seq[byte]]("Msg 1"))
      await buff.pushTo(cast[seq[byte]]("Msg 2"))
      await buff.pushTo(cast[seq[byte]]("Msg 3"))

      check cast[string](await buff.read(5)) == "Msg 1"
      check cast[string](await buff.read(5)) == "Msg 2"
      check cast[string](await buff.read(5)) == "Msg 3"

      await buff.pushTo(cast[seq[byte]]("Msg 4"))
      await buff.pushTo(cast[seq[byte]]("Msg 5"))
      await buff.pushTo(cast[seq[byte]]("Msg 6"))

      check cast[string](await buff.read(5)) == "Msg 4"
      check cast[string](await buff.read(5)) == "Msg 5"
      check cast[string](await buff.read(5)) == "Msg 6"

      result = true

    check:
      waitFor(testWritePtr()) == true
