enum RuleSeverity { info, yellow, red, blocking }

class RuleViolation {
  RuleViolation({
    required this.code,
    required this.severity,
    required this.message,
    this.file,
    this.method,
    this.evidence,
    this.risk,
    this.requiredAction,
  });

  final String code;
  final RuleSeverity severity;
  final String message;
  final String? file;
  final String? method;
  final String? evidence;
  final String? risk;
  final String? requiredAction;

  Map<String, dynamic> toJson() => {
        'code': code,
        'severity': severity.name,
        'message': message,
        if (file != null) 'file': file,
        if (method != null) 'method': method,
        if (evidence != null) 'evidence': evidence,
        if (risk != null) 'risk': risk,
        if (requiredAction != null) 'required_action': requiredAction,
      };
}
