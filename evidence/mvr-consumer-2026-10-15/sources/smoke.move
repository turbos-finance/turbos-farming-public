module consumer::smoke { use turbos_farming::config; public fun version(): u64 { config::package_version() } }
