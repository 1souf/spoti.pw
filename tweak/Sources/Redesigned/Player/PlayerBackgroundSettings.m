// The player's background on the Now playing page: which of the three moves behind the player, and the
// Fluid artwork page, its sliders under a preview drawn by the same renderer as the player's field.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Player.h"

NSNotificationName const SGRPlayerFluidLookDidChangeNotification = @"spotifyglass.redesign.player.fluidLookDidChange";

static const SGRPlayerBackground kDefaultBackground = SGRPlayerBackgroundFluid;

// A slider of the page: its key, range, step and default, in the whole numbers it stores.
typedef struct {
    __unsafe_unretained NSString *key, *title;
    NSInteger minimum, maximum, step, fallback;
    BOOL percent;
} SGRFluidSlider;

static const SGRFluidSlider kSpeed = {SGRKeyFluidSpeed, @"Speed", 25, 300, 25, 100, YES};
static const SGRFluidSlider kWarp = {SGRKeyFluidWarp, @"Warp", 0, 100, 5, 100, YES};
static const SGRFluidSlider kBlur = {SGRKeyFluidBlur, @"Blur", 2, 24, 1, 8, NO};
static const SGRFluidSlider kSaturation = {SGRKeyFluidSaturation, @"Saturation", 0, 250, 10, 150, YES};
static const SGRFluidSlider kBrightness = {SGRKeyFluidBrightness, @"Brightness", 40, 150, 5, 100, YES};

static NSInteger stored(SGRFluidSlider slider) {
    return MAX(slider.minimum, MIN(slider.maximum, SGInt(slider.key, slider.fallback)));
}

// Once: a Moving background switched off is Still artwork; one left on takes the default.
static void migrate(void) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    id was = [store objectForKey:SGRKeyPlayerMotionWas];
    if (!was) return;
    if (![store objectForKey:SGRKeyPlayerBackground] && ![was boolValue]) [store setInteger:SGRPlayerBackgroundStill forKey:SGRKeyPlayerBackground];
    [store removeObjectForKey:SGRKeyPlayerMotionWas];
}

// A reset to stock leaves the player's background still, as it left the switch off.
static NSInteger fallbackBackground(void) {
    return [NSUserDefaults.standardUserDefaults boolForKey:SGKeyStock] ? SGRPlayerBackgroundStill : kDefaultBackground;
}

SGRPlayerBackground SGRPlayerBackgroundStyle(void) {
    migrate();
    NSInteger style = SGInt(SGRKeyPlayerBackground, fallbackBackground());
    return style >= SGRPlayerBackgroundStill && style <= SGRPlayerBackgroundFluid ? (SGRPlayerBackground)style : kDefaultBackground;
}

SGRWarpLook SGRPlayerFluidLook(void) {
    return (SGRWarpLook){
        .speed = stored(kSpeed) / 100.0f,
        .warp = stored(kWarp) / 100.0f,
        .blur = stored(kBlur),
        .saturation = stored(kSaturation) / 100.0f,
        .brightness = stored(kBrightness) / 100.0f,
    };
}

static void lookChanged(void) {
    [NSNotificationCenter.defaultCenter postNotificationName:SGRPlayerFluidLookDidChangeNotification object:nil];
}

#pragma mark - the Fluid artwork page

static const CGFloat kPreviewHeight = 240, kPreviewTop = 16, kPreviewBottom = 8, kPreviewRadius = 26;

// The page with the preview over its rows. The preview is a band across the middle of the player at the
// player's own scale, so the blur and the warp look the size they will there.
@interface SGRFluidPage : SGModPage
@end

@implementation SGRFluidPage {
    UIView *_header;
    SGRWarpView *_preview;
    CGSize _laidOutFor;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _header = [UIView new];
    _preview = [SGRWarpView new];
    _preview.layer.cornerRadius = kPreviewRadius;
    _preview.layer.cornerCurve = kCACornerCurveContinuous;
    _preview.layer.masksToBounds = YES;
    [_header addSubview:_preview];
    self.tableView.tableHeaderView = _header;
    _preview.warpLayer.look = SGRPlayerFluidLook();
    [self showArtwork];
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(showLook) name:SGRPlayerFluidLookDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(showArtwork) name:SGRNowPlayingArtworkDidChangeNotification object:nil];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    UITableView *table = self.tableView;
    CGFloat inset = table.layoutMargins.left, width = table.bounds.size.width;
    CGSize size = CGSizeMake(width, kPreviewTop + kPreviewHeight + kPreviewBottom);
    if (CGSizeEqualToSize(size, _laidOutFor) || width < 1) return;
    _laidOutFor = size;
    _header.frame = (CGRect){CGPointZero, size};
    CGRect card = CGRectMake(inset, kPreviewTop, width - 2 * inset, kPreviewHeight);
    _preview.frame = card;
    CGSize screen = table.window.bounds.size.width > 0 ? table.window.bounds.size : UIScreen.mainScreen.bounds.size;
    CGFloat pictureHeight = card.size.width * screen.height / MAX(1, screen.width);
    _preview.warpLayer.pictureFrame = CGRectMake(0, (card.size.height - pictureHeight) / 2, card.size.width, pictureHeight);
    table.tableHeaderView = _header;
}

- (void)showLook {
    _preview.warpLayer.look = SGRPlayerFluidLook();
}

- (void)showArtwork {
    UIImage *artwork = SGRNowPlayingArtwork(NULL, NULL);
    [_preview.warpLayer setArtwork:artwork ?: SGRWarpSampleArtwork() animated:_preview.window != nil];
}

// Reset puts every slider back, and the rows read them again.
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [super tableView:table didSelectRowAtIndexPath:path];
    [table reloadData];
}

@end

static SGModRow *sliderRow(SGRFluidSlider slider) {
    return SGSliderRow(slider.title, nil, slider.minimum, slider.maximum, slider.step,
        ^double { return stored(slider); },
        ^(double value) {
            SGSetInt(slider.key, lround(value));
            lookChanged();
        },
        ^NSString *(double value) {
            return slider.percent ? [NSString stringWithFormat:@"%ld%%", lround(value)] : [NSString stringWithFormat:@"%ld", lround(value)];
        });
}

static UIViewController *fluidPage(void) {
    SGModRow *reset = SGActionRow(@"Reset", nil, ^{
        for (NSString *key in @[SGRKeyFluidSpeed, SGRKeyFluidWarp, SGRKeyFluidBlur, SGRKeyFluidSaturation, SGRKeyFluidBrightness]) {
            [NSUserDefaults.standardUserDefaults removeObjectForKey:key];
        }
        lookChanged();
    });
    reset.color = SGRed();
    reset.symbol = @"arrow.counterclockwise";
    return [[SGRFluidPage alloc] initWithTitle:@"Fluid artwork" intro:nil sections:@[
        SGNotedSection(nil, @[sliderRow(kSpeed), sliderRow(kWarp), sliderRow(kBlur), sliderRow(kSaturation), sliderRow(kBrightness)],
                       @"The player follows these as they move. Brightness past 100% can make white text harder to read on a light cover."),
        SGSection(nil, @[reset]),
    ] footer:nil];
}

NSArray<SGModRow *> *SGRPlayerBackgroundRows(void) {
    migrate();
    SGModRow *style = SGChoiceRow(@"Background", nil, SGRKeyPlayerBackground, @[@"Still artwork", @"Colour flow", @"Fluid artwork"], fallbackBackground());
    style.choiceNotes = @[@"The cover, blurred and held still", @"Soft patches of the cover's colours drifting",
                          @"The cover itself, blurred and slowly warped"];
    style.choiceFooter = @"A paused song holds the background still.";
    SGModRow *fluid = SGPageRow(@"Fluid artwork", ^UIViewController *{ return fluidPage(); });
    fluid.visible = ^BOOL { return SGRPlayerBackgroundStyle() == SGRPlayerBackgroundFluid; };
    return @[style, fluid];
}
