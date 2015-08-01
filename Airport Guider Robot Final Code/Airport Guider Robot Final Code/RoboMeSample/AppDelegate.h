//
//  AppDelegate.h
//  RoboMeSample
//
//  Copyright (c) 2013 WowWee Group Limited. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <SpeechKit/SpeechKit.h>
#import <CoreMotion/CoreMotion.h>
@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;
- (void)setupSpeechKitConnection;
- (CMMotionManager *)sharedManager;


@end
