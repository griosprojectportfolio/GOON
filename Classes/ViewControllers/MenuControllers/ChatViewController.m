//
//  ChatViewController.m
//  ChattAR
//
//  Created by Igor Alefirenko on 28/08/2013.
//  Copyright (c) 2013 QuickBlox. All rights reserved.
//

#import "SASlideMenuRootViewController.h"
#import "ChatViewController.h"
#import "TrendingChatRoomsDataSource.h"
#import "LocalChatRoomsDataSource.h"
#import "FBService.h"
#import "FBStorage.h"
#import "ChatRoomStorage.h"
#import "LocationService.h"
#import "Utilites.h"
#import "ChatRoomViewController.h"
#import "AppSettingsService.h"

@interface ChatViewController () <UITableViewDataSource, UITableViewDelegate, QBActionStatusDelegate, QBChatDelegate, UIAlertViewDelegate, NMPaginatorDelegate, UIScrollViewDelegate, UISearchBarDelegate>

@property (nonatomic, strong) IBOutlet UITableView *trendingTableView;
@property (strong, nonatomic) IBOutlet UITableView *locationTableView;
@property (strong, nonatomic) IBOutlet UISearchBar *searchBar;

@property (nonatomic, strong) NSMutableArray *trendings;
@property (nonatomic, strong) NSMutableArray *locals;

@property (nonatomic, strong) TrendingChatRoomsDataSource *trendingDataSource;
@property (nonatomic, strong) LocalChatRoomsDataSource *locationDataSource;

@property (nonatomic, strong) UIActivityIndicatorView *trendingActivityIndicator;
@property (nonatomic, strong) UILabel *trendingFooterLabel;
@property (nonatomic, weak) NSString *tableName;

- (IBAction)globalSearch:(id)sender;

@end

@implementation ChatViewController

#pragma mark - 
#pragma mark LifeCycle

- (void)dealloc{
    QBDLogEx(@"");
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [Flurry logEvent:kFlurryEventChatScreenWasOpened];
    
    self.searchBar.autocorrectionType= UITextAutocorrectionTypeNo;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide) name:UIKeyboardWillHideNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateDistanceLabels) name:CAUpdateLocationNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(loadRooms) name:kNotificationDidLogin object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(newRoomCreated:) name:CAChatRoomDidCreateNotification object:nil];

    _trendings = [[NSMutableArray alloc] initWithArray:[[ChatRoomStorage shared] trendingRooms]];
    _locals = [[NSMutableArray alloc] initWithArray:[[ChatRoomStorage shared] localRooms]];
    
    _trendingTableView.tag = kTrendingTableViewTag;
    _locationTableView.tag = kLocalTableViewTag;
    
    
    if(_trendings.count > 0){
        self.trendingDataSource.chatRooms = _trendings;
    }
    if(_locals.count > 0){
        self.locationDataSource.chatRooms = [[ChatRoomStorage shared] localRooms];
    }
    
    self.trendingTableView.dataSource = self.trendingDataSource;
    self.locationTableView.dataSource = self.locationDataSource;
    
    self.trendingTableView.delegate = self;
    self.locationTableView.delegate = self;
    
    // paginator:
    self.trendingPaginator = [[ChatRoomsPaginator alloc] initWithPageSize:10 delegate:self];
    self.trendingPaginator.tag = kTrendingPaginatorTag;
    self.trendingTableView.tableFooterView = [self creatingTrendingFooter];
    if(_trendings.count > 0 ){
        if (![[ChatRoomStorage shared] endOfList]) {
            [self.trendingPaginator setPageTo:[_trendings count]/10];
            self.trendingFooterLabel.text = [NSString stringWithFormat:@"Load more..."];
            [self.trendingFooterLabel setNeedsDisplay];
        } else {
            self.trendingTableView.tableFooterView = nil;
        }
    }
    
    // if iPhone 5
    self.scrollView.pagingEnabled = YES;
    if(IS_HEIGHT_GTE_568){
        self.scrollView.contentSize = CGSizeMake(500, 504);
    } else {
        self.scrollView.contentSize = CGSizeMake(500, 416);
    }
    // hard code
    if (![[Utilites shared] isUserLoggedIn]) {
        [self performSegueWithIdentifier:@"Splash" sender:self];
        [[Utilites shared] setUserLogIn];
    }
    [self configureSearchIndicatorView];
}

- (void)configureSearchIndicatorView
{
    if (!self.searchIndicatorView) {
        self.searchIndicatorView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        self.searchIndicatorView.frame = CGRectMake(self.view.frame.size.width/2 - 10, self.view.frame.size.height/2 -10, 20 , 20);
        [self.searchIndicatorView hidesWhenStopped];
        [self.view addSubview:self.searchIndicatorView];
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.locationDataSource.distances = [self arrayOfDistances:[[ChatRoomStorage shared] localRooms]];
    [self.trendingTableView reloadData];
    [self.locationTableView reloadData];
}


#pragma mark -
#pragma mark Notifications

- (void)updateDistanceLabels
{
    [[NSNotificationCenter defaultCenter] removeObserver:CAUpdateLocationNotification];
    if ([ChatRoomStorage shared].localRooms == nil) {
        return;
    }
    NSArray *localRooms = [[ChatRoomStorage shared] sortRooms:[ChatRoomStorage shared].localRooms
                                          accordingToLocation:[LocationService shared].myLocation
                                                        limit:30];
    [ChatRoomStorage shared].localRooms = localRooms;
    self.locationDataSource.chatRooms = localRooms;
    self.locationDataSource.distances = [self arrayOfDistances:localRooms];
    [self.locationTableView reloadData];
}

- (void)loadRooms
{
    [[NSNotificationCenter defaultCenter]  removeObserver:self name:kNotificationDidLogin object:nil];
    
    if ([_trendings count] == 0) {
        [self.trendingPaginator fetchFirstPage];
    }
    if ([[ChatRoomStorage shared] localRooms] == nil) {
        NSMutableDictionary *extendedRequest = [@{@"limit": @([AppSettingsService shared].localLimit)} mutableCopy];
        [QBCustomObjects objectsWithClassName:kChatRoom extendedRequest:extendedRequest delegate:[QBEchoObject instance] context:[QBEchoObject makeBlockForEchoObject:^(Result *result) {
            // to do
            if ([result success] && [result isKindOfClass:[QBCOCustomObjectPagedResult class]]) {
                // todo:
                QBCOCustomObjectPagedResult *pagedResult = (QBCOCustomObjectPagedResult *)result;
                [ChatRoomStorage shared].allLoadedRooms = pagedResult.objects;
                
                _locals = [[ChatRoomStorage shared] sortRooms:[pagedResult.objects copy]
                                          accordingToLocation:[LocationService shared].myLocation
                                                        limit:30];
                [[ChatRoomStorage shared] setLocalRooms:_locals];
                _locationDataSource.chatRooms = _locals;
                _locationDataSource.distances = [self arrayOfDistances:_locals];
                [[ChatRoomStorage shared] setDistances:[self arrayOfDistances:[[ChatRoomStorage shared] localRooms]]];
                [self.locationTableView reloadData];
                [[NSNotificationCenter defaultCenter] postNotificationName:CAStateDataLoadedNotification object:nil userInfo:@{kLocalRoomListLoaded: @YES}];
            }
        }]];
    }else {
        _locationDataSource.chatRooms = [[ChatRoomStorage shared] localRooms];
        _locationDataSource.distances = [self arrayOfDistances:[[ChatRoomStorage shared] localRooms]];
    }
}

- (void)newRoomCreated:(NSNotification *)notification
{
    QBCOCustomObject *room = notification.object;
    [self.locals insertObject:room atIndex:0];
    [ChatRoomStorage shared].localRooms = self.locals;
    self.locationDataSource.chatRooms = self.locals;
    double_t distance = [self distanceFromNewRoom:room];
    [self.locationDataSource.distances insertObject:[NSNumber numberWithDouble:distance] atIndex:0];
}

- (void)keyboardWillShow
{
    CGRect tableFrame = self.trendingTableView.frame;
    tableFrame.size.height -= 215;
    [UIView animateWithDuration:0.25 animations:^{
        [self.trendingTableView setFrame:tableFrame];
    }];
}

- (void)keyboardWillHide
{
    CGRect tableFrame = self.trendingTableView.frame;
    tableFrame.size.height += 215;
    [UIView animateWithDuration:0.25 animations:^{
        [self.trendingTableView setFrame:tableFrame];
    }];
}


#pragma mark - Paginator

- (void)fetchNextPage:(ChatRoomsPaginator *)paginator
{
    [paginator fetchNextPage];
    if (paginator.tag == kTrendingPaginatorTag) {
        [self.trendingActivityIndicator startAnimating];
    }
}

- (void)updateTableViewFooterWithPaginator:(ChatRoomsPaginator *)paginator
{
    if ([paginator.results count] != 0)
    {
        if (paginator.tag == kTrendingPaginatorTag) {
            self.trendingFooterLabel.text = [NSString stringWithFormat:@"Load more..."];
            [self.trendingFooterLabel setNeedsDisplay];
        }
    }
}

- (UIView *)creatingTrendingFooter
{
    UIView *footerView = [[UIView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, _trendingTableView.frame.size.width, 44.0f)];
    footerView.backgroundColor = [UIColor clearColor];
    _trendingFooterLabel = [[UILabel alloc] initWithFrame:CGRectMake(0.0f, 0.0f, _trendingTableView.frame.size.width, 44.0f)];
    _trendingFooterLabel.backgroundColor = [UIColor clearColor];
    _trendingFooterLabel.textAlignment = NSTextAlignmentCenter;
    _trendingFooterLabel.textColor = [UIColor lightGrayColor];
    _trendingFooterLabel.font = [UIFont systemFontOfSize:16];
    [footerView addSubview:_trendingFooterLabel];
    
    self.trendingActivityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.trendingActivityIndicator.center = CGPointMake(40.0, 22.0);
    self.trendingActivityIndicator.hidesWhenStopped = YES;
    [footerView addSubview:self.trendingActivityIndicator];
    return footerView;
}


#pragma mark - 
#pragma mark ScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    
    if (self.trendingTableView.tableFooterView  != nil) {
        if (scrollView.contentOffset.y == (scrollView.contentSize.height - scrollView.bounds.size.height))
        {
            if (scrollView.tag == kTrendingTableViewTag) {
                // ask next page only if we haven't reached last page
                if(![self.trendingPaginator reachedLastPage])
                {
                    // fetch next page of results
                    [self fetchNextPage:self.trendingPaginator];
                }
            }
        }
    }
}


#pragma mark -
#pragma mark NMPaginatorDelegate

- (void)paginator:(id)paginator didReceiveResults:(NSArray *)results
{
    if(results.count != 10){
        self.trendingTableView.tableFooterView  = nil;
        [[ChatRoomStorage shared] setEndOfList:YES];
        //return;
    }
    // handle new results
        [_trendings addObjectsFromArray:results];
        _trendingDataSource.chatRooms = _trendings;
        [[ChatRoomStorage shared] setTrendingRooms:_trendings];
        [self.trendingActivityIndicator stopAnimating];
    
    [self updateTableViewFooterWithPaginator:paginator];
    //reload table
    [self.trendingTableView reloadData];
    [[NSNotificationCenter defaultCenter] postNotificationName:CAStateDataLoadedNotification object:nil userInfo:@{kTrendingRoomListLoaded:@YES}];
}

- (void)paginatorDidReset:(id)paginator
{
    [self.trendingTableView reloadData];
    [self.locationTableView reloadData];
    [self updateTableViewFooterWithPaginator:paginator];
}


#pragma mark -
#pragma mark Data Sources


- (TrendingChatRoomsDataSource *)trendingDataSource {
    if (!_trendingDataSource){
        _trendingDataSource = [TrendingChatRoomsDataSource new];
    }
    return _trendingDataSource;
}

- (LocalChatRoomsDataSource *)locationDataSource {
    if (!_locationDataSource){
        _locationDataSource = [LocalChatRoomsDataSource new];
    }
    return _locationDataSource;
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:kChatToChatRoomSegueIdentifier]){
        // passcurrent room to Chat Room controller
        ((ChatRoomViewController *)segue.destinationViewController).controllerName = self.tableName;
        ((ChatRoomViewController *)segue.destinationViewController).currentChatRoom = sender;
    }
}


#pragma mark -
#pragma mark Table View Delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self.searchBar resignFirstResponder];
    [self.searchBar setShowsCancelButton:NO animated:NO];
    // get current chat room
    QBCOCustomObject *currentRoom;
    if (tableView.tag == kTrendingTableViewTag) {
        self.tableName = @"Trending";
       currentRoom =  [_trendings objectAtIndex:[indexPath row]];
    } else if (tableView.tag == kLocalTableViewTag) {
        self.tableName = @"Local";
       currentRoom = [[[ChatRoomStorage shared] localRooms] objectAtIndex:[indexPath row]];
    }
    // Open CHat Controller
    [self performSegueWithIdentifier:kChatToChatRoomSegueIdentifier sender:currentRoom];
}


#pragma mark -
#pragma mark Table View Data Source

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"NewIdentifier"];
    return cell;
}


#pragma mark - 
#pragma mark Actions

- (IBAction)createChatRoom:(id)sender {
    [self performSegueWithIdentifier:kCreateChatRoomIdentifier sender:nil];
}

- (NSArray *)getNamesOfRooms:(NSArray *)rooms {
    NSMutableArray *names = [[NSMutableArray alloc] init];
    for (int i=0; i<[rooms count]; i++) {
        QBCOCustomObject *object = [rooms objectAtIndex:i];
        [names addObject:[object.fields objectForKey:kName]];
    }
    return names;
}

- (BOOL)alertViewShouldEnableFirstOtherButton:(UIAlertView *)alertView {
    return YES;
}


// distances for local rooms
- (NSMutableArray *)arrayOfDistances:(NSArray *)objects {
    NSMutableArray *chatRoomDistances = [NSMutableArray array];
    for (QBCOCustomObject *object in objects) {
        CLLocation *room = [[CLLocation alloc] initWithLatitude:[[[object fields] objectForKey:kLatitude] doubleValue] longitude:[[[object fields] objectForKey:kLongitude] doubleValue]];
        NSInteger distance = [[LocationService shared].myLocation distanceFromLocation:room];
        [chatRoomDistances addObject:[NSNumber numberWithInt:distance]];
    }
    return chatRoomDistances;
}

- (NSInteger)distanceFromNewRoom:(QBCOCustomObject *)room {
    CLLocation *newRoom = [[CLLocation alloc] initWithLatitude:[[[room fields] objectForKey:kLatitude] doubleValue] longitude:[[[room fields] objectForKey:kLongitude] doubleValue]];
    NSInteger distance = [[LocationService shared].myLocation distanceFromLocation:newRoom];
    return distance;
}


#pragma mark -
#pragma mark UISearchBar

- (UIView *)createSearchFooterView
{
    UIView *noResultsFoundView = [[UIView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, self.trendingTableView.frame.size.width, 88.0f)];
    noResultsFoundView.tag = kSearchresultsFooterTag;
    [noResultsFoundView setBackgroundColor:[UIColor clearColor]];
    
    UILabel *noResultsFoundLabel = [[UILabel alloc] initWithFrame:CGRectMake(0.0f, 0.0f, self.trendingTableView.frame.size.width, 44.0f)];
    noResultsFoundLabel.text = @"No results found";
    noResultsFoundLabel.backgroundColor = [UIColor clearColor];
    noResultsFoundLabel.textAlignment = NSTextAlignmentCenter;
    [noResultsFoundView addSubview:noResultsFoundLabel];
    
    UIButton *searchGlobalButton = [UIButton buttonWithType:UIButtonTypeSystem];
    searchGlobalButton.frame = CGRectMake(0.0f, 44.0f, self.trendingTableView.frame.size.width, 44.0f);
    searchGlobalButton.tag = kGlobalSearchFooterTag;
//    searchGlobalButton.titleLabel.textAlignment = NSTextAlignmentCenter;
//    searchGlobalButton.titleLabel.textColor = [UIColor blueColor];
    [searchGlobalButton setTitle:@"Global Search" forState:UIControlStateNormal];
    searchGlobalButton.backgroundColor = [UIColor clearColor];
    [searchGlobalButton addTarget:self action:@selector(globalSearch:) forControlEvents:UIControlEventTouchUpInside];
    [noResultsFoundView addSubview:searchGlobalButton];
    
    return noResultsFoundView;
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText
{
    self.trendings = [[ChatRoomStorage shared].trendingRooms mutableCopy];
    self.trendingDataSource.chatRooms = _trendings;
    self.trendingTableView.tableFooterView = nil;
    self.trendingFooterLabel.text = [NSString stringWithFormat:@"Load more..."];
    if (searchText.length == 0) {
        self.trendingTableView.tableFooterView = [self creatingTrendingFooter];
        [self.trendingTableView reloadData];
    } else {
        NSMutableArray *foundedFriends = [self searchText:searchText inArray:self.trendings];
        [self.trendings removeAllObjects];
        [self.trendings addObjectsFromArray:foundedFriends];
        if ([self.trendings count] == 0) {
            self.trendingTableView.tableFooterView = [self createSearchFooterView];
        }
        [self.trendingTableView reloadData];
    }
}

- (BOOL)searchingString:(NSString *)source inString:(NSString *)searchString
{
    NSString *sourceString = [source stringByReplacingOccurrencesOfString:@"  " withString:@" "];
    NSRange range = [sourceString rangeOfString:searchString options:NSCaseInsensitiveSearch];
    if (range.location == NSNotFound) {
        return NO;
    }
    return YES;
}

- (NSMutableArray *)searchText:(NSString *)text  inArray:(NSMutableArray *)array
{
    NSMutableArray *founded = [[NSMutableArray alloc] init];
    for (QBCOCustomObject *obj in array) {
        if ([self searchingString:obj.fields[kName] inString:text]) {
            [founded addObject:obj];
        }
    }
    return founded;
}

- (BOOL)searchBarShouldBeginEditing:(UISearchBar *)searchBar
{
    [searchBar setShowsCancelButton:YES animated:YES];
    return YES;
}

- (void)searchBarCancelButtonClicked:(UISearchBar *) searchBar
{
    if (self.trendingTableView.tableFooterView != nil) {
        self.trendingTableView.tableFooterView = nil;
        self.trendingTableView.tableFooterView = [self creatingTrendingFooter];
    } else {
        self.trendingTableView.tableFooterView = [self creatingTrendingFooter];
    }
    self.trendings = [[ChatRoomStorage shared].trendingRooms mutableCopy];
    self.trendingDataSource.chatRooms = _trendings;
    [searchBar setShowsCancelButton:NO animated:YES];
    [searchBar resignFirstResponder];
    self.trendingFooterLabel.text = @"Load more...";
    [self.trendingTableView reloadData];
}

- (IBAction)globalSearch:(id)sender
{
    NSMutableDictionary *extendedRequest = [[NSMutableDictionary alloc] init];
    [extendedRequest setObject:self.searchBar.text forKey:@"name[ctn]"];
    [QBCustomObjects objectsWithClassName:kChatRoom extendedRequest:extendedRequest delegate:[QBEchoObject instance] context:[QBEchoObject makeBlockForEchoObject:^(Result *result) {
        QBCOCustomObjectPagedResult *pagedResult = (QBCOCustomObjectPagedResult *)result;
        NSArray *searchedRooms = pagedResult.objects;
        [ChatRoomStorage shared].searchedRooms = searchedRooms;
        
        self.trendingTableView.tableFooterView = nil;
        self.trendings = [[ChatRoomStorage shared].searchedRooms mutableCopy];
        self.trendingDataSource.chatRooms = [ChatRoomStorage shared].searchedRooms;
        [self.trendingTableView reloadData];
        self.trendingFooterLabel.text = nil;
        
        if ([[ChatRoomStorage shared].searchedRooms count] == 0) {
            self.trendingTableView.tableFooterView = [self createSearchFooterView];
            UIView *noResultsView = [self.trendingTableView.tableFooterView viewWithTag:kSearchresultsFooterTag];
            UIButton *globalSearchButton = (UIButton *)[noResultsView viewWithTag:kGlobalSearchFooterTag];
            [globalSearchButton setHidden:YES];
        }
        [self.searchIndicatorView stopAnimating];
    }]];
    [self.searchIndicatorView startAnimating];
}

@end
