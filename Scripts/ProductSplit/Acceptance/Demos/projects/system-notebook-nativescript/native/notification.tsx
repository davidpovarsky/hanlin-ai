const noticeContext = $getenv('presentation');
const noticeParameters = noticeContext ? noticeContext.parameters : null;
const noticeMessage = noticeParameters !== null && typeof noticeParameters === 'object' && !Array.isArray(noticeParameters)
  && typeof noticeParameters.message === 'string' ? noticeParameters.message : 'פעולה ממתינה במחברת.';
function continueInApp(): void { $presentation.notification.openApp(); }
function dismissNotice(): void { $presentation.notification.dismiss(); }
$render(
  <vstack spacing={12} padding={12}>
    <text font="headline">מחברת המערכת</text>
    <text>{noticeMessage}</text>
    <button actionID="notice.open"><text>המשך במחברת</text></button>
    <button actionID="notice.dismiss"><text>סגירת ההתראה</text></button>
  </vstack>
);
