import Foundation
import RFCKit
import RFCReaderKit
import UserNotifications
import os

#if os(iOS)
  import BackgroundTasks
#endif

nonisolated private let notificationLog = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "me.mazetti.rfc-reader", category: "notifications")

/// Local notifications about bookmarked RFCs (#191). What changed is
/// `BookmarkEvents`', worked out in `LibraryModel.compareBookmarks()` after every
/// refresh of the index or the revisions; this only asks for permission, posts, and
/// arranges the daily refresh: a `BGAppRefreshTask` on iOS, and on macOS a loop
/// that lasts as long as the app runs, with no login item.
///
/// Off by default, and permission is asked only when the reader turns it on.
enum BookmarkNotifications {
  /// The background refresh, as `project.yml` declares it in
  /// `BGTaskSchedulerPermittedIdentifiers`.
  static let refreshIdentifier = "me.mazetti.rfc-reader.bookmark-refresh"
  /// The `rfc://` link a notification opens, in its `userInfo`.
  nonisolated static let urlKey = "url"
  /// How long after the last refresh iOS is asked for the next.
  static let refreshInterval: TimeInterval = 86_400
  /// How often macOS looks whether the index or the revisions are due, each by its
  /// own daily rule. An hour, not a day: a loop of exactly a day wakes a few seconds
  /// before what the last one fetched is a day old, and finds nothing due.
  static let checkInterval: TimeInterval = 3_600

  /// Held here: the notification center keeps its delegate weakly.
  private static let delegate = NotificationDelegate()

  static var isEnabled: Bool {
    UserDefaults.standard.bool(forKey: ReaderPreferences.notifyAboutBookmarksKey)
  }

  /// At launch, before a tap on a notification can be delivered: a tap that launched
  /// the app arrives as soon as it has finished launching.
  static func install() {
    UNUserNotificationCenter.current().delegate = delegate
    if isEnabled { scheduleRefresh() }
    #if os(macOS)
      Task(name: "Refresh bookmarks daily") {
        // The continuous clock, which runs on while the Mac sleeps, so a refresh
        // that fell due while it slept is made within the hour of waking.
        while true {
          try? await Task.sleep(for: .seconds(checkInterval))
          guard isEnabled else { continue }
          // Not waited for: the index check waits for a cheap network (#314) for as
          // long as the Mac is on an expensive one, and the next hour's look at the
          // revisions should not wait with it. A refresh still under way is joined.
          Task(name: "Refresh for bookmarks") { await LibraryModel.shared.refreshForBookmarks() }
        }
      }
    #endif
  }

  /// Asks for permission when the reader turns notifications on. False when it was
  /// refused, now or before, which turns the setting back off.
  static func requestPermission() async -> Bool {
    do {
      let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [
        .alert
      ])
      // Unless the reader turned it off again while the system asked.
      if granted, isEnabled { scheduleRefresh() }
      return granted
    } catch {
      notificationLog.error(
        "asking for notification permission failed: \(String(describing: error), privacy: .public)"
      )
      return false
    }
  }

  /// When the reader turns notifications off.
  static func disable() {
    #if os(iOS)
      BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshIdentifier)
    #endif
  }

  /// One notification per notice, grouped by RFC in Notification Center. Nothing
  /// when notifications are off: the comparison still runs, so that turning them on
  /// later starts from then, not from whatever changed before.
  static func post(_ notices: [BookmarkNotice]) async {
    guard isEnabled, !notices.isEmpty else { return }
    let center = UNUserNotificationCenter.current()
    for notice in notices {
      let content = UNMutableNotificationContent()
      content.title = notice.title
      if let subtitle = notice.subtitle { content.subtitle = subtitle }
      content.body = notice.body
      content.threadIdentifier = notice.document.fileStem
      content.userInfo = [urlKey: notice.url.absoluteString]
      let request = UNNotificationRequest(
        identifier: UUID().uuidString, content: content, trigger: nil)
      do {
        try await center.add(request)
      } catch {
        notificationLog.error(
          "posting a notification failed: \(String(describing: error), privacy: .public)")
      }
    }
  }

  /// Asks iOS for the next background refresh, a day from now at the earliest. The
  /// system decides when, from how the app is used; a newer request replaces the
  /// one pending.
  static func scheduleRefresh() {
    #if os(iOS)
      let request = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
      request.earliestBeginDate = .now.addingTimeInterval(refreshInterval)
      do {
        try BGTaskScheduler.shared.submit(request)
      } catch {
        notificationLog.error(
          "scheduling the bookmark refresh failed: \(String(describing: error), privacy: .public)"
        )
      }
    #endif
  }

  /// iOS's background refresh: schedules the next, then refreshes and compares.
  static func refreshInBackground() async {
    guard isEnabled else { return }
    scheduleRefresh()
    await LibraryModel.shared.refreshForBookmarks()
  }
}

/// Shows a notification while the app is in front, where most comparisons happen,
/// and opens a tapped one's RFC the way any `rfc://` link is opened.
///
/// `nonisolated`, as the center calls it on a queue of its own.
nonisolated private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate,
  Sendable
{
  func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .list]
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
  ) async {
    let userInfo = response.notification.request.content.userInfo
    guard let string = userInfo[BookmarkNotifications.urlKey] as? String,
      let url = URL(string: string), let link = RFCLink(url: url)
    else { return }
    await MainActor.run { LibraryModel.shared.route(link) }
  }
}
