#ifndef CSQLITEVEC_UMBRELLA_H
#define CSQLITEVEC_UMBRELLA_H

#include <sqlite3.h>
#include "sqlite-vec.h"

/// Registers `sqlite3_vec_init` as a SQLite auto-extension. Wrapped in C
/// so the function-pointer cast is well-defined; Swift's `unsafeBitCast`
/// trips a debug-runtime assertion on differing function-type metadata.
void csqlitevec_register_auto_extension(void);

/// Initialises sqlite-vec on an already-open connection. Used from GRDB's
/// `Configuration.prepareDatabase` so every pool connection inherits the
/// `vec0` virtual table. Returns SQLITE_OK on success.
int csqlitevec_init_on_connection(sqlite3 *db);

#endif
