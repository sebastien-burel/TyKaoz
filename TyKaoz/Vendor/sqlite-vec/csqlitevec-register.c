#include <sqlite3.h>
#include "sqlite-vec.h"
#include "csqlitevec-umbrella.h"

int csqlitevec_init_on_connection(sqlite3 *db) {
    // Compiled with -DSQLITE_CORE so sqlite3_vec_init links directly
    // against libsqlite3 symbols — passing NULL for the API routines is
    // safe (the extension API indirection is compiled out).
    return sqlite3_vec_init(db, 0, 0);
}
