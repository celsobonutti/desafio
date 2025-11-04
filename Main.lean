import Desafio.Command
import Init.System.FilePath
import Std.Data.HashMap.Basic
import Std.Internal.Async.Basic
import Std.Internal.Async.Process
import Std.Internal.Async.TCP
import Std.Net.Addr
import Std.Sync.SharedMutex
import Std.Data.TreeMap
import Lean.Data.RBMap

open Std
open Internal
open IO.Async.TCP
open IO.Async
open Lean

def localHost := Std.Net.IPv4Addr.ofParts 127 0 0 1

def socketAddress :=
  Std.Net.SocketAddressV4.mk localHost 8080

def fileLocation (key : String) : System.FilePath :=
  s!"/var/lib/desafio/{key}"

def readLoop (client : Socket.Client) (mutex : SharedMutex (TreeMap String ByteArray)) : Async Unit := do
  while true do
    let some byteArr ← client.recv? 1000000000
      | return ()

    -- IO.println s!"Received: {byteArr.utf8Decode?}"

    let Except.ok result := Command.parser.run byteArr
      | IO.println s!"invalid message: {byteArr.utf8Decode?}"

    match result with
    | Command.status =>
      let usage ← IO.Process.getResourceUsage
      client.send s!"Memory usage: {usage.sharedMemorySizeKb}kb\n".toUTF8

    | Command.write key value =>
      mutex.atomically do
        modify (λ map => map.insert key value)
      IO.FS.writeBinFile (fileLocation key) value
      client.send "success\n".toUTF8

    | Command.read key =>
      let map ← mutex.atomicallyRead do
        read
      match map.get? key with
      | some data => client.send (data.push '\n'.toUInt8)
      | none =>
        if ←System.FilePath.pathExists (fileLocation key) then
          let data ← IO.FS.readBinFile (fileLocation key)
          mutex.atomically do
            modify (λ map => map.insert key data)
          client.send (data.push '\n'.toUInt8)
        else
          client.send "error\n".toUTF8

    | Command.delete key =>
      mutex.atomically do
        modify (λ map => map.erase key)
      if ←System.FilePath.pathExists (fileLocation key) then
        IO.FS.removeFile (fileLocation key)
      client.send "success\n".toUTF8

def asyncMain : Async Unit := do
  let memory : SharedMutex (TreeMap String ByteArray) ← SharedMutex.new {}
  -- let mut x : HashMap String ByteArray := HashMap.emptyWithCapacity 1000 
  let server ← Socket.Server.mk
  server.bind socketAddress
  server.listen 50
  
  while true do
    let client ← server.accept
    background (readLoop client memory)

def main : IO Unit := do
  asyncMain.block
