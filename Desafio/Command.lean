import Std.Internal.Parsec.Basic
import Std.Internal.Parsec.ByteArray

open Std.Internal

inductive Command : Type where
  | read : String → Command
  | reads : String → Command
  | keys : Command
  | write : String → String → Command
  | delete : String → Command
  | status : Command

def Command.toString : Command → String
  | read x => s!"Read: {x}"
  | reads x => s!"Reading with prefix: {x}"
  | keys => "Keys"
  | write key value => s!"Writing {key} with {value}"
  | delete x => s!"Delete: {x}"
  | status => "Status"

instance instToStringCommand : ToString Command where
  toString := Command.toString

namespace Command

namespace Key
  def parseChar : Parsec.ByteArray.Parser Char :=
    Parsec.ByteArray.digit
    <|> Parsec.ByteArray.asciiLetter
    <|> Parsec.ByteArray.pByteChar '.'
    <|> Parsec.ByteArray.pByteChar '-'
    <|> Parsec.ByteArray.pByteChar '_'
    <|> Parsec.ByteArray.pByteChar ':'

  def parse : Parsec.ByteArray.Parser String := do
    Parsec.manyChars parseChar
end Key

def parseValue : Parsec.ByteArray.Parser String := do
  let value : ByteSlice ← Parsec.ByteArray.takeUntil λ x => x == '\r'.toUInt8
  pure <| String.fromUTF8!  <| value.toByteArray

def parseRead : Parsec.ByteArray.Parser Command := do
  Parsec.ByteArray.skipString "read"
  Parsec.ByteArray.ws
  let key ← Key.parse
  Parsec.ByteArray.skipByteChar '\r'
  pure (read key)

def parseReads : Parsec.ByteArray.Parser Command := do
  Parsec.ByteArray.skipString "reads"
  Parsec.ByteArray.ws
  let key ← Key.parse
  Parsec.ByteArray.skipByteChar '\r'
  pure (reads key)

def parseDelete : Parsec.ByteArray.Parser Command := do
  Parsec.ByteArray.skipString "delete"
  Parsec.ByteArray.ws
  let key ← Key.parse
  Parsec.ByteArray.skipByteChar '\r'
  pure (delete key)

def parseKeys : Parsec.ByteArray.Parser Command :=
  Parsec.ByteArray.skipString "keys" *> Parsec.ByteArray.skipByteChar '\r' *> pure keys

def parseStatus : Parsec.ByteArray.Parser Command :=
  Parsec.ByteArray.skipString "status" *> Parsec.ByteArray.skipByteChar '\r' *> pure status

def parseWrite : Parsec.ByteArray.Parser Command := do
  Parsec.ByteArray.skipString "write"
  Parsec.ByteArray.ws
  let key ← Key.parse
  Parsec.skip
  let value ← parseValue
  Parsec.ByteArray.skipByteChar '\r'
  pure (write key value)

def parser : Parsec.ByteArray.Parser Command := do
  Parsec.attempt parseStatus
  <|> Parsec.attempt parseRead
  <|> Parsec.attempt parseReads
  <|> Parsec.attempt parseKeys
  <|> Parsec.attempt parseDelete
  <|> Parsec.attempt parseWrite

end Command
