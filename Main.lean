import Desafio.Command
import Init.System.FilePath
import Std.Data.HashMap.Basic
import Std.Internal.Async.Basic
import Std.Internal.Async.Process
import Std.Internal.Async.TCP
import Std.Net.Addr
import Std.Sync.SharedMutex

open Std
open Internal
open IO.Async.TCP
open IO.Async

def localHost := Std.Net.IPv4Addr.ofParts 127 0 0 1

def socketAddress :=
  Std.Net.SocketAddressV4.mk localHost 1001

def fileLocation (key : String) : System.FilePath :=
  s!"/var/lib/desafio/{key}"

def readLoop (client : Socket.Client) (mutex : SharedMutex (HashMap String ByteArray)) : Async Unit := do
  while true do
    let some byteArr ← client.recv? 2000000000
      | return ()
    
    let Except.ok result := Command.parser.run byteArr
      | IO.println "invalid message, closing connection"

    match result with
    | Command.status =>
      let usage ← IO.Process.getResourceUsage
      client.send s!"Memory usage: {usage.sharedMemorySizeKb}kb".toUTF8

    | Command.write key value =>
      mutex.atomically do
        modify (λ map => map.insert key value)
      IO.FS.writeBinFile (fileLocation key) value
      client.send "success".toUTF8

    | Command.read key =>
      let map ← mutex.atomically do
        get
      match map.get? key with
      | some data => client.send data
      | none =>
        if ←System.FilePath.pathExists (fileLocation key) then
          let data ← IO.FS.readBinFile (fileLocation key)
          client.send data
        else
          client.send "error".toUTF8

    | Command.delete key =>
      mutex.atomically do
        modify (λ map => map.erase key)
      if ←System.FilePath.pathExists (fileLocation key) then
        IO.FS.removeFile (fileLocation key)
      client.send "success".toUTF8

def asyncMain : Async Unit := do
  let memory : SharedMutex (HashMap String ByteArray) ← SharedMutex.new <| HashMap.emptyWithCapacity 100
  let server ← Socket.Server.mk
  server.bind socketAddress
  server.listen 50
  
  while true do
    let client ← server.accept
    background (readLoop client memory)

def main : IO Unit := do
  asyncMain.block
