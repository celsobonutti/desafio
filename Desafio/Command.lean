import Std.Internal.Parsec.Basic
import Std.Internal.Parsec.ByteArray

open Std.Internal

inductive Command : Type where
  | read : String → Command
  | write : String → ByteArray → Command
  | delete : String → Command
  | status : Command

def Command.toString : Command → String
  | read x => s!"Read: {x}"
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

def parseValue : Parsec.ByteArray.Parser ByteArray := do
  ByteArray.mk <$> Parsec.many (Parsec.satisfy (λ x => x != '\r'.toUInt8))

def parseRead : Parsec.ByteArray.Parser Command := do
  Parsec.ByteArray.skipString "read"
  Parsec.ByteArray.ws
  let key ← Key.parse
  Parsec.ByteArray.skipByteChar '\r'
  pure (read key)

def parseDelete : Parsec.ByteArray.Parser Command := do
  Parsec.ByteArray.skipString "delete"
  Parsec.ByteArray.ws
  let key ← Key.parse
  Parsec.ByteArray.skipByteChar '\r'
  pure (delete key)

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
  <|> Parsec.attempt parseDelete
  <|> Parsec.attempt parseWrite

end Command
