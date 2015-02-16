//
//  QuotedChatRoomCell.h
//  ChattAR
//
//  Created by Igor Alefirenko on 20/09/2013.
//  Copyright (c) 2013 QuickBlox. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "AsyncImageView.h"

@interface QuotedChatRoomCell : UITableViewCell

@property (nonatomic, strong) AsyncImageView *qUserPhoto;
@property (nonatomic, strong) UIImageView *qColorBuble;
@property (nonatomic, strong) UILabel *qUserName;
@property (nonatomic, strong) UILabel *qMessage;
@property (nonatomic, strong) UILabel *qDateTime;
@property (nonatomic, strong) UIImageView *replyImg;

@property (nonatomic, strong) AsyncImageView *rUserPhoto;
@property (nonatomic, strong) UIImageView *rColorBuble;
@property (nonatomic, strong) UILabel *rDistance;
@property (nonatomic, strong) UILabel *rUserName;
@property (nonatomic, strong) UILabel *rMessage;
@property (nonatomic, strong) UILabel *rDateTime;

- (void)handleParametersForCellWithMessage:(QBChatMessage *)message andIndexPath:(NSIndexPath *)indexPath;
+ (CGFloat)configureHeightForCellWithDictionary:(NSString *)msg;

- (void)bubleImageForChatRoomWithUserID:(NSString *)currentID;

@end
