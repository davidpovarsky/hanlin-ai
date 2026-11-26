const keyboardContext = $getenv('presentation');
function insertGreeting(): void { $presentation.keyboard.insertText('שלום '); }
function insertThanks(): void { $presentation.keyboard.insertText('תודה רבה '); }
function deleteLast(): void { $presentation.keyboard.deleteBackward(); }
function moveCursorLeft(): void { $presentation.keyboard.adjustTextPosition(-1); }
function nextKeyboard(): void { $presentation.keyboard.nextInputMode(); }
$render(
  <vstack spacing={8} padding={8}>
    <text font="headline">מחברת — מקלדת מקורית</text>
    <text font="caption">{keyboardContext ? keyboardContext.keyboard?.selectedText || 'אפשר להוסיף ביטוי בשדה הטקסט הפעיל' : 'הקשר מקלדת אינו זמין'}</text>
    <hstack spacing={8}>
      <button actionID="keys.greeting"><text>שלום</text></button>
      <button actionID="keys.thanks"><text>תודה רבה</text></button>
    </hstack>
    <hstack spacing={8}>
      <button actionID="keys.delete"><text>מחיקה</text></button>
      <button actionID="keys.left"><text>שמאלה</text></button>
      <button actionID="keys.next"><text>המקלדת הבאה</text></button>
    </hstack>
  </vstack>
);
