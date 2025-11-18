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
opaque write_c (tree : @& BTree) (key : @& String) (data : @& ByteArray) : IO Unit

/-- Read a value by key from the BTree -/
@[extern "btree_read"]
opaque read_c (tree : @& BTree) (key : @& String) : IO (Option ByteArray)

/-- Delete a key-value pair from the BTree -/
@[extern "btree_delete_impl"]
opaque delete_c (tree : @& BTree) (key : @& String) : IO Unit

/-- Filter keys by prefix, returning all matching values -/
@[extern "btree_filter"]
opaque filter_c (tree : @& BTree) (prefix_ : @& String) : IO (Array ByteArray)

/-- Get all keys in the BTree -/
@[extern "btree_keys"]
opaque keys_c (tree : @& BTree) : IO (Array String)

/-- Save the BTree to a file -/
@[extern "btree_save_impl"]
opaque save (tree : @& BTree) (filename : @& String) : IO Unit

/-- Load a BTree from a file -/
@[extern "btree_load"]
opaque load (filename : @& String) : IO BTree

end BTree
