// Sing in the redesign: its switch and the Karaoke section of the Lyrics page. The work itself is
// Shared/Sing's; its microphone in the player's lyrics is SGRSingControl.h's.
#import <Foundation/Foundation.h>

#define SGRKeySing @"spotifyglass.redesign.sing"   // off until switched on

// Hands the switch to Shared/Sing while the redesign runs (Sing.x), at launch and as it is turned:
// the microphone comes and goes at once, no restart.
void SGRSingApplySwitch(void);

// SingSettings.m: Lyrics > Karaoke, with the switch and the voice model's download.
@class SGModSection;
SGModSection *SGRKaraokeSection(void);
