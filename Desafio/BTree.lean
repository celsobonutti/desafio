import Std.Sync.Basic
import Desafio.BTreeLean

namespace BTree
  unsafe def write [Monad m] (tree : BTree) (key : String) (data : ByteArray) : Std.AtomicT α m BTree := do
    let _ := unsafeIO <| write_c tree key data
    pure tree

  unsafe def delete [Monad m] (tree : BTree) (key : String) : Std.AtomicT α m BTree := do
    let _ := unsafeIO <| delete_c tree key
    pure tree

  unsafe def read [Monad m]  (key : String) : ReaderT BTree m (Option ByteArray) := do
    let tree ← ReaderT.read
    let value := unsafeIO <| read_c tree key
    match value with
    | Except.ok x => pure x
    | Except.error _ => pure none

  unsafe def filter [Monad m] (key : String) : ReaderT BTree m (Array ByteArray) := do
    let tree ← ReaderT.read
    let value := unsafeIO <| filter_c tree key
    match value with
    | Except.ok x => pure x
    | Except.error _ => pure #[]

  unsafe def keys [Monad m] : ReaderT BTree m (Array String) := do
    let tree ← ReaderT.read
    let value := unsafeIO <| keys_c tree
    match value with
    | Except.ok x => pure x
    | Except.error _ => pure #[]
end BTree
