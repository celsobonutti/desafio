import Desafio.BTreeLean

/-
  Helper functions for BTree with automatic resource management
-/

namespace BTree

/-- Execute an action with a BTree, ensuring it's freed afterwards -/
def withBTree (action : BTree → IO α) : IO α := do
  let tree ← BTree.mk
  try
    action tree
  finally
    tree.free

/-- Execute an action with a loaded BTree, ensuring it's freed afterwards -/
def withLoadedBTree (filename : String) (action : BTree → IO α) : IO α := do
  let tree ← BTree.load filename
  try
    action tree
  finally
    tree.free

/-- Insert multiple key-value pairs -/
def writeMany (tree : BTree) (pairs : Array (String × ByteArray)) : IO Unit := do
  for (key, data) in pairs do
    tree.write key data

/-- Read multiple keys -/
def readMany (tree : BTree) (keys : Array String) : IO (Array (String × Option ByteArray)) := do
  let mut results := #[]
  for key in keys do
    let value ← tree.read key
    results := results.push (key, value)
  return results

/-- Check if a key exists -/
def contains (tree : BTree) (key : String) : IO Bool := do
  let result ← tree.read key
  return result.isSome

/-- Get all keys with a given prefix -/
def keysWithPrefix (tree : BTree) (prefix_ : String) : IO (Array ByteArray) :=
  tree.filter prefix_

end BTree

/-
  Example with automatic resource management:

  def example : IO Unit := do
    BTree.withBTree fun tree => do
      -- Tree is automatically freed when done
      tree.write "user:1" (ByteArray.mk #[1, 2, 3])
      tree.write "user:2" (ByteArray.mk #[4, 5, 6])
      tree.write "post:1" (ByteArray.mk #[7, 8, 9])

      -- Get all user keys
      let userKeys ← tree.keysWithPrefix "user:"
      IO.println s!"User keys: {userKeys}"

      -- Save before exiting
      tree.save "data.btree"
-/
