## Nim-Libp2p
## Copyright (c) 2020 Status Research & Development GmbH
## Licensed under either of
##  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
##  * MIT license ([LICENSE-MIT](LICENSE-MIT))
## at your option.
## This file may not be copied, modified, or distributed except according to
## those terms.

import sequtils
import chronos, chronicles

# TODO: this should probably go in chronos

logScope:
  topics = "semaphore"

type
  AsyncSemaphore* = ref object of RootObj
    size*: int
    count*: int
    queue: seq[Future[void]]

proc init*(T: type AsyncSemaphore, size: int): T =
  T(size: size, count: size)

proc tryAcquire*(s: AsyncSemaphore): bool =
  ## Attempts to acquire a resource, if successful
  ## returns true, otherwise false
  ##

  if s.count > 0 and s.queue.len == 0:
    s.count.dec
    trace "Acquired slot", available = s.count, queue = s.queue.len
    return true

proc acquire*(s: AsyncSemaphore): Future[void] =
  ## Acquire a resource and decrement the resource
  ## counter. If no more resources are available,
  ## the returned future will not complete until
  ## the resource count goes above 0 again.
  ##

  let fut = newFuture[void]("AsyncSemaphore.acquire")
  if s.tryAcquire():
    fut.complete()
    return fut

  s.queue.add(fut)
  s.count.dec
  trace "Queued slot", available = s.count, queue = s.queue.len
  return fut

proc release*(s: AsyncSemaphore) =
  ## Release a resource from the semaphore,
  ## by picking the first future from the queue
  ## and completing it and incrementing the
  ## internal resource count
  ##

  doAssert(s.count <= s.size)

  if s.count < s.size:
    trace "Releasing slot", available = s.count,
                            queue = s.queue.len

    if s.queue.len > 0:
      var fut = s.queue.pop()
      if not fut.finished():
        fut.complete()

    s.count.inc # increment the resource count
    trace "Released slot", available = s.count,
                           queue = s.queue.len
                          #  stack = getStackTrace()
    return

when isMainModule:
  import unittest, random

  randomize()

  suite "AsyncSemaphore":
    test "should acquire":
      proc test() {.async.} =
        let sema = AsyncSemaphore.init(3)

        await sema.acquire()
        await sema.acquire()
        await sema.acquire()

        check sema.count == 0

      waitFor(test())

    test "should release":
      proc test() {.async.} =
        let sema = AsyncSemaphore.init(3)

        await sema.acquire()
        await sema.acquire()
        await sema.acquire()

        check sema.count == 0
        sema.release()
        sema.release()
        sema.release()
        check sema.count == 3

      waitFor(test())

    test "should queue acquire":
      proc test() {.async.} =
        let sema = AsyncSemaphore.init(1)

        await sema.acquire()
        let fut = sema.acquire()

        check sema.count == -1
        check sema.queue.len == 1
        sema.release()
        sema.release()
        check sema.count == 1

        await sleepAsync(10.millis)
        check fut.finished()

      waitFor(test())

    test "should keep count == size":
      proc test() {.async.} =
        let sema = AsyncSemaphore.init(1)
        sema.release()
        sema.release()
        sema.release()
        check sema.count == 1

      waitFor(test())

    test "should tryAcquire":
      proc test() {.async.} =
        let sema = AsyncSemaphore.init(1)
        await sema.acquire()
        check sema.tryAcquire() == false

      waitFor(test())

    test "should tryAcquire and acquire":
      proc test() {.async.} =
        let sema = AsyncSemaphore.init(4)
        check sema.tryAcquire() == true
        check sema.tryAcquire() == true
        check sema.tryAcquire() == true
        check sema.tryAcquire() == true
        check sema.count == 0

        let fut = sema.acquire()
        check fut.finished == false
        check sema.count == -1
        # queue is only used when count is < 0
        check sema.queue.len == 1

        sema.release()
        sema.release()
        sema.release()
        sema.release()
        sema.release()

        check fut.finished == true
        check sema.count == 4
        check sema.queue.len == 0

      waitFor(test())

    test "should restrict resource access":
      proc test() {.async.} =
        let sema = AsyncSemaphore.init(3)
        var resource = 0

        proc task() {.async.} =
          try:
            await sema.acquire()
            resource.inc()
            check resource > 0 and resource <= 3
            let sleep = rand(0..10).millis
            # echo sleep
            await sleepAsync(sleep)
          finally:
            resource.dec()
            sema.release()

        var tasks: seq[Future[void]]
        for i in 0..<10:
          tasks.add(task())

        await allFutures(tasks)

      waitFor(test())
