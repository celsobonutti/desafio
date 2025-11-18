import Desafio.Command
import Init.System.FilePath
import Std.Data.HashMap.Basic
import Std.Internal.Async.Basic
import Std.Internal.Async.Process
import Std.Internal.Async.TCP
import Std.Net.Addr
import Std.Sync.SharedMutex
import Std.Data.TreeMap
import Std.Data.TreeMap.Basic
import Lean.Data.RBMap
import Lean.Data.Json.FromToJson.Basic
import Lean.Data.Json.FromToJson.Extra
import Lean.Data.Json.Printer
import Lean.Data.Json.Parser
import Desafio.BTree

open Std
open Internal
open IO.Async.TCP
open IO.Async

abbrev Memory := BTree

def localHost := Std.Net.IPv4Addr.ofParts 127 0 0 1

def socketAddress :=
  Std.Net.SocketAddressV4.mk localHost 8080

def fileLocation : System.FilePath :=
  s!"./.db"

unsafe def processCommand (cmd : Command) (client : Socket.Client) (mutex : SharedMutex Memory) : Async Unit := do
    match cmd with
    | Command.status =>
      client.send s!"well going our operation\r".toUTF8

    | Command.write key value =>
      mutex.atomically do
        let tree ← get
        let _ ← BTree.write tree key value
        pure ()
      client.send s!"well going our operation\r".toUTF8

    | Command.read key =>
      let value ← mutex.atomicallyRead do
        let value ← BTree.read key
        pure value
      match value with
      | some data => client.send (data.push '\r'.toUInt8)
      | none =>
          client.send "error\r".toUTF8

    | Command.reads prefix_ =>
      let values ← mutex.atomicallyRead do
        BTree.filter prefix_
      values
        |> Array.foldl (λacc value => (acc.push '\r'.toUInt8) ++ value) ∅
        |> client.send

    | Command.keys =>
      let keys ← mutex.atomicallyRead do
        BTree.keys
      keys
        |> Array.foldl (λacc key => (acc.push '\r'.toUInt8) ++ key.toUTF8) ∅
        |> client.send

    | Command.delete key =>
      mutex.atomically do
        let tree ← get
        let _ ← BTree.delete tree key
        pure ()
      client.send "success\r".toUTF8

unsafe def readLoop (client : Socket.Client) (mutex : SharedMutex Memory) : Async Unit := do
  while true do
    let some byteArr ← client.recv? 10000000
      | pure ()

    let Except.ok result := Command.parser.run byteArr
      | client.send "error\r".toUTF8

    processCommand result client mutex

def persistLoop (mutex : SharedMutex Memory) : IO Unit := do
  while true do
    let value ← mutex.atomicallyRead read
    BTree.save value fileLocation.toString
    IO.sleep 500

def readPersistedMemory : IO Memory := do
  if ←System.FilePath.pathExists fileLocation then
    BTree.load fileLocation.toString
  else do
    let tree ← BTree.mk
    pure tree

unsafe def asyncMain : Async Unit := do
  let persistedMemory ← readPersistedMemory
  let memory : SharedMutex Memory ← SharedMutex.new persistedMemory
  let server ← Socket.Server.mk
  server.bind socketAddress
  server.listen 50
  
  let read := do
    while true do
      let client ← server.accept
      IO.println "Client connected"
      background (readLoop client memory)

  let _ ← Async.concurrently read (background (persistLoop memory))

unsafe def main : IO Unit := do
  asyncMain.block
