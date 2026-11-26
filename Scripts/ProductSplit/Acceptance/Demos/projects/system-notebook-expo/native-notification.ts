/** Actual original UserNotifications API. Used directly by NativeScript and through the original Expo Native API worklet. */
export function scheduleNativeNotice(id: string, userInfoJSON: string): Promise<{requestID: string; scheduled: true}> {
  'worklet';
  return new Promise((resolve, reject) => {
    const center = UNUserNotificationCenter.currentNotificationCenter();
    center.requestAuthorizationWithOptionsCompletionHandler(UNAuthorizationOptions.Alert | UNAuthorizationOptions.Sound, (allowed, error) => {
      if (error) { reject(new Error(error.localizedDescription)); return; }
      if (!allowed) { reject(new Error('הרשאת ההתראות אינה זמינה.')); return; }
      try {
        const content = UNMutableNotificationContent.new();
        content.title = 'מחברת המערכת'; content.body = 'לחיצה ממושכת מציגה את הממשק העשיר.';
        content.categoryIdentifier = 'CHAVRUSA_REMINDER';
        const data = NSString.stringWithString(userInfoJSON).dataUsingEncoding(NSUTF8StringEncoding);
        if (!data) throw new Error('Could not encode notification JSON.');
        const dictionary = NSJSONSerialization.JSONObjectWithDataOptionsError(data, NSJSONReadingOptions.MutableContainers, null);
        if (!(dictionary instanceof NSDictionary)) throw new Error('Notification userInfo is not a dictionary.');
        content.userInfo = dictionary;
        const trigger = UNTimeIntervalNotificationTrigger.triggerWithTimeIntervalRepeats(10, false);
        const request = UNNotificationRequest.requestWithIdentifierContentTrigger(id, content, trigger);
        center.addNotificationRequestWithCompletionHandler(request, failure => {
          if (failure) reject(new Error(failure.localizedDescription));
          else resolve({requestID: id, scheduled: true}); // Scheduled is not delivered, rendered or executed.
        });
      } catch (failure) { reject(failure); }
    });
  });
}
