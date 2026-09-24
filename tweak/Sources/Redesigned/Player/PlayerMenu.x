// Player redesign: the ⋯ opens a menu drawn the way the Music app draws its own (SGRPlayerMenu.h) in place
// of Spotify's sheet of rows -- while what is in it, and what each row does, stay Spotify's.
//
// **Why Spotify's sheet still opens.** The rows come from Swift item factories with no way in, and which
// there are depends on the track, where it plays from (Remove from this playlist only in one's own), the
// account, the market and the flags, and on what is playing at all (an episode has rows of its own); each
// is in the app's language and does something only Spotify's own code knows how to. A menu of hand-written
// actions would be the trap Redesigned/Playlist/PlaylistMenu.x describes. So the ⋯ opens Spotify's sheet as
// it always did and the sheet is the menu's source: it is kept out of sight -- its presented view hidden
// and taking no touches, its dimming cleared -- its rows are read off its table, and the card is put over it
// in the presentation's container, grown out of the ⋯.
//
// **Spotify's rows** (trees/continuous/1.txt:648): each cell of ContextMenuTableView holds an Encore ListRow,
// a UIControl (ListRow < Layout < Box < PassthroughControl) whose accessibility identifier is the item's
// number -- 9 Share, 11 Add to Queue, 19 Add to playlist, 27 Remove from this playlist, 28 Lyrics, 34 Go to
// Queue, 59 Exclude track from your taste profile -- with its glyph and its words in it. The number is what
// places a row on the card (kKnown); a number the table does not know goes under More, in Spotify's order,
// so nothing Spotify offers is lost and nothing added later has to be known here first. Every number seen
// is logged once, with its words, for the table to grow from. The table's binder
// (ContextMenuItem.TableBinder, 9.1.78) answers the data source and willDisplayCell: only -- there is no
// didSelectRowAtIndexPath: -- so a row is fired through its ListRow (SGRActivate), as a tap would. Only the
// cells on screen exist, and the hidden table is as short as the sheet would have been, so it is made tall
// enough for all of them for the moment they are read or a row is fired, and put back.
//
// **What Spotify then does** is what it always does: it dismisses the sheet and acts (the card goes with the
// sheet), or pushes a page of its own onto the sheet (Share's destinations, a list of artists) -- the sheet
// is then shown the way Spotify drew it and the card goes -- or changes the row in place (Lyrics • Off to
// On), which the card reads again. A tap outside the card dismisses the sheet, as a tap on Spotify's dimming
// did.
//
// **Where it falls back** to Spotify's sheet as it was: no table in it, no rows within kRowsWait, a row that
// cannot be found again to fire, and the switch off (SGRKeyPlayerMenu, read at launch).
//
// Which sheet is the player's: one that appears within kMenuAfterTap of a tap on the player's ⋯, which
// PlayerHeader.x hands over. Speed and pitch (Shared/Player) still puts its block into the hidden sheet; the
// card has a row of its own for them that opens onto the same sliders (SGSpeedPitchPanelMake).
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Shared/Player/SpeedPitch.h"
#import "Player.h"
#import "SGRPlayerMenu.h"

// A sheet this soon after the ⋯'s tap is the player's.
static const NSTimeInterval kMenuAfterTap = 3;
// No rows by then and Spotify's own sheet is shown instead, with whatever it is showing.
static const NSTimeInterval kRowsWait = 4;
// The black behind the card; Spotify's dimming is 0.7, which is a sheet's and not a menu's.
static const CGFloat kDimming = 0.2;

static BOOL sgr_menuOn;
static __weak UIView *sgr_moreButton;
static NSTimeInterval sgr_moreTappedAt;
static char kTakeoverKey, kWatchedKey, kDimmingKey, kDimmingColorKey, kMaskKey;

#pragma mark - where each of Spotify's rows goes

typedef NS_ENUM(NSInteger, SGRPlayerMenuPlace) {
    SGRPlaceMore,          // under More, the default for a number not known here
    SGRPlaceTile,          // the row of three across the top
    SGRPlaceMain,          // the first group of rows
    SGRPlaceFeedback,      // with More
    SGRPlaceDestructive,   // last, in red
};

typedef struct {
    const char *identifier;
    SGRPlayerMenuPlace place;
    const char *symbol;
} SGRPlayerMenuKnownRow;

// Numbers read off the ListRows of 9.1.78 (trees/continuous/1.txt:650-716). The glyphs are the Music app's
// for the same thing where it has one.
static const SGRPlayerMenuKnownRow kKnown[] = {
    {"19", SGRPlaceTile, "text.badge.plus"},                              // Add to playlist
    {"11", SGRPlaceTile, "text.line.last.and.arrowtriangle.forward"},     // Add to Queue
    {"9", SGRPlaceTile, "square.and.arrow.up"},                           // Share
    {"59", SGRPlaceFeedback, "hand.thumbsdown"},                          // Exclude track from your taste profile
    {"27", SGRPlaceDestructive, "minus.circle"},                          // Remove from this playlist
    {"28", SGRPlaceMore, "quote.bubble"},                                 // Lyrics • On/Off: the redesign shows its own
    {"34", SGRPlaceMore, "list.bullet"},                                  // Go to Queue: the footer has the queue glyph
};

static const SGRPlayerMenuKnownRow *knownRow(NSString *identifier) {
    for (size_t i = 0; i < sizeof(kKnown) / sizeof(kKnown[0]); i++) {
        if ([identifier isEqualToString:@(kKnown[i].identifier)]) return &kKnown[i];
    }
    return NULL;
}

static UIImage *symbol(NSString *name) {
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightRegular];
    return name ? [UIImage systemImageNamed:name withConfiguration:config] : nil;
}

#pragma mark - the player's ⋯

@interface SGRPlayerMoreTapWatcher : NSObject <UIGestureRecognizerDelegate>
@end

@implementation SGRPlayerMoreTapWatcher
- (void)tapped:(id)sender {
    UIView *button = [sender isKindOfClass:UIGestureRecognizer.class] ? ((UIGestureRecognizer *)sender).view : sender;
    sgr_moreButton = button;
    sgr_moreTappedAt = CACurrentMediaTime();
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}
@end

void SGRPlayerMenuWatchMoreButton(UIView *button) {
    if (!sgr_menuOn || !button || objc_getAssociatedObject(button, &kWatchedKey)) return;
    static SGRPlayerMoreTapWatcher *watcher;
    if (!watcher) watcher = [SGRPlayerMoreTapWatcher new];
    objc_setAssociatedObject(button, &kWatchedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // An Encore button may read its touches through a gesture recognizer rather than as a control, so both
    // are watched, as Speed and pitch watches it.
    if ([button isKindOfClass:UIControl.class]) {
        [(UIControl *)button addTarget:watcher action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside | UIControlEventPrimaryActionTriggered];
    }
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:watcher action:@selector(tapped:)];
    tap.cancelsTouchesInView = NO;
    tap.delaysTouchesEnded = NO;
    tap.delegate = watcher;
    [button addGestureRecognizer:tap];
}

#pragma mark - Spotify's rows, read

@interface SGRPlayerMenuSpotifyRow : NSObject
@property (nonatomic, strong) NSIndexPath *indexPath;
@property (nonatomic, copy) NSString *identifier, *title, *subtitle;
@property (nonatomic, strong) UIImage *image;
@property (nonatomic) BOOL disabled;
@end

@implementation SGRPlayerMenuSpotifyRow
@end

static UITableView *tableIn(UIView *root, int depth) {
    if ([root isKindOfClass:UITableView.class]) return (UITableView *)root;
    if (!root || depth > 6) return nil;
    for (UIView *child in root.subviews) {
        UITableView *table = tableIn(child, depth + 1);
        if (table) return table;
    }
    return nil;
}

static NSInteger rowCount(UITableView *table) {
    NSInteger rows = 0;
    for (NSInteger section = 0; section < table.numberOfSections; section++) rows += [table numberOfRowsInSection:section];
    return rows;
}

// The ListRow of a cell: the control that carries the item's number.
static UIControl *listRowIn(UITableViewCell *cell) {
    __block UIControl *found = nil;
    SGForEachView(cell.contentView, ^(UIView *v) {
        if (!found && [v isKindOfClass:UIControl.class] && v.accessibilityIdentifier.length) found = (UIControl *)v;
    });
    return found;
}

static BOOL shown(UIView *view, UIView *within) {
    for (UIView *v = view; v && v != within; v = v.superview) {
        if (v.hidden || v.alpha < 0.01) return NO;
    }
    return YES;
}

static SGRPlayerMenuSpotifyRow *readRow(UITableViewCell *cell, NSIndexPath *indexPath) {
    UIControl *control = listRowIn(cell);
    if (!control) return nil;
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    __block UIImageView *glyph = nil;
    SGForEachView(control, ^(UIView *v) {
        if ([v isKindOfClass:UILabel.class] && ((UILabel *)v).text.length && shown(v, control)) [labels addObject:(UILabel *)v];
        if (!glyph && [v isKindOfClass:UIImageView.class] && ((UIImageView *)v).image && v.bounds.size.width <= 40 && shown(v, control)) glyph = (UIImageView *)v;
    });
    if (!labels.count) return nil;
    [labels sortUsingComparator:^NSComparisonResult(UILabel *a, UILabel *b) {
        CGPoint pa = [a convertPoint:CGPointZero toView:control], pb = [b convertPoint:CGPointZero toView:control];
        if (fabs(pa.y - pb.y) > 1) return pa.y < pb.y ? NSOrderedAscending : NSOrderedDescending;
        return pa.x < pb.x ? NSOrderedAscending : NSOrderedDescending;
    }];
    SGRPlayerMenuSpotifyRow *row = [SGRPlayerMenuSpotifyRow new];
    row.indexPath = indexPath;
    row.identifier = control.accessibilityIdentifier;
    row.title = labels[0].text;
    if (labels.count > 1) row.subtitle = labels[1].text;
    // "Lyrics • Off" is one label of Spotify's: its state goes under the words, the way the Music app puts it.
    NSRange dot = [row.title rangeOfString:@" • "];
    if (!row.subtitle && dot.location != NSNotFound && dot.location > 0) {
        row.subtitle = [row.title substringFromIndex:NSMaxRange(dot)];
        row.title = [row.title substringToIndex:dot.location];
    }
    row.image = glyph.image;
    row.disabled = !control.enabled || !shown(control, cell);
    return row;
}

// Runs `block` with every row of the table laid out: the hidden table is as short as the sheet would be,
// and only its cells on screen exist, so for the moment of the block it is as tall as its content.
static void withEveryCell(UITableView *table, void (^block)(void)) {
    CGRect saved = table.bounds;
    CGFloat top = -table.adjustedContentInset.top;
    CGFloat tall = table.contentSize.height + table.adjustedContentInset.top + table.adjustedContentInset.bottom;
    BOOL grow = tall > saved.size.height + 0.5 || fabs(saved.origin.y - top) > 0.5;
    if (grow) {
        table.bounds = CGRectMake(saved.origin.x, top, saved.size.width, MAX(tall, saved.size.height));
        [table layoutIfNeeded];
    }
    block();
    if (grow) {
        table.bounds = saved;
        [table layoutIfNeeded];
    }
}

static NSArray<SGRPlayerMenuSpotifyRow *> *readRows(UITableView *table) {
    NSInteger count = rowCount(table);
    if (!count) return @[];
    NSMutableArray<SGRPlayerMenuSpotifyRow *> *rows = [NSMutableArray array];
    withEveryCell(table, ^{
        for (NSInteger section = 0; section < table.numberOfSections; section++) {
            for (NSInteger item = 0; item < [table numberOfRowsInSection:section]; item++) {
                NSIndexPath *indexPath = [NSIndexPath indexPathForRow:item inSection:section];
                UITableViewCell *cell = [table cellForRowAtIndexPath:indexPath];
                SGRPlayerMenuSpotifyRow *row = cell ? readRow(cell, indexPath) : nil;
                if (row) [rows addObject:row];
            }
        }
    });
    if ((NSInteger)rows.count < count) {
        static int logged;
        if (logged++ < 3) SGLog(@"redesign player menu: read %lu of the table's %ld rows", (unsigned long)rows.count, (long)count);
    }
    return rows;
}

static NSString *signatureOf(NSArray<SGRPlayerMenuSpotifyRow *> *rows) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (SGRPlayerMenuSpotifyRow *row in rows) [parts addObject:[NSString stringWithFormat:@"%@=%@|%@|%d", row.identifier, row.title, row.subtitle ?: @"", row.disabled]];
    return [parts componentsJoinedByString:@", "];
}

// Every number once, with its words and where it went, so kKnown can grow from the log.
static void logNumbers(NSArray<SGRPlayerMenuSpotifyRow *> *rows) {
    static NSMutableSet<NSString *> *seen;
    if (!seen) seen = [NSMutableSet set];
    NSMutableArray<NSString *> *fresh = [NSMutableArray array];
    for (SGRPlayerMenuSpotifyRow *row in rows) {
        if ([seen containsObject:row.identifier]) continue;
        [seen addObject:row.identifier];
        [fresh addObject:[NSString stringWithFormat:@"%@ \"%@\"%@", row.identifier, row.title, knownRow(row.identifier) ? @"" : @" (under More)"]];
    }
    if (fresh.count) SGLog(@"redesign player menu: Spotify's rows %@", [fresh componentsJoinedByString:@", "]);
}

#pragma mark - the takeover of one sheet

@interface SGRPlayerMenuTakeover : NSObject
@property (nonatomic, weak) UIViewController *menu;
@property (nonatomic, weak) UIViewController *sheet;   // the presented container the menu is in
@property (nonatomic, strong) SGRPlayerMenuCard *card;
@property (nonatomic, strong) UIControl *catcher;      // under the card: the dimming, and a tap outside
@property (nonatomic, weak) UIView *button;
@property (nonatomic, copy) NSString *signature;
@property (nonatomic) BOOL hasRows, revealed, closing, grown;
@property (nonatomic, strong) id speedObserver;
@property (nonatomic, strong) CALayer *savedMask;   // the sheet's own mask, if it had one, to put back
@end

@implementation SGRPlayerMenuTakeover
- (void)dealloc {
    if (_speedObserver) [NSNotificationCenter.defaultCenter removeObserver:_speedObserver];
}

- (void)catcherTapped {
    UIViewController *sheet = self.sheet;
    SGLog(@"redesign player menu: a tap outside the card closes it");
    [sheet dismissViewControllerAnimated:YES completion:nil];
}
@end

static void fire(SGRPlayerMenuTakeover *t, SGRPlayerMenuSpotifyRow *row);

static UIViewController *presentedSheet(UIViewController *menu) {
    UIViewController *top = menu;
    while (top.parentViewController) top = top.parentViewController;
    return top.presentingViewController ? top : nil;
}

static UIView *sheetViewOf(UIViewController *sheet) {
    return sheet.presentationController.presentedView ?: sheet.viewIfLoaded;
}

// Spotify's dimming, cleared: the catcher draws a lighter one of its own. Its colour is kept to put back.
static void clearDimming(UIView *container, BOOL clear) {
    UIView *dimming = SGRFindByIdentifier(container, @"Components.UI.SheetPresentation.Dimming", &kDimmingKey);
    if (!dimming) return;
    UIColor *saved = objc_getAssociatedObject(dimming, &kDimmingColorKey);
    if (clear) {
        if (!saved && dimming.backgroundColor) objc_setAssociatedObject(dimming, &kDimmingColorKey, dimming.backgroundColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (![dimming.backgroundColor isEqual:UIColor.clearColor]) dimming.backgroundColor = UIColor.clearColor;
    } else if (saved) {
        dimming.backgroundColor = saved;
    }
}

// Out of sight by `hidden`, and by a mask that lets nothing through, not by alpha: the sheet's presentation
// sets its presented view's alpha back to 1 whenever the container lays out (the harness saw it after every
// change of the card's height), and iOS 26 draws a sheet's glass through a mask of no size at all, so the
// mask is a point of nothing rather than empty. Whatever mask it had is kept to put back.
static void hideSheet(SGRPlayerMenuTakeover *t, UIView *container) {
    UIView *sheet = sheetViewOf(t.sheet);
    CALayer *mask = objc_getAssociatedObject(sheet, &kMaskKey);
    if (!mask) {
        mask = [CALayer layer];
        mask.frame = CGRectMake(0, 0, 1, 1);
        mask.backgroundColor = UIColor.clearColor.CGColor;
        objc_setAssociatedObject(sheet, &kMaskKey, mask, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        t.savedMask = sheet.layer.mask;
    }
    if (sheet.layer.mask != mask) sheet.layer.mask = mask;
    if (!sheet.hidden) sheet.hidden = YES;
    if (sheet.userInteractionEnabled) sheet.userInteractionEnabled = NO;
    sheet.accessibilityElementsHidden = YES;
    clearDimming(container, YES);
}

// The card's frame: its top trailing corner at the ⋯'s, so it grows out of the button as the Music app's
// menus do, and no taller than the room under it.
static void placeCard(SGRPlayerMenuTakeover *t, UIView *container) {
    if (!t.revealed) hideSheet(t, container);
    UIView *button = t.button;
    CGRect anchor = button.window && button.window == container.window ? [button convertRect:button.bounds toView:container] : CGRectNull;
    CGFloat width = SGRPlayerMenuWidth, right, top;
    if (!CGRectIsNull(anchor)) {
        right = CGRectGetMaxX(anchor) - 2;
        top = CGRectGetMinY(anchor) + 2;
    } else {
        right = container.bounds.size.width - SGRSideMargin;
        top = container.safeAreaInsets.top + SGRGrid;
    }
    CGFloat x = MAX(SGRSideMargin, right - width);
    CGFloat bottom = container.bounds.size.height - MAX(container.safeAreaInsets.bottom, SGRSideMargin) - SGRGrid;
    t.card.maxHeight = MAX(120, bottom - top);
    CGFloat height = MIN(t.card.preferredHeight, t.card.maxHeight);
    // Bounds and centre, not the frame: the card may be mid-growth, under a transform.
    t.card.bounds = CGRectMake(0, 0, width, height);
    t.card.center = CGPointMake(x + width / 2, top + height / 2);
    t.catcher.frame = container.bounds;
}

static CGPoint anchorInCard(SGRPlayerMenuTakeover *t) {
    UIView *button = t.button;
    if (!button.window) return CGPointMake(t.card.bounds.size.width - SGRGlassCircleSize / 2, SGRGlassCircleSize / 2);
    return [button convertPoint:CGPointMake(CGRectGetMidX(button.bounds), CGRectGetMidY(button.bounds)) toView:t.card];
}

static void closeCard(SGRPlayerMenuTakeover *t) {
    if (t.closing) return;
    t.closing = YES;
    SGRPlayerMenuCard *card = t.card;
    UIControl *catcher = t.catcher;
    catcher.userInteractionEnabled = NO;
    [UIView animateWithDuration:0.22 animations:^{ catcher.alpha = 0; } completion:^(BOOL finished) { [catcher removeFromSuperview]; }];
    [card shrinkAway:^{ [card removeFromSuperview]; }];
}

// Spotify's sheet as Spotify draws it, and the card gone.
static void reveal(SGRPlayerMenuTakeover *t, NSString *why) {
    if (t.revealed || t.closing) return;
    t.revealed = YES;
    SGLog(@"redesign player menu: Spotify's sheet shown, %@", why);
    UIView *sheet = sheetViewOf(t.sheet);
    UIView *container = t.sheet.presentationController.containerView;
    sheet.userInteractionEnabled = YES;
    sheet.accessibilityElementsHidden = NO;
    clearDimming(container, NO);
    sheet.alpha = 0;
    sheet.hidden = NO;
    sheet.layer.mask = t.savedMask;
    objc_setAssociatedObject(sheet, &kMaskKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [UIView animateWithDuration:0.25 animations:^{ sheet.alpha = 1; }];
    closeCard(t);
    t.closing = NO;
}

#pragma mark building the card

static SGRPlayerMenuItem *itemFor(SGRPlayerMenuTakeover *t, SGRPlayerMenuSpotifyRow *row, const SGRPlayerMenuKnownRow *known) {
    __weak SGRPlayerMenuTakeover *weak = t;
    UIImage *image = (known ? symbol(@(known->symbol)) : nil) ?: row.image;
    SGRPlayerMenuItem *item = [SGRPlayerMenuItem itemWithTitle:row.title image:image action:^{
        SGRPlayerMenuTakeover *strong = weak;
        if (strong) fire(strong, row);
    }];
    item.subtitle = row.subtitle;
    item.disabled = row.disabled;
    item.key = row.identifier;
    item.destructive = known && known->place == SGRPlaceDestructive;
    return item;
}

static SGRPlayerMenuItem *speedAndPitchItem(void) {
    SGRPlayerMenuItem *item = [SGRPlayerMenuItem itemWithTitle:@"Speed and pitch" image:symbol(@"slider.horizontal.3") action:nil];
    item.key = @"spotifyglass.speedPitch";
    item.subtitle = SGSpeedPitchSummary();
    item.makeExpansion = ^UIView *{ return SGSpeedPitchPanelMake(); };
    item.expansionHeight = SGSpeedPitchPanelHeight();
    return item;
}

static NSArray<SGRPlayerMenuSection *> *sectionsFor(SGRPlayerMenuTakeover *t, NSArray<SGRPlayerMenuSpotifyRow *> *rows) {
    NSMutableArray<SGRPlayerMenuItem *> *tiles = [NSMutableArray array], *main = [NSMutableArray array],
                                  *feedback = [NSMutableArray array], *more = [NSMutableArray array],
                                  *destructive = [NSMutableArray array];
    for (SGRPlayerMenuSpotifyRow *row in rows) {
        const SGRPlayerMenuKnownRow *known = knownRow(row.identifier);
        SGRPlayerMenuItem *item = itemFor(t, row, known);
        switch (known ? known->place : SGRPlaceMore) {
            case SGRPlaceTile: [tiles addObject:item]; break;
            case SGRPlaceMain: [main addObject:item]; break;
            case SGRPlaceFeedback: [feedback addObject:item]; break;
            case SGRPlaceDestructive: [destructive addObject:item]; break;
            case SGRPlaceMore: [more addObject:item]; break;
        }
    }
    // Tiles in the Music app's order, Share last.
    [tiles sortUsingComparator:^NSComparisonResult(SGRPlayerMenuItem *a, SGRPlayerMenuItem *b) {
        return knownRow(a.key) < knownRow(b.key) ? NSOrderedAscending : NSOrderedDescending;
    }];
    // More than three tiles never happens with kKnown as it is; the rest would be rows.
    while (tiles.count > 3) {
        [main insertObject:tiles.lastObject atIndex:0];
        [tiles removeLastObject];
    }
    [main addObject:speedAndPitchItem()];
    if (more.count == 1) {
        [feedback addObject:more.firstObject];
    } else if (more.count) {
        SGRPlayerMenuItem *item = [SGRPlayerMenuItem itemWithTitle:@"More" image:symbol(@"ellipsis.circle") action:nil];
        item.key = @"spotifyglass.more";
        item.children = more;
        [feedback addObject:item];
    }
    return @[[SGRPlayerMenuSection sectionWithItems:tiles tiles:YES], [SGRPlayerMenuSection sectionWithItems:main tiles:NO],
             [SGRPlayerMenuSection sectionWithItems:feedback tiles:NO], [SGRPlayerMenuSection sectionWithItems:destructive tiles:NO]];
}

#pragma mark firing a row

static void fire(SGRPlayerMenuTakeover *t, SGRPlayerMenuSpotifyRow *row) {
    UITableView *table = tableIn(t.menu.viewIfLoaded, 0);
    __block BOOL fired = NO;
    if (table) {
        withEveryCell(table, ^{
            UITableViewCell *cell = [table cellForRowAtIndexPath:row.indexPath];
            UIControl *control = cell ? listRowIn(cell) : nil;
            // The rows may have moved since they were read: the number is what the row is.
            if (![control.accessibilityIdentifier isEqualToString:row.identifier]) {
                control = nil;
                for (UITableViewCell *visible in table.visibleCells) {
                    UIControl *candidate = listRowIn(visible);
                    if ([candidate.accessibilityIdentifier isEqualToString:row.identifier]) control = candidate;
                }
            }
            if (!control) return;
            SGLog(@"redesign player menu: \"%@\" (%@) fired", row.title, row.identifier);
            SGRActivate(control);
            fired = YES;
        });
    }
    if (!fired) {
        SGLog(@"redesign player menu: \"%@\" (%@) is not in the sheet any more", row.title, row.identifier);
        reveal(t, @"a row could not be fired");
    }
}

#pragma mark the pass

static void pass(SGRPlayerMenuTakeover *t) {
    if (t.revealed || t.closing) return;
    UIViewController *menu = t.menu;
    if (!t.sheet) t.sheet = presentedSheet(menu);
    UIView *container = t.sheet.presentationController.containerView;
    if (!container) return;
    hideSheet(t, container);

    if (!t.card) {
        t.catcher = [UIControl new];
        t.catcher.backgroundColor = [UIColor colorWithWhite:0 alpha:kDimming];
        t.catcher.alpha = 0;
        t.catcher.isAccessibilityElement = NO;
        [t.catcher addTarget:t action:@selector(catcherTapped) forControlEvents:UIControlEventTouchDown];
        t.card = [[SGRPlayerMenuCard alloc] initWithFrame:CGRectZero];
        __weak SGRPlayerMenuTakeover *weak = t;
        t.card.sizeChanged = ^(SGRPlayerMenuCard *card) {
            SGRPlayerMenuTakeover *strong = weak;
            UIView *host = card.superview;
            if (strong && host) placeCard(strong, host);
        };
        t.card.onEscape = ^{ [weak catcherTapped]; };
        [t.card showLoading];
    }
    if (t.catcher.superview != container) [container addSubview:t.catcher];
    if (t.card.superview != container) [container addSubview:t.card];
    if (container.subviews.lastObject != t.card) {
        [container bringSubviewToFront:t.catcher];
        [container bringSubviewToFront:t.card];
    }

    UITableView *table = tableIn(menu.viewIfLoaded, 0);
    NSArray<SGRPlayerMenuSpotifyRow *> *rows = table ? readRows(table) : @[];
    NSString *signature = signatureOf(rows);
    BOOL changed = rows.count && ![signature isEqualToString:t.signature];
    if (changed) {
        t.signature = signature;
        t.hasRows = YES;
        logNumbers(rows);
        [t.card showSections:sectionsFor(t, rows)];
    }

    if (!t.grown) {
        t.grown = YES;
        placeCard(t, container);
        [t.card layoutIfNeeded];
        [UIView animateWithDuration:0.2 animations:^{ t.catcher.alpha = 1; }];
        [t.card growFrom:anchorInCard(t)];
    } else if (changed) {
        SGRAnimate(SGRMotionLayout, ^{
            placeCard(t, container);
            [t.card layoutIfNeeded];
        }, nil);
    } else {
        placeCard(t, container);
    }
}

static SGRPlayerMenuTakeover *takeoverFor(UIViewController *menu) {
    id existing = objc_getAssociatedObject(menu, &kTakeoverKey);
    if (existing) return existing == NSNull.null ? nil : existing;
    BOOL tapped = sgr_moreTappedAt && CACurrentMediaTime() - sgr_moreTappedAt < kMenuAfterTap;
    if (!tapped) {
        objc_setAssociatedObject(menu, &kTakeoverKey, NSNull.null, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return nil;
    }
    sgr_moreTappedAt = 0;
    SGRPlayerMenuTakeover *t = [SGRPlayerMenuTakeover new];
    t.menu = menu;
    t.button = sgr_moreButton;
    objc_setAssociatedObject(menu, &kTakeoverKey, t, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    __weak SGRPlayerMenuTakeover *weak = t;
    t.speedObserver = [NSNotificationCenter.defaultCenter addObserverForName:SGSpeedPitchChangedNotification object:nil
                                                                      queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        [weak.card setSubtitle:note.userInfo[@"summary"] forKey:@"spotifyglass.speedPitch"];
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRowsWait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SGRPlayerMenuTakeover *strong = weak;
        if (strong && !strong.hasRows) reveal(strong, [NSString stringWithFormat:@"no rows of Spotify's within %.0f s", kRowsWait]);
    });
    SGLog(@"redesign player menu: the ⋯'s sheet taken over");
    return t;
}

%hook _TtC24ContextMenu_InternalImpl25ContextMenuViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    SGRPlayerMenuTakeover *t = takeoverFor((UIViewController *)self);
    if (t) pass(t);
}

- (void)viewDidLayoutSubviews {
    %orig;
    SGRPlayerMenuTakeover *t = takeoverFor((UIViewController *)self);
    if (t) pass(t);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    SGRPlayerMenuTakeover *t = objc_getAssociatedObject(self, &kTakeoverKey);
    if ([t isKindOfClass:SGRPlayerMenuTakeover.class]) pass(t);
}

// The sheet going away takes the card with it; a page of Spotify's pushed over the menu shows the sheet.
- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    SGRPlayerMenuTakeover *t = objc_getAssociatedObject(self, &kTakeoverKey);
    if (![t isKindOfClass:SGRPlayerMenuTakeover.class]) return;
    UINavigationController *navigation = ((UIViewController *)self).navigationController;
    UIViewController *sheet = t.sheet;
    BOOL leaving = !sheet.presentingViewController || sheet.isBeingDismissed || sheet.presentingViewController.isBeingDismissed;
    if (!leaving && navigation.viewControllers.count > 1) reveal(t, @"Spotify opened a page of its own on it");
    else closeCard(t);
}

%end

%ctor {
    if (!SGRedesignedUI()) return;
    sgr_menuOn = SGEnabled(SGRKeyPlayerMenu);
    if (!sgr_menuOn) return;
    %init;
    SGRequireClasses(@[@"_TtC24ContextMenu_InternalImpl25ContextMenuViewController"]);
}
