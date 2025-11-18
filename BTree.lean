/-
  BTree - Persistent B-Tree implementation with ByteArray values

  An opaque B-Tree data structure that maps String keys to ByteArray values.
  All operations are performed through FFI calls to the C implementation.
-/

/-- Opaque B-Tree type mapping String keys to ByteArray values -/
opaque BTree : Type := Unit

namespace BTree

/-- Create a new empty BTree -/
@[extern "btree_mk"]
opaque mk : IO BTree

/-- Free a BTree (manual memory management) -/
@[extern "btree_free_impl"]
opaque free (tree : @& BTree) : IO Unit

/-- Write a key-value pair to the BTree -/
@[extern "btree_write"]
opaque write (tree : @& BTree) (key : @& String) (data : @& ByteArray) : IO Unit

/-- Read a value by key from the BTree -/
@[extern "btree_read"]
opaque read (tree : @& BTree) (key : @& String) : IO (Option ByteArray)

/-- Delete a key-value pair from the BTree -/
@[extern "btree_delete"]
opaque delete (tree : @& BTree) (key : @& String) : IO Unit

/-- Filter keys by prefix, returning all matching keys -/
@[extern "btree_filter"]
opaque filter (tree : @& BTree) (prefix_ : @& String) : IO (Array String)

/-- Save the BTree to a file -/
@[extern "btree_save"]
opaque save (tree : @& BTree) (filename : @& String) : IO Unit

/-- Load a BTree from a file -/
@[extern "btree_load"]
opaque load (filename : @& String) : IO BTree

end BTree

/-
  Example usage:

  def example : IO Unit := do
    let tree ← BTree.mk

    -- Write some data
    let data := ByteArray.mk #[1, 2, 3, 4, 5]
    tree.write "key1" data

    -- Read it back
    let result ← tree.read "key1"
    match result with
    | some bytes => IO.println s!"Found {bytes.size} bytes"
    | none => IO.println "Key not found"

    -- Filter by prefix
    let keys ← tree.filter "key"
    IO.println s!"Keys starting with 'key': {keys}"

    -- Save to file
    tree.save "btree.dat"

    -- Free the tree
    tree.free
-/
