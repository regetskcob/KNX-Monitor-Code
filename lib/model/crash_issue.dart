/// Prefilled public issue after an unexpected end (public issue #4): the issue
/// form `crash_report.yml` in the public repository takes its fields from the
/// query (by field id). Only version, platform, time and reason go into the
/// address: no log, no addresses, no names. The address ends up in the browser
/// history and has a length limit; the user attaches the scrubbed package
/// themselves.
library;

/// Fields of the issue form, in this order.
typedef CrashIssue = ({String version, String platform, String time, String reason});

/// Address of the new issue in the public repository.
Uri crashIssueUrl(CrashIssue issue) => Uri.https('github.com', '/regetskcob/KNX-Monitor/issues/new', {
  'template': 'crash_report.yml',
  // Public issues have a German title first.
  'title': 'Unerwartet beendet: ${issue.version} auf ${issue.platform}',
  'version': issue.version,
  'platform': issue.platform,
  'time': issue.time,
  'reason': issue.reason,
});
