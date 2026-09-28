// Spotify's classes change between releases, so on any build but SGSupportedSpotifyVersion the mod half
// works and the bug reports that come of it can't be acted on. Said once per Spotify version, and from
// a red row at the top of Mod Settings for as long as that version runs.
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "About.h"
#import "App/Onboarding/Onboarding.h"
#import "App/Sheet/SGCardSheet.h"

static NSString *const kWarned = @"spotifyglass.spotifyversion.warned";
static const NSTimeInterval kSettle = 3, kRetry = 4;
static const NSInteger kTries = 45;

static NSString *running(void) {
    id version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    return [version isKindOfClass:NSString.class] ? version : nil;
}

BOOL SGSpotifyVersionSupported(void) {
    NSString *version = running();
    return !version || [version isEqualToString:SGSupportedSpotifyVersion];
}

static NSString *warningTitle(void) {
    return [NSString stringWithFormat:@"Spotify %@ isn't supported", running()];
}

static void showWarning(void) {
    UIViewController *top = SGTopController();
    if (!top) return;
    NSString *message = [NSString stringWithFormat:
        @"spoti.pw is made for Spotify %@ only. On any other version parts of it break or go missing, "
        @"so it won't work the way you expect.\n\n"
        @"Please don't open issues or report bugs on Discord from this version. Use a %@ IPA instead.",
        SGSupportedSpotifyVersion, SGSupportedSpotifyVersion];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:warningTitle()
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [top presentViewController:alert animated:YES completion:nil];
}

SGModRow *SGSpotifyVersionWarningRow(void) {
    if (SGSpotifyVersionSupported()) return nil;
    NSString *subtitle = [NSString stringWithFormat:@"The mod is made for %@ only", SGSupportedSpotifyVersion];
    return SGWarningRow(warningTitle(), subtitle, ^{ showWarning(); });
}

// Stored only once it is up, so a run that never found a clear screen tries again next launch.
static void warnWhenClear(NSInteger tries) {
    UIViewController *top = SGTopController();
    BOOL busy = !top || SGOnboardingShowing() || [top isKindOfClass:UIAlertController.class]
        || [top isKindOfClass:SGCardSheet.class]
        || UIApplication.sharedApplication.applicationState != UIApplicationStateActive;
    if (busy) {
        if (tries > 0)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRetry * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ warnWhenClear(tries - 1); });
        return;
    }
    [NSUserDefaults.standardUserDefaults setObject:running() forKey:kWarned];
    showWarning();
    SGLog(@"spotify version: warned about %@ over %@", running(), NSStringFromClass(top.class));
}

void SGCheckSpotifyVersionOnce(void) {
    if (SGSpotifyVersionSupported()) return;
    SGLog(@"spotify version: running %@, the mod is made for %@", running(), SGSupportedSpotifyVersion);
    if ([[NSUserDefaults.standardUserDefaults stringForKey:kWarned] isEqualToString:running()]) return;
    __block id observer = [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
                                                                          object:nil
                                                                           queue:NSOperationQueue.mainQueue
                                                                      usingBlock:^(NSNotification *note) {
        [NSNotificationCenter.defaultCenter removeObserver:observer];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSettle * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ warnWhenClear(kTries); });
    }];
}
