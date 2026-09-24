#import <UIKit/UIKit.h>
#define SGRKeySing @"spotifyglass.redesign.sing"
// Owned by the lyrics overlay in Now Playing (Redesigned/Player/PlayerLyrics.x). `lyrics` is the lines'
// band in the page's coordinates, and the microphone sits in its bottom trailing corner. `immersive` is
// the controls away: the microphone stays only while Sing is on. `hold` is called with YES while it is
// open, preparing or explaining itself, and with NO once it is none of them.
UIView *SGRSingControlForPage(UIView *page, CGRect lyrics, BOOL immersive, void (^hold)(BOOL));
void SGRSingControlDismiss(UIView *page);
