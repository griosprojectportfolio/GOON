//
//  Utilites.h
//  ChattAR
//
//  Created by Igor Alefirenko on 26/09/2013.
//  Copyright (c) 2013 QuickBlox. All rights reserved.
//

#import <Foundation/Foundation.h>

@class MBProgressHUD;

@interface Utilites : NSObject

@property (nonatomic, assign) BOOL userLoggedIn;
@property (assign, nonatomic) BOOL isArNotAvailable;
@property (nonatomic, assign) BOOL isShared;
@property (nonatomic, strong) NSDateFormatter *dateFormatter;
@property (strong, nonatomic) MBProgressHUD *progressHUD;
@property (strong, nonatomic) NSDictionary *fullTimePassedFormat;

+ (instancetype)shared;
+ (BOOL)deviceSupportsAR;

- (NSString *)distanceFormatter:(CLLocationDistance)distance;
- (void)checkAndPutStatusBarColor;
- (BOOL)isUserLoggedIn;
- (void)setUserLogIn;


#pragma mark -
#pragma mark Date Formatter

- (NSInteger)yearsFromDate:(NSString *)dateString;
- (NSString *)fullFormatPassedTimeFromDate:(NSDate *)date;


#pragma mark -
#pragma mark Escape symbols encoding

+(NSString*)urlencode:(NSString*)unencodedString;
+(NSString*)urldecode:(NSString*)encodedString;


#pragma mark -
#pragma mark AVAudioPlayer

+ (void)playSound:(BOOL)played vibrate:(BOOL)vibrated;

@end
