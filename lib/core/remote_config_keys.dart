// lib/core/remote_config_keys.dart
// Chaves do Remote Config para externalizar dados sensíveis (ETAPA 16).
// Flags OFF por padrão; com OFF o comportamento é idêntico ao hardcoded.

/// Chave JSON com lista de e-mails de root admins (array ou string CSV).
/// Ex.: ["a@b.com"] ou "a@b.com,b@c.com"
const String rcRootAdminEmailsJson = 'rc_root_admin_emails_json';

/// Chave JSON com lista de hosts permitidos para App Check Web (array ou string CSV).
/// Ex.: ["host1.com","host2.com"]
const String rcAppcheckAllowedHostsJson = 'rc_appcheck_allowed_hosts_json';

/// Flag: quando true, root admins vêm de rc_root_admin_emails_json.
/// Default: false (usa lista hardcoded no cliente).
const String rcEnableDynamicRootAdmins = 'rc_enable_dynamic_root_admins';

/// Flag: quando true, hosts App Check Web vêm de rc_appcheck_allowed_hosts_json.
/// Default: false (usa lista hardcoded).
const String rcEnableDynamicAppcheckHosts = 'rc_enable_dynamic_appcheck_hosts';
