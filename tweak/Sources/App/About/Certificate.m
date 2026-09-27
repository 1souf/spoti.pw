// How this copy is signed, read from the provisioning profile inside the app. A free Apple ID's profile
// lasts 7 days, so those installs are offered a certificate now and then: a sheet when the signature is
// about to run out or has been renewed before, and a row in Mod Settings. spoti.pw writes the sheet and
// can turn it off; nothing of the profile but its kind leaves the phone.
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "About.h"
#import "App/Onboarding/Onboarding.h"
#import "App/Donate/Donate.h"

static NSString *const kOfferURL = @"https://spoti.pw/api/certificate";
static NSString *const kCertificateURL = @"https://spoti.pw/go/cert";
// Outside "spotifyglass." so Reset all settings doesn't bring the sheet back early.
static NSString *const kProfilesKey = @"spotipw.cert.profiles";
static NSString *const kShownKey = @"spotipw.cert.shown";

static const NSTimeInterval kDay = 86400;
static const NSTimeInterval kFreeLongest = 8 * kDay;
static const NSTimeInterval kDueWithin = 2 * kDay, kRest = 30 * kDay;
static const NSTimeInterval kSettle = 30, kRetry = 5;
static const NSInteger kTries = 24;
static const NSUInteger kProfilesKept = 8;

static BOOL sg_offered;

static NSDictionary *profile(void) {
    static NSDictionary *read;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *path = [NSBundle.mainBundle pathForResource:@"embedded" ofType:@"mobileprovision"];
        NSData *data = path ? [NSData dataWithContentsOfFile:path] : nil;
        if (!data.length) return;
        // The plist sits as plain text inside the profile's CMS envelope.
        NSRange all = NSMakeRange(0, data.length);
        NSRange start = [data rangeOfData:[@"<?xml" dataUsingEncoding:NSASCIIStringEncoding] options:0 range:all];
        NSRange end = [data rangeOfData:[@"</plist>" dataUsingEncoding:NSASCIIStringEncoding] options:NSDataSearchBackwards range:all];
        if (start.location == NSNotFound || end.location == NSNotFound || end.location < start.location) return;
        NSData *plist = [data subdataWithRange:NSMakeRange(start.location, NSMaxRange(end) - start.location)];
        id parsed = [NSPropertyListSerialization propertyListWithData:plist options:0 format:NULL error:NULL];
        if ([parsed isKindOfClass:NSDictionary.class]) read = parsed;
    });
    return read;
}

static NSDate *dateIn(NSDictionary *info, NSString *key) {
    id value = info[key];
    return [value isKindOfClass:NSDate.class] ? value : nil;
}

NSDate *SGCertificateExpiry(void) {
    return dateIn(profile(), @"ExpirationDate");
}

NSString *SGCertificateKind(void) {
    NSDictionary *info = profile();
    if (!info) return @"none";
    if ([info[@"ProvisionsAllDevices"] boolValue]) return @"enterprise";
    NSDate *created = dateIn(info, @"CreationDate"), *expires = dateIn(info, @"ExpirationDate");
    if (!created || !expires) return nil;
    return [expires timeIntervalSinceDate:created] <= kFreeLongest ? @"free" : @"paid";
}

static BOOL signedFree(void) {
    return [SGCertificateKind() isEqualToString:@"free"];
}

// The free profiles this install has run under, this one included; each renewal brings a new one.
static NSUInteger profilesSeen(void) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    NSArray *seen = [store arrayForKey:kProfilesKey] ?: @[];
    id uuid = profile()[@"UUID"];
    if ([uuid isKindOfClass:NSString.class] && ![seen containsObject:uuid]) {
        seen = [seen arrayByAddingObject:uuid];
        if (seen.count > kProfilesKept) seen = [seen subarrayWithRange:NSMakeRange(seen.count - kProfilesKept, kProfilesKept)];
        [store setObject:seen forKey:kProfilesKey];
    }
    return seen.count;
}

static BOOL due(void) {
    if (!signedFree()) return NO;
    NSUInteger renewals = profilesSeen();
    double shown = [NSUserDefaults.standardUserDefaults doubleForKey:kShownKey];
    if (shown > 0 && NSDate.date.timeIntervalSince1970 - shown < kRest) return NO;
    return renewals >= 2 || [SGCertificateExpiry() timeIntervalSinceNow] < kDueWithin;
}

static NSString *dayOf(NSDate *date) {
    NSDateFormatter *format = [NSDateFormatter new];
    format.locale = [NSLocale localeWithLocaleIdentifier:@"en"];
    format.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"EEEEdMMMM" options:0 locale:format.locale];
    return [format stringFromDate:date];
}

BOOL SGCertificateOfferShown(void) {
    return sg_offered;
}

SGModRow *SGCertificateRow(void) {
    if (!signedFree()) return nil;
    NSDate *expires = SGCertificateExpiry();
    NSString *title = expires ? [NSString stringWithFormat:@"Signed until %@", dayOf(expires)] : @"Signed with a free Apple ID";
    return SGWithSymbol(SGLinkRow(title, @"A free Apple ID signs for 7 days, a certificate for a year", kCertificateURL), @"signature");
}

#pragma mark - the sheet

static NSString *textIn(NSDictionary *offer, NSString *key) {
    id value = offer[key];
    return [value isKindOfClass:NSString.class] && [value length] ? value : nil;
}

// Anything but a 200 with show set, or a reply missing a piece, is no sheet this time.
static void fetchOffer(void (^done)(NSDictionary *offer)) {
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.timeoutIntervalForRequest = 10;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:kOfferURL]
                                             cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                         timeoutInterval:10];
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        id json = status == 200 && data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        NSDictionary *offer = [json isKindOfClass:NSDictionary.class] && [json[@"show"] isEqual:@YES] ? json : nil;
        if (offer && !(textIn(offer, @"title") && textIn(offer, @"message") && textIn(offer, @"action")
                       && [textIn(offer, @"url") hasPrefix:@"https://"])) offer = nil;
        dispatch_async(dispatch_get_main_queue(), ^{ done(offer); });
    }] resume];
    [session finishTasksAndInvalidate];
}

static BOOL screenBusy(UIViewController *top) {
    return !top || SGOnboardingShowing() || [top isKindOfClass:UIAlertController.class]
        || UIApplication.sharedApplication.applicationState != UIApplicationStateActive;
}

static void present(NSDictionary *offer, UIViewController *top) {
    NSDate *expires = SGCertificateExpiry();
    NSString *day = expires ? dayOf(expires) : @"soon";
    NSString *title = [textIn(offer, @"title") stringByReplacingOccurrencesOfString:@"{date}" withString:day];
    NSString *message = [textIn(offer, @"message") stringByReplacingOccurrencesOfString:@"{date}" withString:day];
    NSString *url = textIn(offer, @"url");
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:title message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [sheet addAction:[UIAlertAction actionWithTitle:textIn(offer, @"action") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        SGLog(@"certificate: sheet opened the link");
        SGOpenURL(url);
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:textIn(offer, @"dismiss") ?: @"Not now" style:UIAlertActionStyleCancel handler:nil]];
    [top presentViewController:sheet animated:YES completion:nil];
}

// Once a run at most, never in a run with the update notice or the donate sheet, and never over the
// tour or an alert. The screen is checked again after the request, which can take a while.
static void offerWhenClear(NSInteger tries) {
    if (sg_offered || SGUpdateNoticeShown() || SGDonateShown() || !due()) return;
    if (screenBusy(SGTopController())) {
        if (tries > 0)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRetry * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ offerWhenClear(tries - 1); });
        return;
    }
    sg_offered = YES;
    fetchOffer(^(NSDictionary *offer) {
        UIViewController *top = SGTopController();
        if (!offer || screenBusy(top) || SGUpdateNoticeShown() || SGDonateShown()) {
            SGLog(@"certificate: sheet due, not shown (%@)", offer ? @"screen busy" : @"no offer from spoti.pw");
            return;
        }
        [NSUserDefaults.standardUserDefaults setDouble:NSDate.date.timeIntervalSince1970 forKey:kShownKey];
        SGDonateHoldOff();
        present(offer, top);
        SGLog(@"certificate: sheet shown, signature runs out %@", SGCertificateExpiry());
    });
}

void SGWatchForCertificate(void) {
    NSString *kind = SGCertificateKind();
    SGLog(@"certificate: %@%@", kind ?: @"unreadable profile",
          [kind isEqualToString:@"free"] ? [NSString stringWithFormat:@", runs out %@", SGCertificateExpiry()] : @"");
    if (!signedFree()) return;
    profilesSeen();
    __block id observer = [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
                                                                          object:nil
                                                                           queue:NSOperationQueue.mainQueue
                                                                      usingBlock:^(NSNotification *note) {
        [NSNotificationCenter.defaultCenter removeObserver:observer];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSettle * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ offerWhenClear(kTries); });
    }];
}
