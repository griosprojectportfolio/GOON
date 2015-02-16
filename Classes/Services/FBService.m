//
//  FBService.m
//  ChattAR
//
//  Created by QuickBlox developers on 07.05.12.
//  Copyright (c) 2012 QuickBlox. All rights reserved.
//
#import "FBService.h"
#import "XMPPFramework.h"
#import "DDTTYLogger.h"
#import "XMPPStream.h"
#import "FBStorage.h"
#import "Utilites.h"
#import "AppSettingsService.h"
#import "ProcessStateService.h"

@implementation FBService{
    NSTimer *_presenceTimer;
}

#pragma mark -
#pragma mark Singletone

+ (instancetype)shared {
    static id instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (id)init {
    self = [super init];
    if (self) {
		xmppStream = [[XMPPStream alloc] initWithFacebookAppId:APP_ID];
		[xmppStream addDelegate:self delegateQueue:dispatch_get_main_queue()];
    }
    return self;
}


#pragma mark -
#pragma mark Facebook Requests

- (void)userProfileWithResultBlock:(FBResultBlock)resultBlock {
    FBRequest *meRequest = [FBRequest requestForMe];
    [meRequest startWithCompletionHandler:^(FBRequestConnection *connection, id result, NSError *error) {
        resultBlock(result);
    }];
}

- (void)userFriendsUsingBlock:(FBResultBlock)resultBlock {
    FBRequest *friendsRequest = [FBRequest requestForMyFriends];
    [friendsRequest startWithCompletionHandler:^(FBRequestConnection *connection, id result, NSError *error) {
        resultBlock(result);
    }];
}

- (void)userProfileWithID:(NSString *)userID withBlock:(FBResultBlock)resultBlock {
    FBRequest *requestForID = [FBRequest requestForGraphPath:userID];
    [requestForID startWithCompletionHandler:^(FBRequestConnection *connection, id result, NSError *error) {
        resultBlock(result);
    }];
}

- (void)usersProfilesWithIDs:(NSArray *)userIDs resultBlock:(FBResultBlock)resultBlock {
    NSString *path = @"?ids=";
    if (userIDs == nil && [userIDs count] == 0) {
        return;
    }
    for (NSString *ID in userIDs) {
        if ([ID isEqualToString:[userIDs lastObject]]) {
            path = [path stringByAppendingString:ID];
            break;
        }
        path = [path stringByAppendingString:ID];
        path = [path stringByAppendingString:@","];
    }
    FBRequest *opponentsRequest = [FBRequest requestForGraphPath:path];
    [opponentsRequest startWithCompletionHandler:^(FBRequestConnection *connection, id result, NSError *error) {
        resultBlock(result);
    }];
}


#pragma mark -
#pragma mark Messages

- (void)sendMessage:(NSString *)messageText toUserWithID:(NSString *)userID {
    
    // send message to facebook
    //
    [[FBService shared] sendMessage:messageText toFacebookWithFriendID:userID];
    
    [Flurry logEvent:kFlurryEventDialogMessageWasSent withParameters:@{@"type":@"Facebook"}];
    
    
    // Save message to history
    //
    NSMutableDictionary *facebookMessage = [[NSMutableDictionary alloc] init];
    [facebookMessage setValue:messageText forKey:kMessage];
    NSDate *date = [NSDate date];
    NSString *createdTime = [[Utilites shared].dateFormatter stringFromDate:date];
    [facebookMessage setValue:createdTime forKey:kCreatedTime];
    NSMutableDictionary *from = [[NSMutableDictionary alloc] init];
    [from setValue:[[FBStorage shared].me objectForKey:kId] forKey:kId];
    [from setValue:[[FBStorage shared].me objectForKey:kName] forKey:kName];
    [facebookMessage setValue:from forKey:kFrom];
    //
    //
    NSMutableDictionary *conversation = [[FBStorage shared].allFriendsHistoryConversation objectForKey:userID];
    if (conversation == nil) {
        conversation = [[NSMutableDictionary alloc] init];
    }
    NSMutableArray *data = [(conversation[kComments])[kData] mutableCopy];
    if (data ==nil) {
        data = [@[facebookMessage] mutableCopy];
    } else {
        [data addObject:facebookMessage];
    }
    NSMutableDictionary *comments = [@{kData: data} mutableCopy];
    [conversation setObject:comments forKey:kComments];
    
    // last message date to user
    NSMutableDictionary *user = [FBStorage shared].friendsAsDictionary[userID];
    user[kLastMessageDate] = createdTime;
    
    [[FBStorage shared].allFriendsHistoryConversation setObject:conversation forKey:userID];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:CAChatDidReceiveOrSendMessageNotification object:nil];
}


#pragma mark -
#pragma mark Post to Feed

- (void)publishMessageToFeed:(NSString *)message {
    
    NSMutableDictionary *postParams = [@{
                                         @"link" : @"https://itunes.apple.com/us/app/chattar-for-facebook/id543208565?mt=8",
                                         @"picture" : @"https://s3.amazonaws.com/qbprod/70680c6415024fb9a302db074c71869c00",
                                         @"name" : @"ChattAR",
                                         @"caption" : @"By QuickBlox",
                                         @"description" : @"Your Facebook app with extra location-based features. Stay in touch with your friends or meet new people locally."
                                         } mutableCopy];
    
    postParams[kMessage] = message;
    [FBRequestConnection startWithGraphPath:@"me/feed" parameters:postParams HTTPMethod:@"POST" completionHandler:^(FBRequestConnection *connection, id result, NSError *error) {
        
        [[NSNotificationCenter defaultCenter] postNotificationName:CARoomDidPublishedToFacebookNotification object:error];
    }];
}


#pragma mark -
#pragma mark Options

+ (NSMutableDictionary *)findFBConversationWithFriend:(NSMutableDictionary *)aFriend {
    
    NSMutableDictionary *conversation = [FBStorage shared].allFriendsHistoryConversation[aFriend[kId]] ;
    if (conversation != nil) {
        return conversation;
    }
    // if not return, create new conversation:
    NSMutableDictionary *newConversation = [[NSMutableDictionary alloc]init];
    // adding commnets to this conversation:
    NSMutableDictionary *comments = [[NSMutableDictionary alloc] init];
    NSMutableArray *array = [[NSMutableArray alloc] init];
    [comments setObject:array forKey:kData];
    [newConversation setObject:comments forKey:kComments];
    
    // adding kTo:
    NSMutableDictionary *kto = [[NSMutableDictionary alloc] init];
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
    [dict setValue:[aFriend objectForKey:kId] forKey:kId];
    [dict setValue:[aFriend objectForKey:kName] forKey:kName];
    
    [kto setValue:[NSMutableArray arrayWithObject:dict] forKey:kData];
    [newConversation setObject:kto forKey:kTo];
    
    return newConversation;
}

- (void)putQuickbBloxIDsToFacebookUsers:(NSMutableArray *)facebookUsers fromQuickbloxUsers:(NSArray *)quickbloxUsers {
    for (NSMutableDictionary *facebookUser in facebookUsers) {
        NSString *facebookUserID = facebookUser[kId];
        
        for (QBUUser *quickbloxUser in quickbloxUsers) {
            if ([quickbloxUser.facebookID isEqualToString:facebookUserID]) {
                facebookUser[kQuickbloxID] = [@(quickbloxUser.ID) stringValue];
                break;
            }
        }
    }
}

- (NSDictionary *)findFriendWithID:(NSString *)facebookID {
    NSArray *friends = [FBStorage shared].friends;
    for (NSDictionary *friend in friends) {
        if ([friend[kId] isEqualToString:facebookID]) {
            return friend;
        }
    }
    return nil;
}


#pragma mark -
#pragma mark XMPP Chat

-(void)logInChat {
	NSError *error = nil;
	[xmppStream connectWithTimeout:30 error:&error];
}

- (void)logOutChat {
    [xmppStream disconnect];
}

- (void) sendMessage:(NSString *)textMessage toFacebookWithFriendID:(NSString *)friendID{
    if([textMessage length] == 0) {
        return;
    }

    NSXMLElement *body = [NSXMLElement elementWithName:@"body"];
    [body setStringValue:textMessage];
    
    NSXMLElement *message = [NSXMLElement elementWithName:@"message"];
    [message addAttributeWithName:@"to" stringValue:[NSString stringWithFormat:@"-%@@chat.facebook.com",friendID]];
    [message addChild:body];
    [xmppStream sendElement:message];
}

- (void) inboxMessagesWithBlock:(FBResultBlock)resultBlock{
    NSString *urlString = [NSString stringWithFormat:@"%@/me/inbox?access_token=%@",FB, [FBStorage shared].accessToken];
    NSURL *url = [NSURL URLWithString:[urlString stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSURLResponse *response = nil;
        NSData *resultData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:nil];
        NSDictionary *jsonDict = [NSJSONSerialization JSONObjectWithData:resultData options:NSJSONReadingMutableContainers error:nil];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            resultBlock(jsonDict);
        });
    });
}


#pragma mark -
#pragma mark Loading and handling

- (void)loadAndHandleDataAboutMeAndMyFriends
{
    // get info about me:
    [self userProfileWithResultBlock:^(id result) {
        FBGraphObject *user = (FBGraphObject *)result;
        [FBStorage shared].me = [user mutableCopy];
        
        [QBUsers userWithFacebookID:user[kId] delegate:[QBEchoObject instance] context:[QBEchoObject makeBlockForEchoObject:^(Result *result) {
            //
            QBUUser *qbMe = ((QBUUserResult *)result).user;
            [FBStorage shared].me[kQuickbloxID] = @(qbMe.ID);
        }]];
    }];
    
    
    // get my friends:
    [self userFriendsUsingBlock:^(id result) {
        
        // save friends
        NSMutableArray *myFriends = [(FBGraphObject *)result objectForKey:kData];
        if ([myFriends count] == 0) {
            // post notification
            [[NSNotificationCenter defaultCenter] postNotificationName:CAStateDataLoadedNotification object:nil userInfo:@{kFriendsLoaded:@YES}];
            return;
        }
        
        [FBStorage shared].friends = myFriends;
        
        NSMutableArray *friendsIDs = [[NSMutableArray alloc] init];
        
        // add photo urls to friends, collect ids
        for (NSMutableDictionary *friend in myFriends) {
            // add photo
            NSString *urlString = [[NSString alloc] initWithFormat:@"https://graph.facebook.com/%@/picture?access_token=%@",friend[kId],[FBStorage shared].accessToken];
            friend[kPhoto] = urlString;
            
            // add flag (friend)
            friend[kIsFriend] = @YES;
            
            // collect id
            NSString *userID = friend[kId];
            [friendsIDs addObject:userID];
            
            // last message date
            NSDictionary *messageDict = [(([FBStorage shared].allFriendsHistoryConversation[userID])[kComments])[kData] lastObject];
            NSString *createdTime = messageDict[kCreatedTime];
            if (createdTime != nil) {
                friend[kLastMessageDate] = createdTime;
            }
        }
        // Search QB Users by FB friends
        //
        NSMutableArray *chunkIDs = [[NSMutableArray alloc] init];
        NSMutableArray *findQBUser = [[NSMutableArray alloc] init];
        
        __block int friendsChunks = 0;
        void (^friendsResultBlock)(Result *) = ^(Result *result) {
            if (result.success && [result isKindOfClass:[QBUUserPagedResult class]]) {
                friendsChunks--;
                
                QBUUserPagedResult *pagedResult = (QBUUserPagedResult *)result;
                NSArray *qbUsers = pagedResult.users;
                
                [findQBUser addObjectsFromArray:qbUsers];
                
                // Received all friends
                if (friendsChunks == 0) {
                    
                    // set QB user id to facebook friend
                    for (QBUUser *quickbloxUser in findQBUser) {
                        NSMutableDictionary *facebookFriend = [FBStorage shared].friendsAsDictionary[quickbloxUser.facebookID];
                        facebookFriend[kQuickbloxID] = [@(quickbloxUser.ID) stringValue];
                    }

                    // post notification
                    [[NSNotificationCenter defaultCenter] postNotificationName:CAStateDataLoadedNotification object:nil userInfo:@{kFriendsLoaded:@YES}];
                    return;
                }
            }
        };
        for (NSMutableDictionary *userID in friendsIDs) {
            if ([chunkIDs count] <= 99) {
                [chunkIDs addObject:userID];
            } else {
                friendsChunks++;
                
                // QBUsers request:
                PagedRequest *pagedRequest = [PagedRequest request];
                pagedRequest.perPage = 100;
                [QBUsers usersWithFacebookIDs:[chunkIDs copy] pagedRequest:pagedRequest delegate:[QBEchoObject instance] context:[QBEchoObject makeBlockForEchoObject:friendsResultBlock]];
                
                // remove terminatearray and add one new object:
                [chunkIDs removeAllObjects];
                [chunkIDs addObject:userID];
            }
        }
        // last chunk
        if ([chunkIDs count] > 0) {
            PagedRequest *pagedRequest = [PagedRequest request];
            pagedRequest.perPage = 100;
            [QBUsers usersWithFacebookIDs:[chunkIDs copy] pagedRequest:pagedRequest delegate:[QBEchoObject instance] context:[QBEchoObject makeBlockForEchoObject:friendsResultBlock]];
            friendsChunks++;
        }
    }];
}
      

- (NSMutableDictionary *)handleFacebookHistoryConversation:(NSMutableArray *)conversation {
    NSMutableDictionary *history = [[NSMutableDictionary alloc] init];
    for (NSMutableDictionary *dict in conversation) {
        NSArray *array = [[dict objectForKey:kTo] objectForKey:kData];
        // if only me and opponent:
        if ([array count] <= 2) {
            for (NSMutableDictionary *element in array) {
                if ([element objectForKey:kId] != [[FBStorage shared].me objectForKey:kId]) {
                    [history setObject:dict forKey:[element objectForKey:kId]];
                }
            }
        } else {
            // if not only me and opponent:
            NSArray *messages = (dict[kComments])[kData];
            NSString *myID = [FBStorage shared].me[kId];
            for (NSDictionary *message in messages){
                NSString *opponentID = (message[kFrom])[kId];
                if ([opponentID isEqualToString:myID]) {
                    history[opponentID] = dict;
                    break;
                }
            }
            
        }
    }
    return history;
}

#pragma mark -
#pragma mark Chat API

- (void)sendPresence {
	XMPPPresence *presence = [XMPPPresence presence];
	[xmppStream sendElement:presence];
}

- (void)xmppStreamDidConnect:(XMPPStream *)sender {
    if (![xmppStream isSecure]){
        NSError *error = nil;
        BOOL result = [xmppStream secureConnection:&error];
        
        if (result == NO){
            NSLog(@"XMPP STARTTLS failed");
        }
    } else{
        NSError *error = nil;
		BOOL result = [xmppStream authenticateWithFacebookAccessToken:[FBStorage shared].accessToken error:&error];

        if (result == NO){
            NSLog(@"XMPP authentication failed");
        }
    }
}

- (void)xmppStreamDidAuthenticate:(XMPPStream *)sender
{
    NSLog(@"Facebook XMPP authenticated");
    _presenceTimer = [NSTimer scheduledTimerWithTimeInterval:30 target:self
                                                    selector:@selector(sendPresence) 
                                                    userInfo:nil repeats:YES];
}

- (void)xmppStream:(XMPPStream *)sender didNotAuthenticate:(NSXMLElement *)error
{
    NSLog(@"XMPP authentication failed");
    
    UIAlertView* alertView = [[UIAlertView alloc] initWithTitle:@"FB Chat Authenticate Fail" message:@"Please restart application" delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
	[alertView show];
}

- (void)xmppStreamDidDisconnect:(XMPPStream *)sender withError:(NSError *)error
{
    _presenceTimer = nil;
    NSLog(@"XMPP disconnected");
    
    // reconnect if disconnected
    if([Reachability internetConnected]){
        [self logInChat];
    }
}

- (void)xmppStream:(XMPPStream *)sender didReceiveMessage:(XMPPMessage *)message
{
	[self backgroundMessageReceived:message];
}

- (void)backgroundMessageReceived:(XMPPMessage *)textMessage
{
	NSString *body = [[textMessage elementForName:kBody] stringValue];
    if (body == nil) {
        return;
    }
    
    NSMutableString *fromID = [[textMessage attributeStringValueForName:kFrom] mutableCopy];
    [fromID replaceCharactersInRange:NSMakeRange(0, 1) withString:@""]; // remove -
    [fromID replaceOccurrencesOfString:@"@chat.facebook.com" withString:@""
                               options:0 range:NSMakeRange(0, [fromID length])]; // remove @chat.facebook.com
    NSArray *friends = [FBStorage shared].friends;
    
    // find opponent:
    NSMutableDictionary *friend = nil;
    for (NSMutableDictionary *myFriend in friends) {
        if ([[myFriend objectForKey:kId] isEqual:fromID]) {
            friend = myFriend;
            break;
        }
    }
    if(friend == nil){
        return;
    }
    // create a message
    NSMutableDictionary *message = [[NSMutableDictionary alloc] init];
    NSMutableDictionary *from = [[NSMutableDictionary alloc] init];
    [from setValue:[friend objectForKey:kId] forKey:kId];
    [from setValue:[friend objectForKey:kName] forKey:kName];
    [message setValue:from forKey:kFrom];
    [message setValue:body forKey:kMessage];
    
    // sate datetime
    NSDate *date = [NSDate date];
    NSString *lastMessageDate = [[Utilites shared].dateFormatter stringFromDate:date];
    friend[kLastMessageDate] = lastMessageDate;
    
    NSString *createdTime = [[Utilites shared].dateFormatter stringFromDate:date];
    [message setValue:createdTime forKey:kCreatedTime];
    
    // increase unread msg count
    if (![ControllerStateService shared].isInDialog && ![[ProcessStateService shared].inDialogWithUserID isEqualToString:friend[kId]]) {
        NSNumber *number = ([FBStorage shared].allFriendsHistoryConversation[fromID])[kUnread];
        if (number == nil) {
            ([FBStorage shared].allFriendsHistoryConversation[fromID])[kUnread] = @1;
        } else {
            int numb = [number integerValue];
            numb++;
            ([FBStorage shared].allFriendsHistoryConversation[fromID])[kUnread] = @(numb);
        }
    }
    // save message to history
    [[[[[FBStorage shared].allFriendsHistoryConversation objectForKey:fromID] objectForKey:kComments] objectForKey:kData] addObject:message];
    
    // post notification
    [[NSNotificationCenter defaultCenter] postNotificationName:CAChatDidReceiveOrSendMessageNotification object:nil userInfo:friend];
    
    // play sound and vibrate:
    AppSettingsService *service = [AppSettingsService shared];
    [Utilites playSound:service.soundEnabled vibrate:service.vibrationEnabled];
}

@end
