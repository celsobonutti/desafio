#include <lean/lean.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdint.h>
#include "btree.h"

struct element {
    char *key;
    lean_object *data;  // Lean ByteArray
};

int element_compare(const void *a, const void *b, void *udata) {
    const struct element *ea = a;
    const struct element *eb = b;
    return strcmp(ea->key, eb->key);
}

bool element_iter(const void *a, void *udata) {
    const struct element *elem = a;
    // Get ByteArray data
    uint8_t *bytes = lean_sarray_cptr(elem->data);
    size_t size = lean_sarray_size(elem->data);

    printf("%s (data: %zu bytes", elem->key, size);
    if (size > 0) {
        printf(", first byte: 0x%02x", bytes[0]);
    }
    printf(")\n");
    return true;
}

// Context for saving to file
struct save_ctx {
    FILE *f;
    bool error;
};

// Iterator function that writes each element to file
bool save_iter(const void *item, void *udata) {
    struct save_ctx *ctx = udata;
    const struct element *elem = item;

    // Write key (length + string)
    size_t len = strlen(elem->key);
    if (fwrite(&len, sizeof(len), 1, ctx->f) != 1) {
        ctx->error = true;
        return false;
    }
    if (fwrite(elem->key, 1, len, ctx->f) != len) {
        ctx->error = true;
        return false;
    }

    // Write ByteArray data (size + bytes)
    uint8_t *bytes = lean_sarray_cptr(elem->data);
    size_t data_size = lean_sarray_size(elem->data);

    if (fwrite(&data_size, sizeof(data_size), 1, ctx->f) != 1) {
        ctx->error = true;
        return false;
    }
    if (data_size > 0 && fwrite(bytes, 1, data_size, ctx->f) != data_size) {
        ctx->error = true;
        return false;
    }

    return true;
}

// Save btree to file in binary format
bool btree_save(struct btree *tr, const char *filename) {
    FILE *f = fopen(filename, "wb");
    if (!f) {
        perror("Error opening file for writing");
        return false;
    }

    // Write count
    size_t count = btree_count(tr);
    if (fwrite(&count, sizeof(count), 1, f) != 1) {
        perror("Error writing count");
        fclose(f);
        return false;
    }

    // Create context for iteration
    struct save_ctx ctx = { .f = f, .error = false };

    // Iterate and save all elements in sorted order
    btree_ascend(tr, NULL, save_iter, &ctx);

    fclose(f);
    return !ctx.error;
}

// Load btree from file
struct btree *btree_load_from_file(const char *filename) {
    FILE *f = fopen(filename, "rb");
    if (!f) {
        perror("Error opening file for reading");
        return NULL;
    }

    // Read count
    size_t count;
    if (fread(&count, sizeof(count), 1, f) != 1) {
        perror("Error reading count");
        fclose(f);
        return NULL;
    }

    printf("Loading %zu elements from file...\n", count);

    // Create new btree
    struct btree *tr = btree_new(sizeof(struct element), 0, element_compare, NULL);
    if (!tr) {
        fclose(f);
        return NULL;
    }

    // Read each element
    for (size_t i = 0; i < count; i++) {
        struct element elem;

        // Read key (length + string)
        size_t len;
        if (fread(&len, sizeof(len), 1, f) != 1) {
            fprintf(stderr, "Error reading key length\n");
            btree_free(tr);
            fclose(f);
            return NULL;
        }
        char *key = malloc(len + 1);
        if (!key || fread(key, 1, len, f) != len) {
            fprintf(stderr, "Error reading key\n");
            free(key);
            btree_free(tr);
            fclose(f);
            return NULL;
        }
        key[len] = '\0';
        elem.key = key;

        // Read ByteArray data (size + bytes)
        size_t data_size;
        if (fread(&data_size, sizeof(data_size), 1, f) != 1) {
            fprintf(stderr, "Error reading data size\n");
            free(key);
            btree_free(tr);
            fclose(f);
            return NULL;
        }

        // Allocate Lean ByteArray
        lean_object *ba = lean_alloc_sarray(1, 0, data_size);
        if (!ba) {
            fprintf(stderr, "Error allocating ByteArray\n");
            free(key);
            btree_free(tr);
            fclose(f);
            return NULL;
        }

        // Read bytes into ByteArray
        if (data_size > 0) {
            uint8_t *bytes = lean_sarray_cptr(ba);
            if (fread(bytes, 1, data_size, f) != data_size) {
                fprintf(stderr, "Error reading data bytes\n");
                free(key);
                btree_free(tr);
                fclose(f);
                return NULL;
            }
        }

        // Set the size
        lean_sarray_object *sarray = (lean_sarray_object*)ba;
        sarray->m_size = data_size;

        elem.data = ba;

        // Use btree_load for fast sequential insertion (items are in sorted order)
        btree_load(tr, &elem);
    }

    fclose(f);
    return tr;
}

// Context for prefix search
struct prefix_search_ctx {
    const char *prefix;
    size_t prefix_len;
    bool (*callback)(const void *item, void *udata);
    void *udata;
    size_t count;
};

// Iterator for prefix search
bool prefix_search_iter(const void *item, void *udata) {
    struct prefix_search_ctx *ctx = udata;
    const struct element *elem = item;

    // Check if the element's key starts with the prefix
    if (strncmp(elem->key, ctx->prefix, ctx->prefix_len) == 0) {
        ctx->count++;
        // Call the user's callback with the matching item
        if (ctx->callback && !ctx->callback(item, ctx->udata)) {
            return false; // Stop iteration if callback returns false
        }
        return true; // Continue to next item
    }

    // Key doesn't match prefix, stop iteration (btree is sorted)
    return false;
}

// Find all elements whose key starts with the given prefix
// Returns the count of matching elements
size_t btree_find_by_prefix(struct btree *tr, const char *prefix,
                             bool (*callback)(const void *item, void *udata),
                             void *udata) {
    struct prefix_search_ctx ctx = {
        .prefix = prefix,
        .prefix_len = strlen(prefix),
        .callback = callback,
        .udata = udata,
        .count = 0
    };

    // Start iteration from an element with the prefix as the key
    // Since the btree is sorted, this will find the first match efficiently
    struct element pivot = { .key = (char*)prefix };
    btree_ascend(tr, &pivot, prefix_search_iter, &ctx);

    return ctx.count;
}

// Helper function to create a ByteArray with test data
lean_object *create_byte_array(const uint8_t *data, size_t size) {
    lean_object *ba = lean_alloc_sarray(1, 0, size);
    if (!ba) return NULL;

    if (size > 0) {
        uint8_t *bytes = lean_sarray_cptr(ba);
        memcpy(bytes, data, size);
    }

    lean_sarray_object *sarray = (lean_sarray_object*)ba;
    sarray->m_size = size;

    return ba;
}

// ===== LEAN FFI EXPORTS =====
// BTree is opaque in Lean - only expose operations

// Create a new BTree
// @[extern "btree_mk"]
// opaque BTree : Type := Unit
// @[extern "btree_mk"]
// def BTree.mk : IO BTree
lean_obj_res btree_mk(lean_obj_arg /* io */) {
    struct btree *tr = btree_new(sizeof(struct element), 0, element_compare, NULL);
    if (!tr) {
        return lean_io_result_mk_error(lean_mk_io_user_error(lean_mk_string("Failed to create BTree")));
    }
    // Return BTree as opaque pointer
    return lean_io_result_mk_ok(lean_box((size_t)tr));
}

// Free a BTree
// @[extern "btree_free_impl"]
// def BTree.free (tree : @& BTree) : IO Unit
lean_obj_res btree_free_impl(b_lean_obj_arg tree_obj, lean_obj_arg /* io */) {
    struct btree *tr = (struct btree*)lean_unbox(tree_obj);
    btree_free(tr);
    return lean_io_result_mk_ok(lean_box(0));
}

// Write (set) an element
// @[extern "btree_write"]
// def BTree.write (tree : @& BTree) (key : @& String) (data : @& ByteArray) : IO Unit
lean_obj_res btree_write(b_lean_obj_arg tree_obj, b_lean_obj_arg key_obj,
                         b_lean_obj_arg data_obj, lean_obj_arg /* io */) {
    struct btree *tr = (struct btree*)lean_unbox(tree_obj);

    // Extract key string
    char *key = lean_string_cstr(key_obj);

    // Clone the ByteArray for storage (increment ref count)
    lean_object *data_copy = data_obj;
    lean_inc(data_copy);

    struct element elem = {
        .key = strdup(key),
        .data = data_copy
    };

    btree_set(tr, &elem);
    return lean_io_result_mk_ok(lean_box(0));
}

// Read (get) an element
// @[extern "btree_read"]
// def BTree.read (tree : @& BTree) (key : @& String) : IO (Option ByteArray)
lean_obj_res btree_read(b_lean_obj_arg tree_obj, b_lean_obj_arg key_obj, lean_obj_arg /* io */) {
    struct btree *tr = (struct btree*)lean_unbox(tree_obj);

    // Extract key string
    char *key = lean_string_cstr(key_obj);

    struct element search_elem = { .key = key };
    const struct element *found = btree_get(tr, &search_elem);

    lean_object *result;
    if (found) {
        // Return some(data)
        lean_inc(found->data);
        result = lean_alloc_ctor(1, 1, 0); // some constructor
        lean_ctor_set(result, 0, found->data);
    } else {
        // Return none
        result = lean_alloc_ctor(0, 0, 0); // none constructor
    }

    return lean_io_result_mk_ok(result);
}

// Delete an element
// @[extern "btree_delete"]
// def BTree.delete (tree : @& BTree) (key : @& String) : IO Unit
lean_obj_res btree_delete_impl(b_lean_obj_arg tree_obj, b_lean_obj_arg key_obj, lean_obj_arg /* io */) {
    struct btree *tr = (struct btree*)lean_unbox(tree_obj);

    // Extract key string
    char *key = lean_string_cstr(key_obj);

    struct element search_elem = { .key = key };
    btree_delete(tr, &search_elem);

    return lean_io_result_mk_ok(lean_box(0));
}

// Filter by prefix - returns array of matching values
// @[extern "btree_filter"]
// def BTree.filter (tree : @& BTree) (prefix : @& String) : IO (Array ByteArray)
struct filter_ctx {
    lean_object *array;
};

static bool filter_callback(const void *item, void *udata) {
    const struct element *elem = item;
    struct filter_ctx *ctx = udata;

    // Add value (ByteArray) to array
    lean_inc(elem->data);
    ctx->array = lean_array_push(ctx->array, elem->data);

    return true; // continue iteration
}

lean_obj_res btree_filter(b_lean_obj_arg tree_obj, b_lean_obj_arg prefix_obj, lean_obj_arg /* io */) {
    struct btree *tr = (struct btree*)lean_unbox(tree_obj);
    char *prefix = lean_string_cstr(prefix_obj);

    // Create empty array
    lean_object *arr = lean_mk_empty_array();
    struct filter_ctx ctx = { .array = arr };

    // Find all elements with prefix
    btree_find_by_prefix(tr, prefix, filter_callback, &ctx);

    return lean_io_result_mk_ok(ctx.array);
}

// Get all keys - returns array of all keys in the tree
// @[extern "btree_keys"]
// def BTree.keys (tree : @& BTree) : IO (Array String)
struct keys_ctx {
    lean_object *array;
};

static bool keys_callback(const void *item, void *udata) {
    const struct element *elem = item;
    struct keys_ctx *ctx = udata;

    // Add key to array
    lean_object *key_str = lean_mk_string(elem->key);
    ctx->array = lean_array_push(ctx->array, key_str);

    return true; // continue iteration
}

lean_obj_res btree_keys(b_lean_obj_arg tree_obj, lean_obj_arg /* io */) {
    struct btree *tr = (struct btree*)lean_unbox(tree_obj);

    // Create empty array
    lean_object *arr = lean_mk_empty_array();
    struct keys_ctx ctx = { .array = arr };

    // Iterate through all elements
    btree_ascend(tr, NULL, keys_callback, &ctx);

    return lean_io_result_mk_ok(ctx.array);
}

// Save to file
// @[extern "btree_save"]
// def BTree.save (tree : @& BTree) (filename : @& String) : IO Unit
lean_obj_res btree_save_impl(b_lean_obj_arg tree_obj, b_lean_obj_arg filename_obj, lean_obj_arg /* io */) {
    struct btree *tr = (struct btree*)lean_unbox(tree_obj);
    char *filename = lean_string_cstr(filename_obj);

    if (!btree_save(tr, filename)) {
        return lean_io_result_mk_error(lean_mk_io_user_error(lean_mk_string("Failed to save BTree")));
    }

    return lean_io_result_mk_ok(lean_box(0));
}

// Load from file
// @[extern "btree_load"]
// def BTree.load (filename : @& String) : IO BTree
lean_obj_res btree_load_impl(b_lean_obj_arg filename_obj, lean_obj_arg /* io */) {
    char *filename = lean_string_cstr(filename_obj);

    struct btree *tr = btree_load_from_file(filename);
    if (!tr) {
        return lean_io_result_mk_error(lean_mk_io_user_error(lean_mk_string("Failed to load BTree")));
    }

    return lean_io_result_mk_ok(lean_box((size_t)tr));
}

