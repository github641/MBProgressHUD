//
// MBProgressHUD.m
// Version 1.0.0
// Created by Matej Bukovinski on 2.4.09.
//

#import "MBProgressHUD.h"
#import <tgmath.h>

/* lzy注170819：补充、提取重点
 定义的Foundation API的版本号。
 用于API兼容。
 */
#ifndef kCFCoreFoundationVersionNumber_iOS_7_0
#define kCFCoreFoundationVersionNumber_iOS_7_0 847.20
#endif

#ifndef kCFCoreFoundationVersionNumber_iOS_8_0
#define kCFCoreFoundationVersionNumber_iOS_8_0 1129.15
#endif

#define MBMainThreadAssert() NSAssert([NSThread isMainThread], @"MBProgressHUD needs to be accessed on the main thread.");

/* lzy注170819：补充、提取重点
 在.h中，是这样写的：
 extern CGFloat const MBProgressMaxOffset;
 */
CGFloat const MBProgressMaxOffset = 1000000.f;

static const CGFloat MBDefaultPadding = 4.f;
static const CGFloat MBDefaultLabelFontSize = 16.f;
static const CGFloat MBDefaultDetailsLabelFontSize = 12.f;

/* lzy注170819：补充、提取重点
 类扩展。一些.m内部使用的变量。
 以及一些需要把.h中的属性的所有权修饰符进行重写，会需要在这里面写。
 比如外部是readOnly，内部重写为readWrite。
 */
@interface MBProgressHUD () {
    // Deprecated
    UIColor *_activityIndicatorColor;
    CGFloat _opacity;
}

@property (nonatomic, assign) BOOL useAnimation;
@property (nonatomic, assign, getter=hasFinished) BOOL finished;
@property (nonatomic, strong) UIView *indicator;
@property (nonatomic, strong) NSDate *showStarted;
@property (nonatomic, strong) NSArray *paddingConstraints;
@property (nonatomic, strong) NSArray *bezelConstraints;
@property (nonatomic, strong) UIView *topSpacer;
@property (nonatomic, strong) UIView *bottomSpacer;
@property (nonatomic, weak) NSTimer *graceTimer;
@property (nonatomic, weak) NSTimer *minShowTimer;
@property (nonatomic, weak) NSTimer *hideDelayTimer;
@property (nonatomic, weak) CADisplayLink *progressObjectDisplayLink;

// Deprecated
@property (assign) BOOL taskInProgress;

@end


@interface MBProgressHUDRoundedButton : UIButton
@end


@implementation MBProgressHUD

#pragma mark - Class methods

+ (instancetype)showHUDAddedTo:(UIView *)view animated:(BOOL)animated {
    MBProgressHUD *hud = [[self alloc] initWithView:view];
    hud.removeFromSuperViewOnHide = YES;
    [view addSubview:hud];
    [hud showAnimated:animated];
    return hud;
}

+ (BOOL)hideHUDForView:(UIView *)view animated:(BOOL)animated {
    MBProgressHUD *hud = [self HUDForView:view];
    if (hud != nil) {
        hud.removeFromSuperViewOnHide = YES;
        [hud hideAnimated:animated];
        return YES;
    }
    return NO;
}

+ (MBProgressHUD *)HUDForView:(UIView *)view {
    /* lzy注170819：补充、提取重点
     Returns an enumerator object that lets you access each object in the array, in reverse order（逆序）.
     When you use this method with mutable subclasses of NSArray, you must not modify the array during enumeration.
     It is more efficient to use the fast enumeration protocol (see NSFastEnumeration). Fast enumeration is available in macOS 10.5 and later and iOS 2.0 and later.
     Returns
     An enumerator object that lets you access each object in the array, in order, from the element at the highest index down to the element at index 0.（访问数组迭代器中的元素，内部元素使用从高到低排的）
     Availability	iOS (2.0 and later), macOS (10.0 and later), tvOS (9.0 and later), watchOS (2.0 and later)
     */
    NSEnumerator *subviewsEnum = [view.subviews reverseObjectEnumerator];
    for (UIView *subview in subviewsEnum) {
        if ([subview isKindOfClass:self]) {
            MBProgressHUD *hud = (MBProgressHUD *)subview;
            if (hud.hasFinished == NO) {
                return hud;
            }
        }
    }
    return nil;
}

#pragma mark - Lifecycle

- (void)commonInit {
    // Set default values for properties
    _animationType = MBProgressHUDAnimationFade;
    _mode = MBProgressHUDModeIndeterminate;
    _margin = 20.0f;
    _opacity = 1.f;
    _defaultMotionEffectsEnabled = YES;
    
    // Default color, depending on the current iOS version
    BOOL isLegacy = kCFCoreFoundationVersionNumber < kCFCoreFoundationVersionNumber_iOS_7_0;
    _contentColor = isLegacy ? [UIColor whiteColor] : [UIColor colorWithWhite:0.f alpha:0.7f];
    // Transparent background
    self.opaque = NO;
    self.backgroundColor = [UIColor clearColor];
    // Make it invisible for now
    self.alpha = 0.0f;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.layer.allowsGroupOpacity = NO;
    
    /* lzy注170819：补充、提取重点
     */
    [self setupViews];
    [self updateIndicators];
    // 监听屏幕（状态栏）方向
    [self registerForNotifications];
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    if ((self = [super initWithCoder:aDecoder])) {
        [self commonInit];
    }
    return self;
}

- (id)initWithView:(UIView *)view {
    NSAssert(view, @"View must not be nil.");
    return [self initWithFrame:view.bounds];
}

- (void)dealloc {
    [self unregisterFromNotifications];
}

#pragma mark - Show & hide

- (void)showAnimated:(BOOL)animated {
    /* lzy注170819：补充、提取重点
     这是.m的 Assert宏定义的使用。本类是UI视图类，所以操作本类，务必在主线程。
     */
    MBMainThreadAssert();
    [self.minShowTimer invalidate];
    self.useAnimation = animated;
    self.finished = NO;
    // If the grace time is set, postpone（延期、延迟） the HUD display
    if (self.graceTime > 0.0) {
        NSTimer *timer = [NSTimer timerWithTimeInterval:self.graceTime target:self selector:@selector(handleGraceTimer:) userInfo:nil repeats:NO];
        [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];// mode是runLoop模式集合。
        self.graceTimer = timer;
    }
    // ... otherwise show the HUD immediately
    else {
        [self showUsingAnimation:self.useAnimation];
    }
}

- (void)hideAnimated:(BOOL)animated {
    MBMainThreadAssert();
    [self.graceTimer invalidate];
    self.useAnimation = animated;
    self.finished = YES;
    // If the minShow time is set, calculate how long the HUD was shown,
    // and postpone（延期、延迟） the hiding operation if necessary
    if (self.minShowTime > 0.0 && self.showStarted) {
        NSTimeInterval interv = [[NSDate date] timeIntervalSinceDate:self.showStarted];
        if (interv < self.minShowTime) {// HUD继续展示 差值 秒
            NSTimer *timer = [NSTimer timerWithTimeInterval:(self.minShowTime - interv) target:self selector:@selector(handleMinShowTimer:) userInfo:nil repeats:NO];
            [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
            self.minShowTimer = timer;
            return;
        }
    }
    // ... otherwise hide the HUD immediately
    [self hideUsingAnimation:self.useAnimation];
}

- (void)hideAnimated:(BOOL)animated afterDelay:(NSTimeInterval)delay {
    NSTimer *timer = [NSTimer timerWithTimeInterval:delay target:self selector:@selector(handleHideTimer:) userInfo:@(animated) repeats:NO];
    [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    self.hideDelayTimer = timer;
}

#pragma mark - Timer callbacks

- (void)handleGraceTimer:(NSTimer *)theTimer {
    // Show the HUD only if the task is still running
    if (!self.hasFinished) {
        [self showUsingAnimation:self.useAnimation];
    }
}

- (void)handleMinShowTimer:(NSTimer *)theTimer {
    [self hideUsingAnimation:self.useAnimation];
}

- (void)handleHideTimer:(NSTimer *)timer {
    [self hideAnimated:[timer.userInfo boolValue]];
}

#pragma mark - View Hierrarchy

- (void)didMoveToSuperview {
    [self updateForCurrentOrientationAnimated:NO];
}

#pragma mark - Internal show & hide operations

/* lzy注170819：补充、提取重点
 1、移除之前添加到相关layer的动画
 2、使得定时器失效，来取消本实例任何handleHideTimer计划中的hideAnimated:方法
 3、记录展示开始时间、HUD的alpha置为1，则HUD出现，之前初始化的时候是0
 4、HUD有可能是『确定进度的类型』，处理CADisplayLink
 5、根据是否做动画出现的标识，处理动画出现相关事宜
 */
- (void)showUsingAnimation:(BOOL)animated {
    // Cancel any previous animations
    /* lzy注170819：补充、提取重点
     Remove all animations attached to the layer.
     Availability	iOS (2.0 and later), macOS (10.5 and later), tvOS (9.0 and later)
     */
    [self.bezelView.layer removeAllAnimations];
    [self.backgroundView.layer removeAllAnimations];
    
    // Cancel any scheduled hideDelayed: calls
    [self.hideDelayTimer invalidate];
    
    /* lzy注170819：补充、提取重点
     
     用在-hideAnimated:方法中，计算该方法调用时与showStarted的差值，如果设置了『最短展示时间』，那么即使没达到最短时间就结束了还是会展示完，如果超过最短展示时间结束的，那么任务结束就结束了，直接hide就好了
     */
    self.showStarted = [NSDate date];
    self.alpha = 1.f;
    
    // Needed in case we hide and re-show with the same NSProgress object attached.
    [self setNSProgressDisplayLinkEnabled:YES];
    
    if (animated) {
        [self animateIn:YES withType:self.animationType completion:NULL];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        self.bezelView.alpha = self.opacity;
#pragma clang diagnostic pop
        self.backgroundView.alpha = 1.f;
    }
}

- (void)hideUsingAnimation:(BOOL)animated {
    if (animated && self.showStarted) {
        self.showStarted = nil;
        [self animateIn:NO withType:self.animationType completion:^(BOOL finished) {
            [self done];
        }];
    } else {
        self.showStarted = nil;
        self.bezelView.alpha = 0.f;
        self.backgroundView.alpha = 1.f;
        [self done];
    }
}

/* lzy注170819：补充、提取重点
 1、HUD做动画出现，需要调用此方法,animatingIn传入YES
 2、HUD隐藏，调用此方法-hideUsingAnimation:。animatingIn传入的NO
 */
- (void)animateIn:(BOOL)animatingIn withType:(MBProgressHUDAnimation)type completion:(void(^)(BOOL finished))completion {
    // Automatically determine the correct zoom animation type
    if (type == MBProgressHUDAnimationZoom) {
        type = animatingIn ? MBProgressHUDAnimationZoomIn : MBProgressHUDAnimationZoomOut;
    }
    
    CGAffineTransform small = CGAffineTransformMakeScale(0.5f, 0.5f);
    CGAffineTransform large = CGAffineTransformMakeScale(1.5f, 1.5f);
    
    // Set starting state
    UIView *bezelView = self.bezelView;
    if (animatingIn && bezelView.alpha == 0.f && type == MBProgressHUDAnimationZoomIn) {
        bezelView.transform = small;
    } else if (animatingIn && bezelView.alpha == 0.f && type == MBProgressHUDAnimationZoomOut) {
        bezelView.transform = large;
    }
    
    // Perform animations
    dispatch_block_t animations = ^{
        if (animatingIn) {
            bezelView.transform = CGAffineTransformIdentity;
        } else if (!animatingIn && type == MBProgressHUDAnimationZoomIn) {
            bezelView.transform = large;
        } else if (!animatingIn && type == MBProgressHUDAnimationZoomOut) {
            bezelView.transform = small;
        }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        bezelView.alpha = animatingIn ? self.opacity : 0.f;
#pragma clang diagnostic pop
        self.backgroundView.alpha = animatingIn ? 1.f : 0.f;
    };
    
    // Spring animations are nicer, but only available on iOS 7+
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 70000 || TARGET_OS_TV
    if (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_7_0) {
        [UIView animateWithDuration:0.3 delay:0. usingSpringWithDamping:1.f initialSpringVelocity:0.f options:UIViewAnimationOptionBeginFromCurrentState animations:animations completion:completion];
        return;
    }
#endif
    [UIView animateWithDuration:0.3 delay:0. options:UIViewAnimationOptionBeginFromCurrentState animations:animations completion:completion];
}
/* lzy注170819：补充、提取重点
 -hideUsingAnimation:调用的最后，无论是否做动画隐藏
 都将调用此方法。
 
 1、使得相关timer和displayLink失效
 2、确认结束，且结束配置中，要求HUD隐藏后移除的，做相关处理
 3、回调处理
 */
- (void)done {
    // Cancel any scheduled hideDelayed: calls
    [self.hideDelayTimer invalidate];
    [self setNSProgressDisplayLinkEnabled:NO];
    
    if (self.hasFinished) {
        self.alpha = 0.0f;
        if (self.removeFromSuperViewOnHide) {
            [self removeFromSuperview];
        }
    }
    MBProgressHUDCompletionBlock completionBlock = self.completionBlock;
    if (completionBlock) {
        completionBlock();
    }
    id<MBProgressHUDDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(hudWasHidden:)]) {
        [delegate performSelector:@selector(hudWasHidden:) withObject:self];
    }
}

#pragma mark - UI

- (void)setupViews {
    UIColor *defaultColor = self.contentColor;
    
    MBBackgroundView *backgroundView = [[MBBackgroundView alloc] initWithFrame:self.bounds];
    backgroundView.style = MBProgressHUDBackgroundStyleSolidColor;
    backgroundView.backgroundColor = [UIColor clearColor];
    backgroundView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    backgroundView.alpha = 0.f;
    [self addSubview:backgroundView];
    _backgroundView = backgroundView;
    
    MBBackgroundView *bezelView = [MBBackgroundView new];
    bezelView.translatesAutoresizingMaskIntoConstraints = NO;
    bezelView.layer.cornerRadius = 5.f;
    bezelView.alpha = 0.f;
    [self addSubview:bezelView];
    _bezelView = bezelView;
    [self updateBezelMotionEffects];
    /* lzy注170819：补充、提取重点
     以上两层view都是加到self了。
     */
    
    UILabel *label = [UILabel new];
    label.adjustsFontSizeToFitWidth = NO;
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = defaultColor;
    label.font = [UIFont boldSystemFontOfSize:MBDefaultLabelFontSize];
    label.opaque = NO;
    label.backgroundColor = [UIColor clearColor];
    _label = label;
    
    UILabel *detailsLabel = [UILabel new];
    detailsLabel.adjustsFontSizeToFitWidth = NO;
    detailsLabel.textAlignment = NSTextAlignmentCenter;
    detailsLabel.textColor = defaultColor;
    detailsLabel.numberOfLines = 0;
    detailsLabel.font = [UIFont boldSystemFontOfSize:MBDefaultDetailsLabelFontSize];
    detailsLabel.opaque = NO;
    detailsLabel.backgroundColor = [UIColor clearColor];
    _detailsLabel = detailsLabel;
    
    UIButton *button = [MBProgressHUDRoundedButton buttonWithType:UIButtonTypeCustom];
    button.titleLabel.textAlignment = NSTextAlignmentCenter;
    button.titleLabel.font = [UIFont boldSystemFontOfSize:MBDefaultDetailsLabelFontSize];
    [button setTitleColor:defaultColor forState:UIControlStateNormal];
    _button = button;
    //     下面的视图没有加。
    for (UIView *view in @[label, detailsLabel, button]) {
        /* lzy注170819：补充、提取重点
         A Boolean value that determines whether the view’s autoresizing mask is translated into Auto Layout constraints.
         If this property’s value is YES, the system creates a set of constraints that duplicate the behavior specified by the view’s autoresizing mask. This also lets you modify the view’s size and location using the view’s frame, bounds, or center properties, allowing you to create a static, frame-based layout within Auto Layout.
         Note that the autoresizing mask constraints fully specify the view’s size and position; therefore, you cannot add additional constraints to modify this size or position without introducing conflicts. If you want to use Auto Layout to dynamically calculate the size and position of your view, you must set this property to NO, and then provide a non ambiguous, nonconflicting set of constraints for the view.
         By default, the property is set to YES for any view you programmatically create. If you add views in Interface Builder, the system automatically sets this property to NO.
         Availability	iOS (6.0 and later), tvOS (6.0 and later)
         为了使用AutoLayout，设置为NO
         */
        view.translatesAutoresizingMaskIntoConstraints = NO;
        
        /* lzy注170819：补充、提取重点
         Sets the priority with which a view resists being made smaller than its intrinsic size.
         Custom views should set default values for both orientations on creation, based on their content, typically to UILayoutPriorityDefaultLow or UILayoutPriorityDefaultHigh. When creating user interfaces, the layout designer can modify these priorities for specific views when the overall layout design requires different tradeoffs than the natural priorities of the views being used in the interface.
         Subclasses should not override this method.
         Parameters
         priority
         The new priority.
         axis
         The axis for which the compression resistance priority should be set.
         Availability	iOS (6.0 and later), tvOS (6.0 and later)
         
         typedef float UILayoutPriority;
         static const UILayoutPriority UILayoutPriorityRequired NS_AVAILABLE_IOS(6_0) = 1000; // A required constraint.  Do not exceed this.
         static const UILayoutPriority UILayoutPriorityDefaultHigh NS_AVAILABLE_IOS(6_0) = 750; // This is the priority level with which a button resists compressing its content.
         static const UILayoutPriority UILayoutPriorityDefaultLow NS_AVAILABLE_IOS(6_0) = 250; // This is the priority level at which a button hugs its contents horizontally.
         static const UILayoutPriority UILayoutPriorityFittingSizeLevel NS_AVAILABLE_IOS(6_0) = 50; // When you send -[UIView systemLayoutSizeFittingSize:], the size fitting most closely to the target size (the argument) is computed.  UILayoutPriorityFittingSizeLevel is the priority level with which the view wants to conform to the target size in that computation.  It's quite low.  It is generally not appropriate to make a constraint at exactly this priority.  You want to be higher or lower.
         
         */
        [view setContentCompressionResistancePriority:998.f forAxis:UILayoutConstraintAxisHorizontal];
        [view setContentCompressionResistancePriority:998.f forAxis:UILayoutConstraintAxisVertical];
        [bezelView addSubview:view];
    }
    
    // 上下间距view
    
    UIView *topSpacer = [UIView new];
    topSpacer.translatesAutoresizingMaskIntoConstraints = NO;
    topSpacer.hidden = YES;
    [bezelView addSubview:topSpacer];
    _topSpacer = topSpacer;
    
    UIView *bottomSpacer = [UIView new];
    bottomSpacer.translatesAutoresizingMaskIntoConstraints = NO;
    bottomSpacer.hidden = YES;
    [bezelView addSubview:bottomSpacer];
    _bottomSpacer = bottomSpacer;
}

- (void)updateIndicators {
    /* lzy注170821
     让mode 与 view的类型对应。
     并配置view的样式。
     */
    UIView *indicator = self.indicator;
    BOOL isActivityIndicator = [indicator isKindOfClass:[UIActivityIndicatorView class]];
    BOOL isRoundIndicator = [indicator isKindOfClass:[MBRoundProgressView class]];
    
    MBProgressHUDMode mode = self.mode;
    if (mode == MBProgressHUDModeIndeterminate) {
        if (!isActivityIndicator) {
            /* lzy注170819：补充、提取重点
             目前模式是 MBProgressHUDModeIndeterminate，但是UIView *indicator不是UIActivityIndicatorView的处理。
             */
            
            // Update to indeterminate indicator
            [indicator removeFromSuperview];
            indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
            [(UIActivityIndicatorView *)indicator startAnimating];
            [self.bezelView addSubview:indicator];
        }
    }
    else if (mode == MBProgressHUDModeDeterminateHorizontalBar) {
        // Update to bar determinate indicator
        [indicator removeFromSuperview];
        indicator = [[MBBarProgressView alloc] init];
        [self.bezelView addSubview:indicator];
    }
    else if (mode == MBProgressHUDModeDeterminate || mode == MBProgressHUDModeAnnularDeterminate) {
        if (!isRoundIndicator) {// 决定视图是哪个
            // Update to determinante indicator
            [indicator removeFromSuperview];
            indicator = [[MBRoundProgressView alloc] init];
            [self.bezelView addSubview:indicator];
        }
        if (mode == MBProgressHUDModeAnnularDeterminate) {// 决定视图的样式
            [(MBRoundProgressView *)indicator setAnnular:YES];
        }
    }
    else if (mode == MBProgressHUDModeCustomView && self.customView != indicator) {
        // Update custom view indicator
        [indicator removeFromSuperview];
        indicator = self.customView;
        [self.bezelView addSubview:indicator];
    }
    else if (mode == MBProgressHUDModeText) {
        [indicator removeFromSuperview];
        indicator = nil;
    }
    
    // 需要使用AutoLayout
    indicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.indicator = indicator;
    
    if ([indicator respondsToSelector:@selector(setProgress:)]) {
        [(id)indicator setValue:@(self.progress) forKey:@"progress"];
    }
    
    [indicator setContentCompressionResistancePriority:998.f forAxis:UILayoutConstraintAxisHorizontal];
    [indicator setContentCompressionResistancePriority:998.f forAxis:UILayoutConstraintAxisVertical];
    // 确定了视图后，确定视图的样式
    [self updateViewsForColor:self.contentColor];
    [self setNeedsUpdateConstraints];
}

- (void)updateViewsForColor:(UIColor *)color {
    if (!color) return;
    
    self.label.textColor = color;
    self.detailsLabel.textColor = color;
    [self.button setTitleColor:color forState:UIControlStateNormal];
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (self.activityIndicatorColor) {
        color = self.activityIndicatorColor;
    }
#pragma clang diagnostic pop
    
    // UIAppearance settings are prioritized. If they are preset the set color is ignored.
    
    UIView *indicator = self.indicator;
    if ([indicator isKindOfClass:[UIActivityIndicatorView class]]) {
        UIActivityIndicatorView *appearance = nil;
#if __IPHONE_OS_VERSION_MIN_REQUIRED < 90000
        appearance = [UIActivityIndicatorView appearanceWhenContainedIn:[MBProgressHUD class], nil];
#else
        // For iOS 9+
        appearance = [UIActivityIndicatorView appearanceWhenContainedInInstancesOfClasses:@[[MBProgressHUD class]]];
#endif
        
        if (appearance.color == nil) {
            ((UIActivityIndicatorView *)indicator).color = color;
        }
    } else if ([indicator isKindOfClass:[MBRoundProgressView class]]) {
        MBRoundProgressView *appearance = nil;
#if __IPHONE_OS_VERSION_MIN_REQUIRED < 90000
        appearance = [MBRoundProgressView appearanceWhenContainedIn:[MBProgressHUD class], nil];
#else
        appearance = [MBRoundProgressView appearanceWhenContainedInInstancesOfClasses:@[[MBProgressHUD class]]];
#endif
        if (appearance.progressTintColor == nil) {
            ((MBRoundProgressView *)indicator).progressTintColor = color;
        }
        if (appearance.backgroundTintColor == nil) {
            ((MBRoundProgressView *)indicator).backgroundTintColor = [color colorWithAlphaComponent:0.1];
        }
    } else if ([indicator isKindOfClass:[MBBarProgressView class]]) {
        MBBarProgressView *appearance = nil;
#if __IPHONE_OS_VERSION_MIN_REQUIRED < 90000
        appearance = [MBBarProgressView appearanceWhenContainedIn:[MBProgressHUD class], nil];
#else
        appearance = [MBBarProgressView appearanceWhenContainedInInstancesOfClasses:@[[MBProgressHUD class]]];
#endif
        if (appearance.progressColor == nil) {
            ((MBBarProgressView *)indicator).progressColor = color;
        }
        if (appearance.lineColor == nil) {
            ((MBBarProgressView *)indicator).lineColor = color;
        }
    } else {
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 70000 || TARGET_OS_TV
        if ([indicator respondsToSelector:@selector(setTintColor:)]) {
            [indicator setTintColor:color];
        }
#endif
    }
}

- (void)updateBezelMotionEffects {
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 70000 || TARGET_OS_TV
    MBBackgroundView *bezelView = self.bezelView;
    if (![bezelView respondsToSelector:@selector(addMotionEffect:)]) return;
    
    if (self.defaultMotionEffectsEnabled) {
        CGFloat effectOffset = 10.f;
        UIInterpolatingMotionEffect *effectX = [[UIInterpolatingMotionEffect alloc] initWithKeyPath:@"center.x" type:UIInterpolatingMotionEffectTypeTiltAlongHorizontalAxis];
        effectX.maximumRelativeValue = @(effectOffset);
        effectX.minimumRelativeValue = @(-effectOffset);
        
        UIInterpolatingMotionEffect *effectY = [[UIInterpolatingMotionEffect alloc] initWithKeyPath:@"center.y" type:UIInterpolatingMotionEffectTypeTiltAlongVerticalAxis];
        effectY.maximumRelativeValue = @(effectOffset);
        effectY.minimumRelativeValue = @(-effectOffset);
        
        UIMotionEffectGroup *group = [[UIMotionEffectGroup alloc] init];
        group.motionEffects = @[effectX, effectY];
        
        [bezelView addMotionEffect:group];
    } else {
        NSArray *effects = [bezelView motionEffects];
        for (UIMotionEffect *effect in effects) {
            [bezelView removeMotionEffect:effect];
        }
    }
#endif
}

#pragma mark - Layout

- (void)updateConstraints {
    UIView *bezel = self.bezelView;
    UIView *topSpacer = self.topSpacer;
    UIView *bottomSpacer = self.bottomSpacer;
    CGFloat margin = self.margin;
    NSMutableArray *bezelConstraints = [NSMutableArray array];
    NSDictionary *metrics = @{@"margin": @(margin)};
    
    NSMutableArray *subviews = [NSMutableArray arrayWithObjects:self.topSpacer, self.label, self.detailsLabel, self.button, self.bottomSpacer, nil];
    if (self.indicator) [subviews insertObject:self.indicator atIndex:1];
    
    // Remove existing constraints
    [self removeConstraints:self.constraints];
    [topSpacer removeConstraints:topSpacer.constraints];
    [bottomSpacer removeConstraints:bottomSpacer.constraints];
    if (self.bezelConstraints) {
        [bezel removeConstraints:self.bezelConstraints];
        self.bezelConstraints = nil;
    }
    
    // Center bezel in container (self), applying the offset if set
    CGPoint offset = self.offset;
    NSMutableArray *centeringConstraints = [NSMutableArray array];
    [centeringConstraints addObject:[NSLayoutConstraint constraintWithItem:bezel attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeCenterX multiplier:1.f constant:offset.x]];
    [centeringConstraints addObject:[NSLayoutConstraint constraintWithItem:bezel attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeCenterY multiplier:1.f constant:offset.y]];
    [self applyPriority:998.f toConstraints:centeringConstraints];
    [self addConstraints:centeringConstraints];
    
    // Ensure minimum side margin is kept
    NSMutableArray *sideConstraints = [NSMutableArray array];
    [sideConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"|-(>=margin)-[bezel]-(>=margin)-|" options:0 metrics:metrics views:NSDictionaryOfVariableBindings(bezel)]];
    [sideConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-(>=margin)-[bezel]-(>=margin)-|" options:0 metrics:metrics views:NSDictionaryOfVariableBindings(bezel)]];
    [self applyPriority:999.f toConstraints:sideConstraints];
    [self addConstraints:sideConstraints];
    
    // Minimum bezel size, if set
    CGSize minimumSize = self.minSize;
    if (!CGSizeEqualToSize(minimumSize, CGSizeZero)) {
        NSMutableArray *minSizeConstraints = [NSMutableArray array];
        [minSizeConstraints addObject:[NSLayoutConstraint constraintWithItem:bezel attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationGreaterThanOrEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1.f constant:minimumSize.width]];
        [minSizeConstraints addObject:[NSLayoutConstraint constraintWithItem:bezel attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationGreaterThanOrEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1.f constant:minimumSize.height]];
        [self applyPriority:997.f toConstraints:minSizeConstraints];
        [bezelConstraints addObjectsFromArray:minSizeConstraints];
    }
    
    // Square aspect ratio, if set
    if (self.square) {
        NSLayoutConstraint *square = [NSLayoutConstraint constraintWithItem:bezel attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:bezel attribute:NSLayoutAttributeWidth multiplier:1.f constant:0];
        square.priority = 997.f;
        [bezelConstraints addObject:square];
    }
    
    // Top and bottom spacing
    [topSpacer addConstraint:[NSLayoutConstraint constraintWithItem:topSpacer attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationGreaterThanOrEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1.f constant:margin]];
    [bottomSpacer addConstraint:[NSLayoutConstraint constraintWithItem:bottomSpacer attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationGreaterThanOrEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1.f constant:margin]];
    // Top and bottom spaces should be equal
    [bezelConstraints addObject:[NSLayoutConstraint constraintWithItem:topSpacer attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:bottomSpacer attribute:NSLayoutAttributeHeight multiplier:1.f constant:0.f]];
    
    // Layout subviews in bezel
    NSMutableArray *paddingConstraints = [NSMutableArray new];
    [subviews enumerateObjectsUsingBlock:^(UIView *view, NSUInteger idx, BOOL *stop) {
        // Center in bezel
        [bezelConstraints addObject:[NSLayoutConstraint constraintWithItem:view attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:bezel attribute:NSLayoutAttributeCenterX multiplier:1.f constant:0.f]];
        // Ensure the minimum edge margin is kept
        [bezelConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"|-(>=margin)-[view]-(>=margin)-|" options:0 metrics:metrics views:NSDictionaryOfVariableBindings(view)]];
        // Element spacing
        if (idx == 0) {
            // First, ensure spacing to bezel edge
            [bezelConstraints addObject:[NSLayoutConstraint constraintWithItem:view attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:bezel attribute:NSLayoutAttributeTop multiplier:1.f constant:0.f]];
        } else if (idx == subviews.count - 1) {
            // Last, ensure spacing to bezel edge
            [bezelConstraints addObject:[NSLayoutConstraint constraintWithItem:view attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:bezel attribute:NSLayoutAttributeBottom multiplier:1.f constant:0.f]];
        }
        if (idx > 0) {
            // Has previous
            NSLayoutConstraint *padding = [NSLayoutConstraint constraintWithItem:view attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:subviews[idx - 1] attribute:NSLayoutAttributeBottom multiplier:1.f constant:0.f];
            [bezelConstraints addObject:padding];
            [paddingConstraints addObject:padding];
        }
    }];
    
    [bezel addConstraints:bezelConstraints];
    self.bezelConstraints = bezelConstraints;
    
    self.paddingConstraints = [paddingConstraints copy];
    [self updatePaddingConstraints];
    
    [super updateConstraints];
}

- (void)layoutSubviews {
    // There is no need to update constraints if they are going to
    // be recreated in [super layoutSubviews] due to needsUpdateConstraints being set.
    // This also avoids an issue on iOS 8, where updatePaddingConstraints
    // would trigger a zombie object access.
    if (!self.needsUpdateConstraints) {
        [self updatePaddingConstraints];
    }
    [super layoutSubviews];
}

- (void)updatePaddingConstraints {
    // Set padding dynamically, depending on whether the view is visible or not
    __block BOOL hasVisibleAncestors = NO;
    [self.paddingConstraints enumerateObjectsUsingBlock:^(NSLayoutConstraint *padding, NSUInteger idx, BOOL *stop) {
        UIView *firstView = (UIView *)padding.firstItem;
        UIView *secondView = (UIView *)padding.secondItem;
        BOOL firstVisible = !firstView.hidden && !CGSizeEqualToSize(firstView.intrinsicContentSize, CGSizeZero);
        BOOL secondVisible = !secondView.hidden && !CGSizeEqualToSize(secondView.intrinsicContentSize, CGSizeZero);
        // Set if both views are visible or if there's a visible view on top that doesn't have padding
        // added relative to the current view yet
        padding.constant = (firstVisible && (secondVisible || hasVisibleAncestors)) ? MBDefaultPadding : 0.f;
        hasVisibleAncestors |= secondVisible;
    }];
}

- (void)applyPriority:(UILayoutPriority)priority toConstraints:(NSArray *)constraints {
    for (NSLayoutConstraint *constraint in constraints) {
        constraint.priority = priority;
    }
}

#pragma mark - Properties

- (void)setMode:(MBProgressHUDMode)mode {
    if (mode != _mode) {
        _mode = mode;
        [self updateIndicators];
    }
}

- (void)setCustomView:(UIView *)customView {
    if (customView != _customView) {
        _customView = customView;
        if (self.mode == MBProgressHUDModeCustomView) {
            [self updateIndicators];
        }
    }
}

- (void)setOffset:(CGPoint)offset {
    if (!CGPointEqualToPoint(offset, _offset)) {
        _offset = offset;
        [self setNeedsUpdateConstraints];
    }
}

- (void)setMargin:(CGFloat)margin {
    if (margin != _margin) {
        _margin = margin;
        [self setNeedsUpdateConstraints];
    }
}

- (void)setMinSize:(CGSize)minSize {
    if (!CGSizeEqualToSize(minSize, _minSize)) {
        _minSize = minSize;
        [self setNeedsUpdateConstraints];
    }
}

- (void)setSquare:(BOOL)square {
    if (square != _square) {
        _square = square;
        [self setNeedsUpdateConstraints];
    }
}

- (void)setProgressObjectDisplayLink:(CADisplayLink *)progressObjectDisplayLink {
    if (progressObjectDisplayLink != _progressObjectDisplayLink) {
        [_progressObjectDisplayLink invalidate];
        
        _progressObjectDisplayLink = progressObjectDisplayLink;
        
        [_progressObjectDisplayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    }
}

- (void)setProgressObject:(NSProgress *)progressObject {
    if (progressObject != _progressObject) {
        _progressObject = progressObject;
        [self setNSProgressDisplayLinkEnabled:YES];
    }
}

- (void)setProgress:(float)progress {
    if (progress != _progress) {
        _progress = progress;
        UIView *indicator = self.indicator;
        if ([indicator respondsToSelector:@selector(setProgress:)]) {
            [(id)indicator setValue:@(self.progress) forKey:@"progress"];
        }
    }
}

- (void)setContentColor:(UIColor *)contentColor {
    if (contentColor != _contentColor && ![contentColor isEqual:_contentColor]) {
        _contentColor = contentColor;
        [self updateViewsForColor:contentColor];
    }
}

- (void)setDefaultMotionEffectsEnabled:(BOOL)defaultMotionEffectsEnabled {
    if (defaultMotionEffectsEnabled != _defaultMotionEffectsEnabled) {
        _defaultMotionEffectsEnabled = defaultMotionEffectsEnabled;
        [self updateBezelMotionEffects];
    }
}

#pragma mark - NSProgress

- (void)setNSProgressDisplayLinkEnabled:(BOOL)enabled {
    // We're using CADisplayLink, because NSProgress can change very quickly and observing it may starve the main thread,
    // so we're refreshing the progress only every frame draw
    if (enabled && self.progressObject) {
        // Only create if not already active.
        if (!self.progressObjectDisplayLink) {
            self.progressObjectDisplayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateProgressFromProgressObject)];
        }
    } else {
        self.progressObjectDisplayLink = nil;
    }
}

- (void)updateProgressFromProgressObject {
    self.progress = self.progressObject.fractionCompleted;
}

#pragma mark - Notifications

- (void)registerForNotifications {
#if !TARGET_OS_TV
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    
    [nc addObserver:self selector:@selector(statusBarOrientationDidChange:)
               name:UIApplicationDidChangeStatusBarOrientationNotification object:nil];
#endif
}

- (void)unregisterFromNotifications {
#if !TARGET_OS_TV
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc removeObserver:self name:UIApplicationDidChangeStatusBarOrientationNotification object:nil];
#endif
}

#if !TARGET_OS_TV
- (void)statusBarOrientationDidChange:(NSNotification *)notification {
    UIView *superview = self.superview;
    if (!superview) {
        return;
    } else {
        [self updateForCurrentOrientationAnimated:YES];
    }
}
#endif

- (void)updateForCurrentOrientationAnimated:(BOOL)animated {
    // Stay in sync with the superview in any case
    if (self.superview) {
        self.frame = self.superview.bounds;
    }
    
    // Not needed on iOS 8+, compile out when the deployment target allows,
    // to avoid sharedApplication problems on extension targets
#if __IPHONE_OS_VERSION_MIN_REQUIRED < 80000
    // Only needed pre iOS 8 when added to a window
    BOOL iOS8OrLater = kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_8_0;
    if (iOS8OrLater || ![self.superview isKindOfClass:[UIWindow class]]) return;
    
    // Make extension friendly. Will not get called on extensions (iOS 8+) due to the above check.
    // This just ensures we don't get a warning about extension-unsafe API.
    Class UIApplicationClass = NSClassFromString(@"UIApplication");
    if (!UIApplicationClass || ![UIApplicationClass respondsToSelector:@selector(sharedApplication)]) return;
    
    UIApplication *application = [UIApplication performSelector:@selector(sharedApplication)];
    UIInterfaceOrientation orientation = application.statusBarOrientation;
    CGFloat radians = 0;
    
    if (UIInterfaceOrientationIsLandscape(orientation)) {
        radians = orientation == UIInterfaceOrientationLandscapeLeft ? -(CGFloat)M_PI_2 : (CGFloat)M_PI_2;
        // Window coordinates differ!
        self.bounds = CGRectMake(0, 0, self.bounds.size.height, self.bounds.size.width);
    } else {
        radians = orientation == UIInterfaceOrientationPortraitUpsideDown ? (CGFloat)M_PI : 0.f;
    }
    
    if (animated) {
        [UIView animateWithDuration:0.3 animations:^{
            self.transform = CGAffineTransformMakeRotation(radians);
        }];
    } else {
        self.transform = CGAffineTransformMakeRotation(radians);
    }
#endif
}

@end


@implementation MBRoundProgressView
/* lzy注170821
 圈，是uiview的drawRect画出来的。
 每次setProgress，都重绘
 */
#pragma mark - Lifecycle

- (id)init {
    return [self initWithFrame:CGRectMake(0.f, 0.f, 37.f, 37.f)];
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        _progress = 0.f;
        _annular = NO;
        _progressTintColor = [[UIColor alloc] initWithWhite:1.f alpha:1.f];
        _backgroundTintColor = [[UIColor alloc] initWithWhite:1.f alpha:.1f];
    }
    return self;
}

#pragma mark - Layout

- (CGSize)intrinsicContentSize {
    return CGSizeMake(37.f, 37.f);
}

#pragma mark - Properties

- (void)setProgress:(float)progress {
    if (progress != _progress) {
        _progress = progress;
        [self setNeedsDisplay];
    }
}

- (void)setProgressTintColor:(UIColor *)progressTintColor {
    NSAssert(progressTintColor, @"The color should not be nil.");
    if (progressTintColor != _progressTintColor && ![progressTintColor isEqual:_progressTintColor]) {
        _progressTintColor = progressTintColor;
        [self setNeedsDisplay];
    }
}

- (void)setBackgroundTintColor:(UIColor *)backgroundTintColor {
    NSAssert(backgroundTintColor, @"The color should not be nil.");
    if (backgroundTintColor != _backgroundTintColor && ![backgroundTintColor isEqual:_backgroundTintColor]) {
        _backgroundTintColor = backgroundTintColor;
        [self setNeedsDisplay];
    }
}

#pragma mark - Drawing

- (void)drawRect:(CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext();
    BOOL isPreiOS7 = kCFCoreFoundationVersionNumber < kCFCoreFoundationVersionNumber_iOS_7_0;
    
    if (_annular) {
        // Draw background
        CGFloat lineWidth = isPreiOS7 ? 5.f : 2.f;
        UIBezierPath *processBackgroundPath = [UIBezierPath bezierPath];
        processBackgroundPath.lineWidth = lineWidth;
        processBackgroundPath.lineCapStyle = kCGLineCapButt;
        CGPoint center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
        CGFloat radius = (self.bounds.size.width - lineWidth)/2;
        CGFloat startAngle = - ((float)M_PI / 2); // 90 degrees
        CGFloat endAngle = (2 * (float)M_PI) + startAngle;
        [processBackgroundPath addArcWithCenter:center radius:radius startAngle:startAngle endAngle:endAngle clockwise:YES];
        [_backgroundTintColor set];
        [processBackgroundPath stroke];
        // Draw progress
        UIBezierPath *processPath = [UIBezierPath bezierPath];
        processPath.lineCapStyle = isPreiOS7 ? kCGLineCapRound : kCGLineCapSquare;
        processPath.lineWidth = lineWidth;
        endAngle = (self.progress * 2 * (float)M_PI) + startAngle;
        [processPath addArcWithCenter:center radius:radius startAngle:startAngle endAngle:endAngle clockwise:YES];
        [_progressTintColor set];
        [processPath stroke];
    } else {
        // Draw background
        CGFloat lineWidth = 2.f;
        CGRect allRect = self.bounds;
        CGRect circleRect = CGRectInset(allRect, lineWidth/2.f, lineWidth/2.f);
        CGPoint center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
        [_progressTintColor setStroke];
        [_backgroundTintColor setFill];
        CGContextSetLineWidth(context, lineWidth);
        if (isPreiOS7) {
            CGContextFillEllipseInRect(context, circleRect);
        }
        CGContextStrokeEllipseInRect(context, circleRect);
        // 90 degrees
        CGFloat startAngle = - ((float)M_PI / 2.f);
        // Draw progress
        if (isPreiOS7) {
            CGFloat radius = (CGRectGetWidth(self.bounds) / 2.f) - lineWidth;
            CGFloat endAngle = (self.progress * 2.f * (float)M_PI) + startAngle;
            [_progressTintColor setFill];
            CGContextMoveToPoint(context, center.x, center.y);
            CGContextAddArc(context, center.x, center.y, radius, startAngle, endAngle, 0);
            CGContextClosePath(context);
            CGContextFillPath(context);
        } else {
            UIBezierPath *processPath = [UIBezierPath bezierPath];
            processPath.lineCapStyle = kCGLineCapButt;
            processPath.lineWidth = lineWidth * 2.f;
            CGFloat radius = (CGRectGetWidth(self.bounds) / 2.f) - (processPath.lineWidth / 2.f);
            CGFloat endAngle = (self.progress * 2.f * (float)M_PI) + startAngle;
            [processPath addArcWithCenter:center radius:radius startAngle:startAngle endAngle:endAngle clockwise:YES];
            // Ensure that we don't get color overlaping when _progressTintColor alpha < 1.f.
            CGContextSetBlendMode(context, kCGBlendModeCopy);
            [_progressTintColor set];
            [processPath stroke];
        }
    }
}

@end


@implementation MBBarProgressView

#pragma mark - Lifecycle

- (id)init {
    return [self initWithFrame:CGRectMake(.0f, .0f, 120.0f, 20.0f)];
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _progress = 0.f;
        _lineColor = [UIColor whiteColor];
        _progressColor = [UIColor whiteColor];
        _progressRemainingColor = [UIColor clearColor];
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
    }
    return self;
}

#pragma mark - Layout

- (CGSize)intrinsicContentSize {
    BOOL isPreiOS7 = kCFCoreFoundationVersionNumber < kCFCoreFoundationVersionNumber_iOS_7_0;
    return CGSizeMake(120.f, isPreiOS7 ? 20.f : 10.f);
}

#pragma mark - Properties

- (void)setProgress:(float)progress {
    if (progress != _progress) {
        _progress = progress;
        [self setNeedsDisplay];
    }
}

- (void)setProgressColor:(UIColor *)progressColor {
    NSAssert(progressColor, @"The color should not be nil.");
    if (progressColor != _progressColor && ![progressColor isEqual:_progressColor]) {
        _progressColor = progressColor;
        [self setNeedsDisplay];
    }
}

- (void)setProgressRemainingColor:(UIColor *)progressRemainingColor {
    NSAssert(progressRemainingColor, @"The color should not be nil.");
    if (progressRemainingColor != _progressRemainingColor && ![progressRemainingColor isEqual:_progressRemainingColor]) {
        _progressRemainingColor = progressRemainingColor;
        [self setNeedsDisplay];
    }
}

#pragma mark - Drawing

- (void)drawRect:(CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    CGContextSetLineWidth(context, 2);
    CGContextSetStrokeColorWithColor(context,[_lineColor CGColor]);
    CGContextSetFillColorWithColor(context, [_progressRemainingColor CGColor]);
    
    // Draw background
    CGFloat radius = (rect.size.height / 2) - 2;
    CGContextMoveToPoint(context, 2, rect.size.height/2);
    CGContextAddArcToPoint(context, 2, 2, radius + 2, 2, radius);
    CGContextAddLineToPoint(context, rect.size.width - radius - 2, 2);
    CGContextAddArcToPoint(context, rect.size.width - 2, 2, rect.size.width - 2, rect.size.height / 2, radius);
    CGContextAddArcToPoint(context, rect.size.width - 2, rect.size.height - 2, rect.size.width - radius - 2, rect.size.height - 2, radius);
    CGContextAddLineToPoint(context, radius + 2, rect.size.height - 2);
    CGContextAddArcToPoint(context, 2, rect.size.height - 2, 2, rect.size.height/2, radius);
    CGContextFillPath(context);
    
    // Draw border
    CGContextMoveToPoint(context, 2, rect.size.height/2);
    CGContextAddArcToPoint(context, 2, 2, radius + 2, 2, radius);
    CGContextAddLineToPoint(context, rect.size.width - radius - 2, 2);
    CGContextAddArcToPoint(context, rect.size.width - 2, 2, rect.size.width - 2, rect.size.height / 2, radius);
    CGContextAddArcToPoint(context, rect.size.width - 2, rect.size.height - 2, rect.size.width - radius - 2, rect.size.height - 2, radius);
    CGContextAddLineToPoint(context, radius + 2, rect.size.height - 2);
    CGContextAddArcToPoint(context, 2, rect.size.height - 2, 2, rect.size.height/2, radius);
    CGContextStrokePath(context);
    
    CGContextSetFillColorWithColor(context, [_progressColor CGColor]);
    radius = radius - 2;
    CGFloat amount = self.progress * rect.size.width;
    
    // Progress in the middle area
    if (amount >= radius + 4 && amount <= (rect.size.width - radius - 4)) {
        CGContextMoveToPoint(context, 4, rect.size.height/2);
        CGContextAddArcToPoint(context, 4, 4, radius + 4, 4, radius);
        CGContextAddLineToPoint(context, amount, 4);
        CGContextAddLineToPoint(context, amount, radius + 4);
        
        CGContextMoveToPoint(context, 4, rect.size.height/2);
        CGContextAddArcToPoint(context, 4, rect.size.height - 4, radius + 4, rect.size.height - 4, radius);
        CGContextAddLineToPoint(context, amount, rect.size.height - 4);
        CGContextAddLineToPoint(context, amount, radius + 4);
        
        CGContextFillPath(context);
    }
    
    // Progress in the right arc
    else if (amount > radius + 4) {
        CGFloat x = amount - (rect.size.width - radius - 4);
        
        CGContextMoveToPoint(context, 4, rect.size.height/2);
        CGContextAddArcToPoint(context, 4, 4, radius + 4, 4, radius);
        CGContextAddLineToPoint(context, rect.size.width - radius - 4, 4);
        CGFloat angle = -acos(x/radius);
        if (isnan(angle)) angle = 0;
        CGContextAddArc(context, rect.size.width - radius - 4, rect.size.height/2, radius, M_PI, angle, 0);
        CGContextAddLineToPoint(context, amount, rect.size.height/2);
        
        CGContextMoveToPoint(context, 4, rect.size.height/2);
        CGContextAddArcToPoint(context, 4, rect.size.height - 4, radius + 4, rect.size.height - 4, radius);
        CGContextAddLineToPoint(context, rect.size.width - radius - 4, rect.size.height - 4);
        angle = acos(x/radius);
        if (isnan(angle)) angle = 0;
        CGContextAddArc(context, rect.size.width - radius - 4, rect.size.height/2, radius, -M_PI, angle, 1);
        CGContextAddLineToPoint(context, amount, rect.size.height/2);
        
        CGContextFillPath(context);
    }
    
    // Progress is in the left arc
    else if (amount < radius + 4 && amount > 0) {
        CGContextMoveToPoint(context, 4, rect.size.height/2);
        CGContextAddArcToPoint(context, 4, 4, radius + 4, 4, radius);
        CGContextAddLineToPoint(context, radius + 4, rect.size.height/2);
        
        CGContextMoveToPoint(context, 4, rect.size.height/2);
        CGContextAddArcToPoint(context, 4, rect.size.height - 4, radius + 4, rect.size.height - 4, radius);
        CGContextAddLineToPoint(context, radius + 4, rect.size.height/2);
        
        CGContextFillPath(context);
    }
}

@end


@interface MBBackgroundView ()

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 80000 || TARGET_OS_TV
@property UIVisualEffectView *effectView;
#endif
#if !TARGET_OS_TV
@property UIToolbar *toolbar;
#endif

@end


@implementation MBBackgroundView

#pragma mark - Lifecycle

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        if (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_7_0) {
            _style = MBProgressHUDBackgroundStyleBlur;
            if (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_8_0) {
                _color = [UIColor colorWithWhite:0.8f alpha:0.6f];
            } else {
                _color = [UIColor colorWithWhite:0.95f alpha:0.6f];
            }
        } else {
            _style = MBProgressHUDBackgroundStyleSolidColor;
            _color = [[UIColor blackColor] colorWithAlphaComponent:0.8];
        }
        
        self.clipsToBounds = YES;
        
        [self updateForBackgroundStyle];
    }
    return self;
}

#pragma mark - Layout

- (CGSize)intrinsicContentSize {
    // Smallest size possible. Content pushes against this.
    return CGSizeZero;
}

#pragma mark - Appearance

- (void)setStyle:(MBProgressHUDBackgroundStyle)style {
    if (style == MBProgressHUDBackgroundStyleBlur && kCFCoreFoundationVersionNumber < kCFCoreFoundationVersionNumber_iOS_7_0) {
        style = MBProgressHUDBackgroundStyleSolidColor;
    }
    if (_style != style) {
        _style = style;
        [self updateForBackgroundStyle];
    }
}

- (void)setColor:(UIColor *)color {
    NSAssert(color, @"The color should not be nil.");
    if (color != _color && ![color isEqual:_color]) {
        _color = color;
        [self updateViewsForColor:color];
    }
}

///////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Views

- (void)updateForBackgroundStyle {
    MBProgressHUDBackgroundStyle style = self.style;
    if (style == MBProgressHUDBackgroundStyleBlur) {
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 80000 || TARGET_OS_TV
        if (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_8_0) {
            UIBlurEffect *effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleLight];
            UIVisualEffectView *effectView = [[UIVisualEffectView alloc] initWithEffect:effect];
            [self addSubview:effectView];
            effectView.frame = self.bounds;
            effectView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
            self.backgroundColor = self.color;
            self.layer.allowsGroupOpacity = NO;
            self.effectView = effectView;
        } else {
#endif
#if !TARGET_OS_TV
            UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:CGRectInset(self.bounds, -100.f, -100.f)];
            toolbar.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
            toolbar.barTintColor = self.color;
            toolbar.translucent = YES;
            [self addSubview:toolbar];
            self.toolbar = toolbar;
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 80000 || TARGET_OS_TV
        }
#endif
    } else {
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 80000 || TARGET_OS_TV
        if (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_8_0) {
            [self.effectView removeFromSuperview];
            self.effectView = nil;
        } else {
#endif
#if !TARGET_OS_TV
            [self.toolbar removeFromSuperview];
            self.toolbar = nil;
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 80000 || TARGET_OS_TV
        }
#endif
        self.backgroundColor = self.color;
    }
}

- (void)updateViewsForColor:(UIColor *)color {
    if (self.style == MBProgressHUDBackgroundStyleBlur) {
        if (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_8_0) {
            self.backgroundColor = self.color;
        } else {
#if !TARGET_OS_TV
            self.toolbar.barTintColor = color;
#endif
        }
    } else {
        self.backgroundColor = self.color;
    }
}

@end

/* lzy注170821
 这是之前版本废弃的方法，为了兼容，写了一个当前类MBProgressHUD的分类，把之前如何创建HUD的代码放到了这里。
 */
@implementation MBProgressHUD (Deprecated)

#pragma mark - Class

+ (NSUInteger)hideAllHUDsForView:(UIView *)view animated:(BOOL)animated {
    NSArray *huds = [MBProgressHUD allHUDsForView:view];
    for (MBProgressHUD *hud in huds) {
        hud.removeFromSuperViewOnHide = YES;
        [hud hideAnimated:animated];
    }
    return [huds count];
}

+ (NSArray *)allHUDsForView:(UIView *)view {
    NSMutableArray *huds = [NSMutableArray array];
    NSArray *subviews = view.subviews;
    for (UIView *aView in subviews) {
        if ([aView isKindOfClass:self]) {
            [huds addObject:aView];
        }
    }
    return [NSArray arrayWithArray:huds];
}

#pragma mark - Lifecycle

- (id)initWithWindow:(UIWindow *)window {
    return [self initWithView:window];
}

#pragma mark - Show & hide

- (void)show:(BOOL)animated {
    [self showAnimated:animated];
}

- (void)hide:(BOOL)animated {
    [self hideAnimated:animated];
}

- (void)hide:(BOOL)animated afterDelay:(NSTimeInterval)delay {
    [self hideAnimated:animated afterDelay:delay];
}

#pragma mark - Threading

- (void)showWhileExecuting:(SEL)method onTarget:(id)target withObject:(id)object animated:(BOOL)animated {
    [self showAnimated:animated whileExecutingBlock:^{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        // Start executing the requested task
        [target performSelector:method withObject:object];
#pragma clang diagnostic pop
    }];
}

- (void)showAnimated:(BOOL)animated whileExecutingBlock:(dispatch_block_t)block {
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    [self showAnimated:animated whileExecutingBlock:block onQueue:queue completionBlock:NULL];
}

- (void)showAnimated:(BOOL)animated whileExecutingBlock:(dispatch_block_t)block completionBlock:(void (^)(void))completion {
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    [self showAnimated:animated whileExecutingBlock:block onQueue:queue completionBlock:completion];
}

- (void)showAnimated:(BOOL)animated whileExecutingBlock:(dispatch_block_t)block onQueue:(dispatch_queue_t)queue {
    [self showAnimated:animated whileExecutingBlock:block onQueue:queue completionBlock:NULL];
}

- (void)showAnimated:(BOOL)animated whileExecutingBlock:(dispatch_block_t)block onQueue:(dispatch_queue_t)queue completionBlock:(nullable MBProgressHUDCompletionBlock)completion {
    self.taskInProgress = YES;
    self.completionBlock = completion;
    dispatch_async(queue, ^(void) {
        block();
        dispatch_async(dispatch_get_main_queue(), ^(void) {
            [self cleanUp];
        });
    });
    [self showAnimated:animated];
}

- (void)cleanUp {
    self.taskInProgress = NO;
    [self hideAnimated:self.useAnimation];
}

#pragma mark - Labels

- (NSString *)labelText {
    return self.label.text;
}

- (void)setLabelText:(NSString *)labelText {
    MBMainThreadAssert();
    self.label.text = labelText;
}

- (UIFont *)labelFont {
    return self.label.font;
}

- (void)setLabelFont:(UIFont *)labelFont {
    MBMainThreadAssert();
    self.label.font = labelFont;
}

- (UIColor *)labelColor {
    return self.label.textColor;
}

- (void)setLabelColor:(UIColor *)labelColor {
    MBMainThreadAssert();
    self.label.textColor = labelColor;
}

- (NSString *)detailsLabelText {
    return self.detailsLabel.text;
}

- (void)setDetailsLabelText:(NSString *)detailsLabelText {
    MBMainThreadAssert();
    self.detailsLabel.text = detailsLabelText;
}

- (UIFont *)detailsLabelFont {
    return self.detailsLabel.font;
}

- (void)setDetailsLabelFont:(UIFont *)detailsLabelFont {
    MBMainThreadAssert();
    self.detailsLabel.font = detailsLabelFont;
}

- (UIColor *)detailsLabelColor {
    return self.detailsLabel.textColor;
}

- (void)setDetailsLabelColor:(UIColor *)detailsLabelColor {
    MBMainThreadAssert();
    self.detailsLabel.textColor = detailsLabelColor;
}

- (CGFloat)opacity {
    return _opacity;
}

- (void)setOpacity:(CGFloat)opacity {
    MBMainThreadAssert();
    _opacity = opacity;
}

- (UIColor *)color {
    return self.bezelView.color;
}

- (void)setColor:(UIColor *)color {
    MBMainThreadAssert();
    self.bezelView.color = color;
}

- (CGFloat)yOffset {
    return self.offset.y;
}

- (void)setYOffset:(CGFloat)yOffset {
    MBMainThreadAssert();
    self.offset = CGPointMake(self.offset.x, yOffset);
}

- (CGFloat)xOffset {
    return self.offset.x;
}

- (void)setXOffset:(CGFloat)xOffset {
    MBMainThreadAssert();
    self.offset = CGPointMake(xOffset, self.offset.y);
}

- (CGFloat)cornerRadius {
    return self.bezelView.layer.cornerRadius;
}

- (void)setCornerRadius:(CGFloat)cornerRadius {
    MBMainThreadAssert();
    self.bezelView.layer.cornerRadius = cornerRadius;
}

- (BOOL)dimBackground {
    MBBackgroundView *backgroundView = self.backgroundView;
    UIColor *dimmedColor =  [UIColor colorWithWhite:0.f alpha:.2f];
    return backgroundView.style == MBProgressHUDBackgroundStyleSolidColor && [backgroundView.color isEqual:dimmedColor];
}

- (void)setDimBackground:(BOOL)dimBackground {
    MBMainThreadAssert();
    self.backgroundView.style = MBProgressHUDBackgroundStyleSolidColor;
    self.backgroundView.color = dimBackground ? [UIColor colorWithWhite:0.f alpha:.2f] : [UIColor clearColor];
}

- (CGSize)size {
    return self.bezelView.frame.size;
}

- (UIColor *)activityIndicatorColor {
    return _activityIndicatorColor;
}

- (void)setActivityIndicatorColor:(UIColor *)activityIndicatorColor {
    if (activityIndicatorColor != _activityIndicatorColor) {
        _activityIndicatorColor = activityIndicatorColor;
        UIActivityIndicatorView *indicator = (UIActivityIndicatorView *)self.indicator;
        if ([indicator isKindOfClass:[UIActivityIndicatorView class]]) {
            [indicator setColor:activityIndicatorColor];
        }
    }
}

@end

@implementation MBProgressHUDRoundedButton

#pragma mark - Lifecycle

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        CALayer *layer = self.layer;
        layer.borderWidth = 1.f;
    }
    return self;
}

#pragma mark - Layout

- (void)layoutSubviews {
    [super layoutSubviews];
    // Fully rounded corners
    CGFloat height = CGRectGetHeight(self.bounds);
    self.layer.cornerRadius = ceil(height / 2.f);
}

- (CGSize)intrinsicContentSize {
    // Only show if we have associated control events
    if (self.allControlEvents == 0) return CGSizeZero;
    CGSize size = [super intrinsicContentSize];
    // Add some side padding
    size.width += 20.f;
    return size;
}

#pragma mark - Color

- (void)setTitleColor:(UIColor *)color forState:(UIControlState)state {
    [super setTitleColor:color forState:state];
    // Update related colors
    [self setHighlighted:self.highlighted];
    self.layer.borderColor = color.CGColor;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    UIColor *baseColor = [self titleColorForState:UIControlStateSelected];
    self.backgroundColor = highlighted ? [baseColor colorWithAlphaComponent:0.1f] : [UIColor clearColor];
}

@end
