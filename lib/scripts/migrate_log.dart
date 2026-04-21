import 'package:master_palm/scripts/migrate_log_io.dart'
    if (dart.library.html) 'package:master_palm/scripts/migrate_log_web.dart'
    as mig_log;

void migrateLogOut(String message) => mig_log.migrateLogOut(message);

void migrateLogErr(String message) => mig_log.migrateLogErr(message);
