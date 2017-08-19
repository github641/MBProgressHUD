//
//  MBHudDemoViewController.m
//  HudDemo
//
//  Created by Matej Bukovinski on 30.9.09.
//  Copyright © 2009-2016 Matej Bukovinski. All rights reserved.
//

#import "MBHudDemoViewController.h"
#import "MBProgressHUD.h"
#import <QuartzCore/QuartzCore.h>

@interface MBExample : NSObject

@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) SEL selector;

@end


@implementation MBExample

+ (instancetype)exampleWithTitle:(NSString *)title selector:(SEL)selector {
    MBExample *example = [[self class] new];
    example.title = title;
    example.selector = selector;
    return example;
}

@end


@interface MBHudDemoViewController () <NSURLSessionDelegate>

@property (nonatomic, strong) NSArray<NSArray<MBExample *> *> *examples;
// Atomic, because it may be cancelled from main thread, flag is read on a background thread
@property (atomic, assign) BOOL canceled;

@end


@implementation MBHudDemoViewController

#pragma mark - Lifecycle

- (void)awakeFromNib {
    [super awakeFromNib];
    
    /* lzy注170818：
     准备数据源。双层数组，外层section，内层row
     */
    self.examples =
    @[
      @[[MBExample exampleWithTitle:@"Indeterminate mode" selector:@selector(indeterminateExample)],
        [MBExample exampleWithTitle:@"With label" selector:@selector(labelExample)],
        [MBExample exampleWithTitle:@"With details label" selector:@selector(detailsLabelExample)]],
      
      @[[MBExample exampleWithTitle:@"Determinate mode" selector:@selector(determinateExample)],
        // 环形的
        [MBExample exampleWithTitle:@"Annular determinate mode" selector:@selector(annularDeterminateExample)],
        [MBExample exampleWithTitle:@"Bar determinate mode" selector:@selector(barDeterminateExample)]],
      
      @[[MBExample exampleWithTitle:@"Text only" selector:@selector(textExample)],
        [MBExample exampleWithTitle:@"Custom view" selector:@selector(customViewExample)],
        [MBExample exampleWithTitle:@"With action button" selector:@selector(cancelationExample)],
        [MBExample exampleWithTitle:@"Mode switching" selector:@selector(modeSwitchingExample)]],
      
      @[[MBExample exampleWithTitle:@"On window" selector:@selector(indeterminateExample)],
        [MBExample exampleWithTitle:@"NSURLSession" selector:@selector(networkingExample)],
        [MBExample exampleWithTitle:@"Determinate with NSProgress" selector:@selector(determinateNSProgressExample)],
        [MBExample exampleWithTitle:@"Dim background" selector:@selector(dimBackgroundExample)],
        [MBExample exampleWithTitle:@"Colored" selector:@selector(colorExample)]]
      ];
}

#pragma mark - Examples

#pragma mark - ================== 1 ==================
- (void)indeterminateExample {
    // Show the HUD on the root view (self.view is a scrollable table view and thus not suitable,
    // as the HUD would move with the content as we scroll).
    /* lzy注170818：
     在根视图上展示HUD。
     本类是UITableViewController。那么self.view就是table view，它是可滚动的，所以不合适，因为如果self.view滚动它的内容，那么hud作为内容的一部分也会跟着滚动。
     于是添加到了self.navigationController.view上
     */
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.navigationController.view animated:YES];

    // Fire off（fire off发射、熄火） an asynchronous task, giving UIKit the opportunity to redraw wit the HUD added to the
    // view hierarchy.
    
    /* lzy注170818：
     qos_class_t 是一种枚举，有以下类型：
     QOS_CLASS_USER_INTERACTIVE： user interactive 等级表示任务需要被立即执行，用来在响应事件之后更新 UI，来提供好的用户体验。这个等级最好保持小规模。
     QOS_CLASS_USER_INITIATED： user initiated(开始、发起、开创) 等级表示任务由 UI 发起异步执行。适用场景是需要及时结果同时又可以继续交互的时候。
     QOS_CLASS_DEFAULT： default 默认优先级
     QOS_CLASS_UTILITY： utility 等级表示需要长时间运行的任务，伴有用户可见进度指示器。经常会用来做计算，I/O，网络，持续的数据填充等任务。这个任务节能。
     QOS_CLASS_BACKGROUND： background 等级表示用户不会察觉的任务，使用它来处理预加载，或者不需要用户交互和对时间不敏感的任务。
     QOS_CLASS_UNSPECIFIED： unspecified 未指明
     
     作者：edison0428
     链接：http://www.jianshu.com/p/ef7d760d36b3
     來源：简书
     著作权归作者所有。商业转载请联系作者获得授权，非商业转载请注明出处。
     
     
     // 全局并行队列
     dispatch_get_global_queue
     long identifier：ios 8.0 告诉队列执行任务的“服务质量 quality of service”，系统提供的参数有：
     QOS_CLASS_USER_INTERACTIVE 0x21,              用户交互(希望尽快完成，用户对结果很期望，不要放太耗时操作)
     QOS_CLASS_USER_INITIATED 0x19,                用户期望(不要放太耗时操作)
     QOS_CLASS_DEFAULT 0x15,                        默认(不是给程序员使用的，用来重置对列使用的)
     QOS_CLASS_UTILITY 0x11,                        实用工具(耗时操作，可以使用这个选项)
     QOS_CLASS_BACKGROUND 0x09,                     后台
     QOS_CLASS_UNSPECIFIED 0x00,                    未指定
     iOS 7.0 之前 优先级
     DISPATCH_QUEUE_PRIORITY_HIGH 2                 高优先级
     DISPATCH_QUEUE_PRIORITY_DEFAULT 0              默认优先级
     DISPATCH_QUEUE_PRIORITY_LOW (-2)               低优先级
     DISPATCH_QUEUE_PRIORITY_BACKGROUND INT16_MIN  后台优先级
     // 获取默认优先级的全局并行队列，这里dispatch_get_global_queue的第一个参数为优先级，第二个参数是苹果为未来预留的参数，这里默认写0就可以了
     dispatch_queue_t globalQueue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
     
     作者：ivan_丁丁丁
     链接：http://www.jianshu.com/p/99937c061451
     來源：简书
     著作权归作者所有。商业转载请联系作者获得授权，非商业转载请注明出处。
     
     */
    
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{

        // Do something useful in the background
        [self doSomeWork];

        // IMPORTANT - Dispatch back to the main thread. Always access UI
        // classes (including MBProgressHUD) on the main thread.
        dispatch_async(dispatch_get_main_queue(), ^{
            /* lzy注170818：
             Hides the HUD. This still calls the hudWasHidden: delegate. This is the counterpart(副本、配对、对应的) of the show: method. Use it to hide the HUD when your task completes.
             Parameters
             animated
             If set to YES the HUD will disappear using the current animationType. If set to NO the HUD will not use animations while disappearing.
             */
            [hud hideAnimated:YES];
        });
    });
}

- (void)labelExample {
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.navigationController.view animated:YES];

    // Set the label text.
    hud.label.text = NSLocalizedString(@"Loading...", @"HUD loading title");
    /* lzy注170818：
    可以继续对UILabel其他属性进行设置。e.g.
     hud.label.backgroundColor = [UIColor redColor];
     hud.label.backgroundColor = [UIColor redColor];
     hud.label.layer.masksToBounds = YES;
     hud.label.layer.cornerRadius = 5;
     */
    
    // You can also adjust other label properties if needed.
    // hud.label.font = [UIFont italicSystemFontOfSize:16.f];
    

    
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self doSomeWork];
        dispatch_async(dispatch_get_main_queue(), ^{
            [hud hideAnimated:YES];
        });
    });
}

- (void)detailsLabelExample {
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.navigationController.view animated:YES];

    // Set the label text.
    hud.label.text = NSLocalizedString(@"Loading...", @"HUD loading title");
    // Set the details label text. Let's make it multiline this time.
    hud.detailsLabel.text = NSLocalizedString(@"Parsing data\n(1/1)", @"HUD title");

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self doSomeWork];
        dispatch_async(dispatch_get_main_queue(), ^{
            [hud hideAnimated:YES];
        });
    });
}

#pragma mark - ================== 2 ==================

- (void)determinateExample {
    // self.navigationController.view
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.navigationController.view animated:YES];

    // Set the determinate(确定的、清楚的) mode to show task progress.
    /* lzy注170818：
     hud原来有mode这个属性，是个枚举。
     
     Indeterminate不确定的
     MBProgressHUD operation mode. The default is MBProgressHUDModeIndeterminate.
     
     MBProgressHUDModeDeterminate： A round, pie-chart like, progress view.
     
     */
    hud.mode = MBProgressHUDModeDeterminate;
    hud.label.text = NSLocalizedString(@"Loading...", @"HUD loading title");

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // Do something useful in the background and update the HUD periodically（周期的）.
        [self doSomeWorkWithProgress];
        dispatch_async(dispatch_get_main_queue(), ^{
            [hud hideAnimated:YES];
        });
    });
}

- (void)annularDeterminateExample {
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.navigationController.view animated:YES];
    
    // Set the annular determinate mode to show task progress.
    hud.mode = MBProgressHUDModeAnnularDeterminate;
    hud.label.text = NSLocalizedString(@"Loading...", @"HUD loading title");
    
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // Do something useful in the background and update the HUD periodically.
        [self doSomeWorkWithProgress];
        dispatch_async(dispatch_get_main_queue(), ^{
            [hud hideAnimated:YES];
        });
    });
}


- (void)barDeterminateExample {
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.navigationController.view animated:YES];
    
    // Set the bar determinate mode to show task progress.
    hud.mode = MBProgressHUDModeDeterminateHorizontalBar;
    hud.label.text = NSLocalizedString(@"Loading...", @"HUD loading title");
    
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // Do something useful in the background and update the HUD periodically.
        [self doSomeWorkWithProgress];
        dispatch_async(dispatch_get_main_queue(), ^{
            [hud hideAnimated:YES];
        });
    });
}




#pragma mark - ================== 3 ==================

- (void)textExample {
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.navigationController.view animated:YES];
    
    // Set the text mode to show only text.
    hud.mode = MBProgressHUDModeText;
    hud.label.text = NSLocalizedString(@"Message here!", @"HUD message title");
    // Move to bottm center.
    /* lzy注170818：
     The bezel offset relative to the center of the view. You can use MBProgressMaxOffset and -MBProgressMaxOffset to move the HUD all the way to the screen edge in each direction. E.g., CGPointMake(0.f, MBProgressMaxOffset) would position the HUD centered on the bottom edge.
     */
    hud.offset = CGPointMake(0.f, MBProgressMaxOffset);
    
    [hud hideAnimated:YES afterDelay:3.f];
}

- (void)customViewExample {
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.navigationController.view animated:YES];
    
    // Set the custom view mode to show any view.
    hud.mode = MBProgressHUDModeCustomView;
    // Set an image view with a checkmark.
    UIImage *image = [[UIImage imageNamed:@"Checkmark"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    hud.customView = [[UIImageView alloc] initWithImage:image];
    // Looks a bit nicer if we make it square.
    hud.square = YES;
    // Optional label text.
    hud.label.text = NSLocalizedString(@"Done", @"HUD done title");
    
    [hud hideAnimated:YES afterDelay:3.f];
}

- (void)cancelationExample {
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.navigationController.view animated:YES];

    // Set the determinate mode to show task progress.
    hud.mode = MBProgressHUDModeDeterminate;
    hud.label.text = NSLocalizedString(@"Loading...", @"HUD loading title");

    // Configure the button.
    [hud.button setTitle:NSLocalizedString(@"Cancel", @"HUD cancel button title") forState:UIControlStateNormal];
    [hud.button addTarget:self action:@selector(cancelWork:) forControlEvents:UIControlEventTouchUpInside];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // Do something useful in the background and update the HUD periodically.
        [self doSomeWorkWithProgress];
        dispatch_async(dispatch_get_main_queue(), ^{
            [hud hideAnimated:YES];
        });
    });
}



- (void)modeSwitchingExample {
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.navigationController.view animated:YES];
    
    // Set some text to show the initial status.
    hud.label.text = NSLocalizedString(@"Preparing...", @"HUD preparing title");
    // Will look best, if we set a minimum size.
    hud.minSize = CGSizeMake(150.f, 100.f);
    
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // Do something useful in the background and update the HUD periodically.
        [self doSomeWorkWithMixedProgress];
        dispatch_async(dispatch_get_main_queue(), ^{
            [hud hideAnimated:YES];
        });
    });
}

#pragma mark - ================== 4 ==================
- (void)windowExample {
    /* lzy注170818：
     覆盖整个屏幕。与添加到根视图上的使用方法类似。
     这里showHUDAddedTo传入的参数是self.view.window
     */
    // Covers the entire screen. Similar to using the root view controller view.
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.view.window animated:YES];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self doSomeWork];
        dispatch_async(dispatch_get_main_queue(), ^{
            [hud hideAnimated:YES];
        });
    });
}


- (void)networkingExample {
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.navigationController.view animated:YES];
    
    // Set some text to show the initial status.
    hud.label.text = NSLocalizedString(@"Preparing...", @"HUD preparing title");
    // Will look best, if we set a minimum size.
    hud.minSize = CGSizeMake(150.f, 100.f);
    
    [self doSomeNetworkWorkWithProgress];
}


- (void)determinateNSProgressExample {
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.navigationController.view animated:YES];
    
    // Set the determinate mode to show task progress.
    hud.mode = MBProgressHUDModeDeterminate;
    hud.label.text = NSLocalizedString(@"Loading...", @"HUD loading title");
    
    // Set up NSProgress
    NSProgress *progressObject = [NSProgress progressWithTotalUnitCount:100];
    hud.progressObject = progressObject;
    
    // Configure a cancel button.
    [hud.button setTitle:NSLocalizedString(@"Cancel", @"HUD cancel button title") forState:UIControlStateNormal];
    [hud.button addTarget:progressObject action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];
    
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // Do something useful in the background and update the HUD periodically.
        [self doSomeWorkWithProgressObject:progressObject];
        dispatch_async(dispatch_get_main_queue(), ^{
            [hud hideAnimated:YES];
        });
    });
}


- (void)dimBackgroundExample {
	MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.navigationController.view animated:YES];

	// Change the background view style and color.
	hud.backgroundView.style = MBProgressHUDBackgroundStyleSolidColor;
	hud.backgroundView.color = [UIColor colorWithWhite:0.f alpha:0.1f];

	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		[self doSomeWork];
		dispatch_async(dispatch_get_main_queue(), ^{
			[hud hideAnimated:YES];
		});
	});
}

- (void)colorExample {
	MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.navigationController.view animated:YES];
	hud.contentColor = [UIColor colorWithRed:0.f green:0.6f blue:0.7f alpha:1.f];

	// Set the label text.
	hud.label.text = NSLocalizedString(@"Loading...", @"HUD loading title");

	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		[self doSomeWork];
		dispatch_async(dispatch_get_main_queue(), ^{
			[hud hideAnimated:YES];
		});
	});
}

#pragma mark - Tasks

- (void)doSomeWork {
    // Simulate by just waiting.
    sleep(3.);
}

- (void)doSomeWorkWithProgressObject:(NSProgress *)progressObject {
	// This just increases the progress indicator in a loop.
	while (progressObject.fractionCompleted < 1.0f) {
		if (progressObject.isCancelled) break;
		[progressObject becomeCurrentWithPendingUnitCount:1];
		[progressObject resignCurrent];
		usleep(50000);
	}
}

- (void)doSomeWorkWithProgress {
    self.canceled = NO;
    // This just increases the progress indicator in a loop.
    float progress = 0.0f;
    while (progress < 1.0f) {
        if (self.canceled) break;
        progress += 0.01f;
        dispatch_async(dispatch_get_main_queue(), ^{
            // Instead we could have also passed a reference to the HUD
            // to the HUD to myProgressTask as a method parameter.
            /* lzy注170818：
             使用类方法，获取对应的视图中的hud实例
             */
            [MBProgressHUD HUDForView:self.navigationController.view].progress = progress;
        });
        /* lzy注170818：
         sleep是线程被调用时，占着cpu去睡觉，其他线程不能占用cpu，os认为该线程正在工作，不会让出系统资源
         usleep功能把进程挂起一段时间， 单位是微秒（千分之一毫秒），其他与sleep一样。
         
         功能与sleep类似，只是传入的参数单位是微妙
         若想最佳利用cpu，在更小的时间情况下，选择用usleep
         sleep传入的参数是整形，所以不能传了小数
         usleep不能工作在windows上，只能在linux下。
         
         睡50000微秒之后再继续while循环
         */
        usleep(50000);
    }
}

- (void)doSomeWorkWithMixedProgress {
    MBProgressHUD *hud = [MBProgressHUD HUDForView:self.navigationController.view];
    // Indeterminate mode
    sleep(2);
    // Switch to determinate mode
    dispatch_async(dispatch_get_main_queue(), ^{
        hud.mode = MBProgressHUDModeDeterminate;
        hud.label.text = NSLocalizedString(@"Loading...", @"HUD loading title");
    });
    float progress = 0.0f;
    while (progress < 1.0f) {
        progress += 0.01f;
        dispatch_async(dispatch_get_main_queue(), ^{
            hud.progress = progress;
        });
        usleep(50000);
    }
    // Back to indeterminate mode
    dispatch_async(dispatch_get_main_queue(), ^{
        hud.mode = MBProgressHUDModeIndeterminate;
        hud.label.text = NSLocalizedString(@"Cleaning up...", @"HUD cleanining up title");
    });
    sleep(2);
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIImage *image = [[UIImage imageNamed:@"Checkmark"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
        hud.customView = imageView;
        hud.mode = MBProgressHUDModeCustomView;
        hud.label.text = NSLocalizedString(@"Completed", @"HUD completed title");
    });
    sleep(2);
}

- (void)doSomeNetworkWorkWithProgress {
    NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfig delegate:self delegateQueue:nil];
    NSURL *URL = [NSURL URLWithString:@"https://support.apple.com/library/APPLE/APPLECARE_ALLGEOS/HT1425/sample_iPod.m4v.zip"];
    NSURLSessionDownloadTask *task = [session downloadTaskWithURL:URL];
    [task resume];
}

- (void)cancelWork:(id)sender {
    self.canceled = YES;
}

#pragma mark - UITableViewDelegate

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.examples.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.examples[section].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    MBExample *example = self.examples[indexPath.section][indexPath.row];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"MBExampleCell" forIndexPath:indexPath];
    cell.textLabel.text = example.title;
    cell.textLabel.textColor = self.view.tintColor;
    cell.textLabel.textAlignment = NSTextAlignmentCenter;
    cell.selectedBackgroundView = [UIView new];
    cell.selectedBackgroundView.backgroundColor = [cell.textLabel.textColor colorWithAlphaComponent:0.1f];
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    MBExample *example = self.examples[indexPath.section][indexPath.row];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [self performSelector:example.selector];
#pragma clang diagnostic pop

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
    });
}

#pragma mark - NSURLSessionDelegate

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location {
    // Do something with the data at location...

    // Update the UI on the main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        MBProgressHUD *hud = [MBProgressHUD HUDForView:self.navigationController.view];
        UIImage *image = [[UIImage imageNamed:@"Checkmark"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
        hud.customView = imageView;
        hud.mode = MBProgressHUDModeCustomView;
        hud.label.text = NSLocalizedString(@"Completed", @"HUD completed title");
        [hud hideAnimated:YES afterDelay:3.f];
    });
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    float progress = (float)totalBytesWritten / (float)totalBytesExpectedToWrite;

    // Update the UI on the main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        MBProgressHUD *hud = [MBProgressHUD HUDForView:self.navigationController.view];
        hud.mode = MBProgressHUDModeDeterminate;
        hud.progress = progress;
    });
}
@end
