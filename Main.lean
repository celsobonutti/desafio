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
import Desafio.BTreeHelpers

open Std
open Internal
open IO.Async.TCP
open IO.Async

abbrev Memory := TreeMap String String

def localHost := Std.Net.IPv4Addr.ofParts 127 0 0 1

def socketAddress :=
  Std.Net.SocketAddressV4.mk localHost 8080

def fileLocation : System.FilePath :=
  s!"./db"

def processCommand (cmd : Command) (client : Socket.Client) (mutex : SharedMutex Memory) : Async Unit := do
    IO.println cmd
    match cmd with
    | Command.status =>
      client.send s!"well going our operation\r".toUTF8

    | Command.write key value =>
      mutex.atomically do
        modify (λ map => map.insert key value)
      client.send s!"well going our operation\r".toUTF8

    | Command.read key =>
      let map ← mutex.atomicallyRead do
        read
      match map.get? key with
      | some data => client.send (data.toUTF8.push '\r'.toUInt8)
      | none =>
          client.send "error\r".toUTF8

    | Command.reads prefix_ =>
      let values ← mutex.atomicallyRead do
        (TreeMap.values ∘ TreeMap.filter (λ key _ => key.startsWith prefix_)) <$> read
      values
        |> List.foldl (λacc value => (acc.push '\r'.toUInt8) ++ value.toUTF8) ∅
        |> client.send

    | Command.keys =>
      let keys ← mutex.atomicallyRead do
        TreeMap.keys <$> read
      keys
        |> List.map String.toUTF8
        |> List.foldl (λacc key => (acc.push '\r'.toUInt8) ++ key) ∅
        |> client.send
      

    | Command.delete key =>
      mutex.atomically do
        modify (λ map => map.erase key)
      client.send "success\r".toUTF8

def readLoop (client : Socket.Client) (mutex : SharedMutex Memory) : Async Unit := do
  while true do
    let some byteArr ← client.recv? 10000000
      | pure ()

    let Except.ok result := Command.parser.run byteArr
      | client.send "error\r".toUTF8

    processCommand result client mutex

def persistLoop (mutex : SharedMutex Memory) : IO Unit := do
  while true do
    let value ← mutex.atomicallyRead read
    let serialized := Lean.ToJson.toJson value |> Lean.Json.compress
    IO.FS.writeFile fileLocation serialized
    IO.sleep 500

def readPersistedMemory : IO Memory := do
  if ←System.FilePath.pathExists fileLocation then
    let memoryText ← IO.FS.readFile fileLocation
    let Except.ok memoryJson := Lean.Json.parse memoryText
      | return ∅
    pure <|
      match Lean.FromJson.fromJson? memoryJson with
      | Except.ok x => x
      | Except.error _ => ∅
  else
    pure ∅

def asyncMain : Async Unit := do
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

def main : IO Unit := do
    BTree.withBTree fun tree => do
      tree.write "user:1" (ByteArray.mk #[1, 2, 3])
      tree.write "user:2" (ByteArray.mk #[4, 5, 6])
      tree.write "post:1" (ByteArray.mk #[7, 8, 9])

      -- Get all user keys
      let userKeys ← tree.keysWithPrefix "user:"
      IO.println s!"User keys: {userKeys}"

      -- Save before exiting
      tree.save "data.btree"
  -- asyncMain.block
