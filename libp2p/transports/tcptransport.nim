## Nim-LibP2P
## Copyright (c) 2019 Status Research & Development GmbH
## Licensed under either of
##  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
##  * MIT license ([LICENSE-MIT](LICENSE-MIT))
## at your option.
## This file may not be copied, modified, or distributed except according to
## those terms.

import chronos, chronicles, sequtils
import transport,
       ../errors,
       ../wire,
       ../connection,
       ../multiaddress,
       ../multicodec,
       ../stream/chronosstream

logScope:
  topic = "TcpTransport"

const
  TcpTransportTrackerName* = "libp2p.tcptransport"

type
  TcpTransport* = ref object of Transport
    server*: StreamServer
    cleanups*: seq[Future[void]]
    handlers*: seq[Future[void]]

  TcpTransportTracker* = ref object of TrackerBase
    opened*: uint64
    closed*: uint64

proc setupTcpTransportTracker(): TcpTransportTracker {.gcsafe.}

proc getTcpTransportTracker(): TcpTransportTracker {.gcsafe.} =
  result = cast[TcpTransportTracker](getTracker(TcpTransportTrackerName))
  if isNil(result):
    result = setupTcpTransportTracker()

proc dumpTracking(): string {.gcsafe.} =
  var tracker = getTcpTransportTracker()
  result = "Opened TCP transports: " & $tracker.opened & "\n" &
           "Closed TCP transports: " & $tracker.closed

proc leakTransport(): bool {.gcsafe.} =
  var tracker = getTcpTransportTracker()
  result = (tracker.opened != tracker.closed)

proc setupTcpTransportTracker(): TcpTransportTracker =
  result = new TcpTransportTracker
  result.opened = 0
  result.closed = 0
  result.dump = dumpTracking
  result.isLeaked = leakTransport
  addTracker(TcpTransportTrackerName, result)

proc cleanup(t: Transport, conn: Connection) {.async.} =
  await conn.closeEvent.wait()
  trace "TCP connection cleanup event wait ended"
  t.connections.keepItIf(it != conn)

proc connHandler*(t: TcpTransport,
                  client: StreamTransport,
                  initiator: bool): Connection =
  trace "Handling TCP connection", address = $client.remoteAddress
  let conn: Connection = newConnection(newChronosStream(client))
  conn.observedAddrs = MultiAddress.init(client.remoteAddress)
  if not initiator:
    if not isNil(t.handler):
      t.handlers.add(t.handler(conn))
    t.connections.add(conn)
    t.cleanups.add(t.cleanup(conn))

  result = conn

proc connCb(server: StreamServer,
            client: StreamTransport) {.async, gcsafe.} =
  trace "Incomming TCP connection", address = $client.remoteAddress
  let t = cast[TcpTransport](server.udata)
  # we don't need result connection in this case
  # as it's added inside connHandler
  discard t.connHandler(client, false)

method init*(t: TcpTransport) =
  t.multicodec = multiCodec("tcp")

  inc getTcpTransportTracker().opened

method close*(t: TcpTransport) {.async, gcsafe.} =
  ## start the transport
  trace "Stopping TCP transport"
  await procCall Transport(t).close() # call base

  # server can be nil
  if not isNil(t.server):
    t.server.stop()
    await t.server.closeWait()

  t.server = nil

  for fut in t.handlers:
    if not fut.finished:
      fut.cancel()
  t.handlers = await allFinished(t.handlers)
  checkFutures(t.handlers)
  t.handlers.setLen(0)

  for fut in t.cleanups:
    if not fut.finished:
      fut.cancel()
  t.cleanups = await allFinished(t.cleanups)
  checkFutures(t.cleanups)
  t.cleanups.setLen(0)

  trace "TCP transport stopped"

  inc getTcpTransportTracker().closed

method listen*(t: TcpTransport,
               ma: MultiAddress,
               handler: ConnHandler):
               Future[Future[void]] {.async, gcsafe.} =
  discard await procCall Transport(t).listen(ma, handler) # call base

  ## listen on the transport
  t.server = createStreamServer(t.ma, connCb,
                                transportFlagsToServerFlags(t.flags), t)
  t.server.start()

  # TODO: In case of 0.0.0.0:0 this address would be 0.0.0.0:PORT,
  # but not real interface address. We need to get interface addresses and
  # add it to transport addresses.
  t.ma = MultiAddress.init(t.server.localAddress())
  result = t.server.join()
  trace "Started TCP node", address = t.ma

method dial*(t: TcpTransport,
             address: MultiAddress):
             Future[Connection] {.async, gcsafe.} =
  trace "Dialing remote peer using TCP transport", address = $address
  ## dial a peer
  let client: StreamTransport = await connect(address)
  result = t.connHandler(client, true)

method handles*(t: TcpTransport, address: MultiAddress): bool {.gcsafe.} =
  if procCall Transport(t).handles(address):
    result = TCP.matchPartial(address)
