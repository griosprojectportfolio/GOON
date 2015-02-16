//
//  DetailDialogsViewController.m
//  ChattAR
//
//  Created by Igor Alefirenko on 29/10/2013.
//  Copyright (c) 2013 QuickBlox. All rights reserved.
//

#import "DetailDialogsViewController.h"
#import "ProfileViewController.h"
#import "NonFriendDialogDataSource.h"
#import "FriendDialogDataSource.h"
#import "ChatRoomCell.h"
#import "FBService.h"
#import "FBStorage.h"
#import "QBService.h"
#import "QBStorage.h"
#import "Utilites.h"
#import "AsyncImageView.h"
#import "ProcessStateService.h"

@interface DetailDialogsViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate, QBActionStatusDelegate, QBChatDelegate>

@property (nonatomic, assign) NSNumber *friendPosition;
@property (strong, nonatomic) IBOutlet UITableView *tableView;
@property (strong, nonatomic) IBOutlet UIView *inputTextView;
@property (strong, nonatomic) IBOutlet UIButton *sendButton;
@property (strong, nonatomic) IBOutlet UITextField *inputMessageField;

// Data Sources:
@property (nonatomic, strong) FriendDialogDataSource *facebookDataSource;
@property (nonatomic, strong) NonFriendDialogDataSource *quickBloxDataSource;

- (IBAction)back:(id)sender;
- (IBAction)sendMessage:(id)sender;

@end

@implementation DetailDialogsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [Flurry logEvent:kFlurryEventDialogScreenWasOpened];
    
    [self configureInputTextViewLayer];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receiveMessage) name:CAChatDidReceiveOrSendMessageNotification object:nil];
    self.title = [self.opponent objectForKey:kName];
    
    NSString *avatarURL = [self.opponent objectForKey:kPhoto];
    AsyncImageView *imgView = [[AsyncImageView alloc] initWithFrame:CGRectMake(0, 0, 28, 28)];
    [imgView setImageURL:[NSURL URLWithString:avatarURL]];
    
    UIGestureRecognizer *tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(viewProfilePage)];
    [imgView addGestureRecognizer:tapGestureRecognizer];
    UIBarButtonItem *profile = [[UIBarButtonItem alloc] initWithCustomView:imgView];

    self.navigationItem.rightBarButtonItem = profile;
    [self chooseKindOfChat];
    
    // KEYBOARD NOTIFICATIONS
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(showKeyboard) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(hideKeyboard) name:UIKeyboardWillHideNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:NO];
    self.conversation[kUnread] = @0;
    [[NSNotificationCenter defaultCenter] postNotificationName:CADialogsHideUnreadMessagesLabelNotification object:nil];
    [ControllerStateService shared].isInDialog = YES;
    [ProcessStateService shared].inDialogWithUserID = self.opponent[kId];
    [self reloadTableView];
}

- (void)viewWillDisappear:(BOOL)animated {
    [ControllerStateService shared].isInDialog = NO;
    [ProcessStateService shared].inDialogWithUserID = nil;
    [super viewWillDisappear:NO];
}

- (void)configureInputTextViewLayer
{
    self.inputTextView.layer.shadowColor = [[UIColor blackColor] CGColor];
    self.inputTextView.layer.shadowRadius = 7.0f;
    self.inputTextView.layer.masksToBounds = NO;
    self.inputTextView.layer.shadowOffset = CGSizeMake(0.0f, 4.0f);
    self.inputTextView.layer.shadowOpacity = 1.0f;
    self.inputTextView.layer.borderWidth = 0.1f;
    
    // button corner-radius
    self.sendButton.layer.cornerRadius = 5.0f;
}

// activating chat:

- (void)chooseKindOfChat {
    if (_isChatWithFacebookFriend) {
        [self activateFacebookChat];
    } else {
        [self activateQuickBloxChat];
    }
}

- (void)activateFacebookChat {
    _facebookDataSource = [[FriendDialogDataSource alloc] init];
    _facebookDataSource.conversation = _conversation;
    _tableView.dataSource = _facebookDataSource;
    [_tableView reloadData];
}

- (void)activateQuickBloxChat {
    _quickBloxDataSource = [[NonFriendDialogDataSource alloc] init];
    _quickBloxDataSource.conversation = _conversation;
    _tableView.dataSource = _quickBloxDataSource;
    [_tableView reloadData];
}


#pragma mark -
#pragma mark Segues

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    ((ProfileViewController *)segue.destinationViewController).controllerTitle = @"Dialog";
    ((ProfileViewController *)segue.destinationViewController).currentUser = self.opponent;
}


#pragma mark -
#pragma mark Actions

- (IBAction)back:(id)sender {
    [self.navigationController popViewControllerAnimated:YES];
}

- (IBAction)sendMessage:(id)sender {
    NSString *trimmedString = [self.inputMessageField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trimmedString length] == 0) {
        return;
    }
    // sending push notification:
    NSString *pushMessage = [NSString stringWithFormat:@"%@: %@", [FBStorage shared].me[kName], trimmedString];
    
    // Send push notification
    //
    [[QBService defaultService] sendPushNotificationWithMessage:pushMessage toUser:_opponent[kQuickbloxID] roomName:nil];
   
    NSString *friendID = _opponent[kId];
    if (_isChatWithFacebookFriend) {
        [[FBService shared] sendMessage:trimmedString toUserWithID:friendID];
    } else {
        NSUInteger userID = [_opponent[kQuickbloxID] integerValue];
        [[QBService defaultService] sendMessage:trimmedString toUser:userID option:friendID];
    }
    
    self.inputMessageField.text = @"";
    [self.inputMessageField resignFirstResponder];
    
    [self reloadTableView];
}

- (void)receiveMessage {
    if (_isChatWithFacebookFriend) {
        NSMutableDictionary *dict = [[FBStorage shared].allFriendsHistoryConversation objectForKey:[_opponent objectForKey:kId]];
        _conversation = dict;
        _facebookDataSource.conversation = dict;
        [self reloadTableView];
        return;
    }
    NSMutableDictionary *dict = [[QBStorage shared].allQuickBloxHistoryConversation objectForKey:[_opponent objectForKey:kId]];
    _conversation = dict;
    _quickBloxDataSource.conversation = dict;
    [self reloadTableView];
}

- (void)viewProfilePage {
    [self performSegueWithIdentifier:kDialogToProfileSegueIdentifier sender:nil];
}
//FB
- (void)reloadTableView {
    [self.tableView reloadData];
    if (self.isChatWithFacebookFriend) {
        if ([[[self.conversation objectForKey:kComments] objectForKey:kData] count] != 0) {
            [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:[[[self.conversation objectForKey:kComments] objectForKey:kData] count]-1 inSection:0] atScrollPosition:UITableViewScrollPositionBottom animated:YES];
        }
    } else {
        if ([[self.conversation objectForKey:kMessage] count]!= 0) {
            [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:[[self.conversation objectForKey:kMessage] count]-1 inSection:0] atScrollPosition:UITableViewScrollPositionBottom animated:YES];
        }
    }
}


#pragma mark -
#pragma mark Show/Hide Keyboard

- (void)showKeyboard {
    CGRect tableFrame = self.tableView.frame;
    tableFrame.size.height -= 215;
    
    [UIView animateWithDuration:0.275 animations:^{
        self.inputTextView.transform = CGAffineTransformMakeTranslation(0, -215);
        self.tableView.frame = tableFrame;
    }];
    [self scrollContentAccordingToChatHistory];
}

- (void)hideKeyboard {
    CGRect tableFrame = self.tableView.frame;
    tableFrame.size.height += 215;
    
    [UIView animateWithDuration:0.275 animations:^{
        self.inputTextView.transform = CGAffineTransformIdentity;
        self.tableView.frame = tableFrame;
    }];
}

-(void)scrollContentAccordingToChatHistory {
    if (self.isChatWithFacebookFriend) {
        if ([(_facebookDataSource.conversation[kComments])[kData] count] > 2) {
            [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:[(_facebookDataSource.conversation[kComments])[kData] count]-1 inSection:0] atScrollPosition:UITableViewScrollPositionBottom animated:NO];
            return;
        }
    }
    if ([_quickBloxDataSource.conversation[kMessage] count] >2) {
        [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:[_quickBloxDataSource.conversation[kMessage] count]-1 inSection:0] atScrollPosition:UITableViewScrollPositionBottom animated:YES];
    }
}


#pragma mark -
#pragma mark UITextField

- (IBAction)textEditDone:(id)sender {
    [sender resignFirstResponder];
}


#pragma mark -
#pragma mark Table View Data Source-

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"NewCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier];
    }
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (_isChatWithFacebookFriend) {
        NSMutableDictionary *message = [[[self.conversation objectForKey:kComments] objectForKey:kData] objectAtIndex:indexPath.row];
        NSString *messageText = [message objectForKey:kMessage];
        return [ChatRoomCell configureHeightForCellWithMessage:messageText];
    }
    QBChatMessage *message = [[self.conversation objectForKey:kMessage] objectAtIndex:indexPath.row];
    NSMutableDictionary *messageData = [[QBService defaultService] unarchiveMessageData:message.text];
    NSString *messageText = [messageData objectForKey:kMessage];
    return [ChatRoomCell configureHeightForCellWithMessage:messageText];
}


#pragma mark -
#pragma mark UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
