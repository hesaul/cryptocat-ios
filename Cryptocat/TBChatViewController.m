//
//  TBChatViewController.m
//  Cryptocat
//
//  Created by Thomas Balthazar on 16/10/13.
//  Copyright (c) 2013 Thomas Balthazar. All rights reserved.
//

#import "TBChatViewController.h"
#import "TBXMPPMessagesHandler.h"
#import "TBBuddiesViewController.h"
#import "TBMeViewController.h"
#import "TBBuddy.h"
#import "TBMessageCell.h"
#import "TBChatToolbarView.h"
#import "UIColor+Cryptocat.h"

#define kPausedMessageTimer   5.0
#define kTableViewPaddingTop  17.0

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
@interface TBChatViewController () <
  UITableViewDataSource,
  UITableViewDelegate,
  TBBuddiesViewControllerDelegate,
  TBMeViewControllerDelegate,
  UITextViewDelegate
>

@property (weak, nonatomic) IBOutlet UITableView *tableView;
@property (weak, nonatomic) IBOutlet TBChatToolbarView *toolbarView;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *toolbarViewBottomConstraint;
@property (nonatomic, strong) NSMutableDictionary *messagesForConversation;
@property (nonatomic, strong) NSString *currentRoomName;
@property (nonatomic, strong) TBBuddy *currentRecipient;
@property (strong, readwrite) NSTimer *composingTimer;
@property (nonatomic, assign, getter=isTyping) BOOL typing;
@property (nonatomic, assign) NSUInteger nbUnreadMessagesInRoom;
@property (nonatomic, strong) NSMutableDictionary *nbUnreadMessagesForBuddy;
@property (nonatomic, strong) NSString *defaultNavLeftItemTitle;

- (void)startObservingKeyboard;
- (void)stopObservingKeyboard;
- (IBAction)sendMessage:(id)sender;
- (BOOL)isInConversationRoom;
- (void)setupTypingTimer;
- (void)cancelTypingTimer;
- (void)didStartComposing;
- (void)didPauseComposing;
- (void)didEndComposing;
- (void)updateUnreadMessagesCounter;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
@implementation TBChatViewController

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Lifecycle

////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)dealloc {
  NSNotificationCenter *defaultCenter = [NSNotificationCenter defaultCenter];
  [defaultCenter removeObserver:self name:TBDidReceiveGroupChatMessageNotification object:nil];
  [defaultCenter removeObserver:self name:TBDidReceivePrivateChatMessageNotification object:nil];
  [defaultCenter removeObserver:self name:TBBuddyDidSignInNotification object:nil];
  [defaultCenter removeObserver:self name:TBBuddyDidSignOutNotification object:nil];
}

////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)didReceiveMemoryWarning {
  [super didReceiveMemoryWarning];
  // Dispose of any resources that can be recreated.
}

////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)viewDidLoad {
  [super viewDidLoad];
	 
  self.defaultNavLeftItemTitle = NSLocalizedString(@"Buddies",
                                                   @"Buddies Button Title on Chat Screen");
  self.navigationItem.leftBarButtonItem.title = self.defaultNavLeftItemTitle;
  self.navigationItem.rightBarButtonItem.title = NSLocalizedString(@"Me",
                                                                @"Me Button Title on Chat Screen");
  
  
  self.typing = NO;
  self.messagesForConversation = [NSMutableDictionary dictionary];
  self.nbUnreadMessagesInRoom = 0;
  self.nbUnreadMessagesForBuddy = [NSMutableDictionary dictionary];
  
  self.view.backgroundColor = [UIColor tb_backgroundColor];
  self.tableView.backgroundColor = self.view.backgroundColor;
  self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
  self.tableView.contentInset = UIEdgeInsetsMake(kTableViewPaddingTop, 0.0, 0.0, 0.0);

  self.toolbarView.textView.delegate = self;
  [self.toolbarView.sendButton addTarget:self
                                  action:@selector(sendMessage:)
                        forControlEvents:UIControlEventTouchUpInside];

  NSNotificationCenter *defaultCenter = [NSNotificationCenter defaultCenter];
  [defaultCenter addObserver:self
                    selector:@selector(didReceiveGroupMessage:)
                        name:TBDidReceiveGroupChatMessageNotification
                      object:nil];
  [defaultCenter addObserver:self
                    selector:@selector(didReceivePrivateMessage:)
                        name:TBDidReceivePrivateChatMessageNotification
                      object:nil];
  [defaultCenter addObserver:self
                    selector:@selector(buddyDidChangeState:)
                        name:TBBuddyDidSignInNotification
                      object:nil];
  [defaultCenter addObserver:self
                    selector:@selector(buddyDidChangeState:)
                        name:TBBuddyDidSignOutNotification
                      object:nil];
}

////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];

  // the first time the view appears, after the loginVC is dismissed
  if (self.currentRoomName==nil) {
    self.currentRoomName = self.roomName;
    self.title = self.roomName;
  }
  
  [self startObservingKeyboard];
  TBLOGMARK;
}

////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)viewWillDisappear:(BOOL)animated {
  [super viewWillDisappear:animated];
  
  [self stopObservingKeyboard];
  TBLOGMARK;
}

////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
  // -- buddies
  if ([segue.identifier isEqualToString:@"BuddiesSegueID"]) {
    UINavigationController *nc = segue.destinationViewController;
    TBBuddiesViewController *bvc = (TBBuddiesViewController *)nc.topViewController;
    bvc.delegate = self;
    bvc.roomName = self.roomName;
    bvc.buddies = self.buddies;
    bvc.nbUnreadMessagesInRoom = self.nbUnreadMessagesInRoom;
    bvc.nbUnreadMessagesForBuddy = self.nbUnreadMessagesForBuddy;
  }
  
  // -- me
  else if ([segue.identifier isEqualToString:@"MeSegueID"]) {
    UINavigationController *nc = segue.destinationViewController;
    TBMeViewController *mvc = (TBMeViewController *)nc.topViewController;
    mvc.delegate = self;
    mvc.me = self.me;
  }
}

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark UITableViewDataSource

////////////////////////////////////////////////////////////////////////////////////////////////////
- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  static NSString *cellID = @"MessageCellID";
  TBMessageCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
  if (cell == nil) {
    [tableView registerClass:[TBMessageCell class] forCellReuseIdentifier:cellID];
    cell = [[TBMessageCell alloc] initWithStyle:UITableViewCellStyleDefault
                                reuseIdentifier:cellID];
  }

  NSMutableArray *messages = [self.messagesForConversation objectForKey:self.currentRoomName];
  
  cell.senderName = @"balky";
  cell.meSpeaking = YES;
  cell.message = [messages objectAtIndex:indexPath.row];
  cell.backgroundColor = self.tableView.backgroundColor;

  return cell;
}

////////////////////////////////////////////////////////////////////////////////////////////////////
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  NSMutableArray *messages = [self.messagesForConversation objectForKey:self.currentRoomName];
  return [messages count];
}

////////////////////////////////////////////////////////////////////////////////////////////////////
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
  return [TBMessageCell heightForCellWithText:
    [[self.messagesForConversation objectForKey:self.currentRoomName] objectAtIndex:indexPath.row]];
}

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark UITableViewDelegate

////////////////////////////////////////////////////////////////////////////////////////////////////
- (NSIndexPath *)tableView:(UITableView *)tableView
  willSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  return nil;
}

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Observers

////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)didReceiveGroupMessage:(NSNotification *)notification {
  NSString *roomName = notification.object;
  NSString *message = [notification.userInfo objectForKey:@"message"];
  NSString *sender = [notification.userInfo objectForKey:@"sender"];
  
  NSString *receivedMessage = [NSString stringWithFormat:@"%@ : %@", sender, message];
  
  if ([self.messagesForConversation objectForKey:roomName]==nil) {
    [self.messagesForConversation setObject:[NSMutableArray array] forKey:roomName];
  }

  [[self.messagesForConversation objectForKey:roomName] addObject:receivedMessage];
  
  if ([self isInConversationRoom]) {
    [self.tableView reloadData];
  }
  else {
    self.nbUnreadMessagesInRoom+=1;
    [self updateUnreadMessagesCounter];
  }
  TBLOG(@"-- received message in %@ from %@: %@", roomName, sender, message);
}

////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)didReceivePrivateMessage:(NSNotification *)notification {
  NSString *message = [notification.userInfo objectForKey:@"message"];
  if ([message isEqualToString:@""]) return ;
  
  TBBuddy *sender = notification.object;
  NSString *receivedMessage = [NSString stringWithFormat:@"%@ : %@", self.title, message];
  
  if ([self.messagesForConversation objectForKey:sender.fullname]==nil) {
    [self.messagesForConversation setObject:[NSMutableArray array] forKey:sender.fullname];
  }
  
  [[self.messagesForConversation objectForKey:sender.fullname] addObject:receivedMessage];
  
  if (![self isInConversationRoom] && [self.currentRecipient isEqual:sender]) {
    [self.tableView reloadData];
  }
  else {
    NSString *buddyName = sender.fullname;
    NSInteger nbUnreadMessages = [[self.nbUnreadMessagesForBuddy objectForKey:buddyName]
                                  integerValue];
    nbUnreadMessages+=1;
    [self.nbUnreadMessagesForBuddy setObject:[NSNumber numberWithInteger:nbUnreadMessages]
                                      forKey:buddyName];
    [self updateUnreadMessagesCounter];
  }
  
  TBLOG(@"-- received private message from %@: %@", sender.fullname, message);
}

////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)buddyDidChangeState:(NSNotification *)notification {
  TBBuddy *buddy = notification.object;
  
  if ([self.currentRecipient isEqual:buddy]) {
    BOOL isSignIn = [notification.name isEqualToString:TBBuddyDidSignInNotification];
    self.toolbarView.textView.backgroundColor = isSignIn ?
                                                  [UIColor whiteColor] : [UIColor redColor];
    self.toolbarView.textView.editable = isSignIn;
  }
}

////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)keyboardWillShow:(NSNotification *)notification {
  NSDictionary* info = [notification userInfo];
  CGSize keyboardSize = [[info objectForKey:UIKeyboardFrameBeginUserInfoKey] CGRectValue].size;
  
  // get the keyboard height depending on the device orientation
  UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
  BOOL isPortrait = orientation==UIInterfaceOrientationPortrait;
  CGFloat keyboardHeight = isPortrait ? keyboardSize.height : keyboardSize.width;
  
  // get the animation info
  double keyboardTransitionDuration;
  [[notification.userInfo valueForKey:UIKeyboardAnimationDurationUserInfoKey]
   getValue:&keyboardTransitionDuration];
  UIViewAnimationCurve keyboardTransitionAnimationCurve;
  [[notification.userInfo valueForKey:UIKeyboardAnimationCurveUserInfoKey]
   getValue:&keyboardTransitionAnimationCurve];
  
  // update the toolbarView constraints
  self.toolbarViewBottomConstraint.constant = keyboardHeight;
  
  // start animation
  [UIView beginAnimations:nil context:NULL];
  [UIView setAnimationDuration:keyboardTransitionDuration];
  [UIView setAnimationCurve:keyboardTransitionAnimationCurve];
  [UIView setAnimationBeginsFromCurrentState:YES];
  
  [self.view layoutIfNeeded];
  
  [UIView commitAnimations];
  // end animation
}

////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)keyboardWillBeHidden:(NSNotification *)notification {
  NSDictionary* info = [notification userInfo];
  CGSize keyboardSize = [[info objectForKey:UIKeyboardFrameBeginUserInfoKey] CGRectValue].size;
  
  // get the keyboard height depending on the device orientation
  UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
  BOOL isPortrait = orientation==UIInterfaceOrientationPortrait;
  CGFloat keyboardHeight = isPortrait ? keyboardSize.height : keyboardSize.width;
  
  // update the toolbarView constraints
  self.toolbarViewBottomConstraint.constant = keyboardHeight;
  
  [self.view layoutIfNeeded];
}

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Private Methods

////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)startObservingKeyboard {
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(keyboardWillShow:)
                                               name:UIKeyboardWillShowNotification
                                             object:nil];
  
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(keyboardWillBeHidden:)
                                               name:UIKeyboardWillHideNotification
                                             object:nil];
}

////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)stopObservingKeyboard {
  [[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:UIKeyboardWillShowNotification
                                                object:nil];
  [[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:UIKeyboardWillHideNotification
                                                object:nil];
}

////////////////////////////////////////////////////////////////////////////////////////////////////
- (BOOL)isInConversationRoom {
  return [self.roomName isEqualToString:self.currentRoomName];
}

////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)setupTypingTimer {
  [self cancelTypingTimer];
  TBLOG(@"-- starting the timer");
  self.composingTimer = [NSTimer scheduledTimerWithTimeInterval:kPausedMessageTimer
                                                         target:self
                                                       selector:@selector(typingDidPause)
                                                       userInfo:nil
                                                        repeats:NO];
}

////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)cancelTypingTimer {
  if (self.composingTimer) {
    TBLOG(@"-- cancelling the timer");
    [self.composingTimer invalidate];
    self.composingTimer = nil;
  }
}

////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)didStartComposing {
  self.typing = YES;
  if ([self.delegate
       respondsToSelector:@selector(chatViewControllerDidStartComposing:forRecipient:)]) {
    [self.delegate chatViewControllerDidStartComposing:self forRecipient:self.currentRecipient];
  }
}

////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)didPauseComposing {
  self.typing = NO;
  if ([self.delegate
       respondsToSelector:@selector(chatViewControllerDidPauseComposing:forRecipient:)]) {
    [self.delegate chatViewControllerDidPauseComposing:self forRecipient:self.currentRecipient];
  }
}

////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)didEndComposing {
  self.typing = NO;
  if ([self.delegate
       respondsToSelector:@selector(chatViewControllerDidEndComposing:forRecipient:)]) {
    [self.delegate chatViewControllerDidEndComposing:self forRecipient:self.currentRecipient];
  }
}

////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)updateUnreadMessagesCounter {
  NSInteger totalUnreadMSGCount = self.nbUnreadMessagesInRoom;
  TBLOG(@"-- self.nbUnreadMessagesInRoom : %d", self.nbUnreadMessagesInRoom);
  for (NSString *buddyName in self.nbUnreadMessagesForBuddy) {
    NSNumber *nbUnreadMessages = [self.nbUnreadMessagesForBuddy objectForKey:buddyName];
    totalUnreadMSGCount+=[nbUnreadMessages integerValue];
    TBLOG(@"-- nb unread msgs for %@ : %d", buddyName, [nbUnreadMessages integerValue]);
  }
  
  if (totalUnreadMSGCount==0) {
    self.navigationItem.leftBarButtonItem.title = self.defaultNavLeftItemTitle;
  }
  else {
    self.navigationItem.leftBarButtonItem.title = [NSString stringWithFormat:@"%@ (%d)",
                                                   self.defaultNavLeftItemTitle,
                                                   totalUnreadMSGCount];
  }
}

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Actions

////////////////////////////////////////////////////////////////////////////////////////////////////
- (IBAction)sendMessage:(id)sender {
  NSString *message = self.toolbarView.textView.text;
  
  if ([self.messagesForConversation objectForKey:self.currentRoomName]==nil) {
    [self.messagesForConversation setObject:[NSMutableArray array] forKey:self.currentRoomName];
  }

  [[self.messagesForConversation objectForKey:self.currentRoomName] addObject:message];
  [self.tableView reloadData];
  self.toolbarView.textView.text = @"";
  
  [self cancelTypingTimer];
  
  // group chat message
  if ([self isInConversationRoom]) {
    if ([self.delegate respondsToSelector:@selector(chatViewController:didAskToSendMessage:)]) {
      [self.delegate chatViewController:self didAskToSendMessage:message];
    }
  }
  // private chat message
  else {
    if ([self.delegate
         respondsToSelector:@selector(chatViewController:didAskToSendMessage:toUser:)]) {
      [self.delegate chatViewController:self
                    didAskToSendMessage:message
                                 toUser:self.currentRecipient];
    }
  }
}

////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)typingDidPause {
  TBLOG(@"-- timer fired");
  [self cancelTypingTimer];
  [self didPauseComposing];
}

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark TBBuddiesViewControllerDelegate

////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)buddiesViewControllerHasFinished:(TBBuddiesViewController *)controller {
  [self dismissViewControllerAnimated:YES completion:NULL];
}

////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)buddiesViewController:(TBBuddiesViewController *)controller
            didSelectRoomName:(NSString *)roomName {
  self.title = roomName;
  self.currentRoomName = roomName;
  self.currentRecipient = nil;
  self.nbUnreadMessagesInRoom = 0;
  [self dismissViewControllerAnimated:YES completion:^{
    [self.tableView reloadData];
    [self updateUnreadMessagesCounter];
  }];
}

////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)buddiesViewController:(TBBuddiesViewController *)controller
               didSelectBuddy:(TBBuddy *)buddy {
  self.title = buddy.nickname;
  self.currentRoomName = buddy.fullname;
  self.currentRecipient = buddy;
  [self.nbUnreadMessagesForBuddy setObject:[NSNumber numberWithInt:0] forKey:buddy.fullname];
  [self dismissViewControllerAnimated:YES completion:^{
    [self.tableView reloadData];
    [self updateUnreadMessagesCounter];
  }];
}

////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)buddiesViewController:(TBBuddiesViewController *)controller
   didAskFingerprintsForBuddy:(TBBuddy *)buddy {
  if ([self.delegate
       respondsToSelector:@selector(chatViewController:didAskFingerprintsForBuddy:)]) {
    [self.delegate chatViewController:self didAskFingerprintsForBuddy:buddy];
  }
}

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark TBMeViewControllerDelegate

////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)meViewControllerHasFinished:(TBMeViewController *)controller {
  [self dismissViewControllerAnimated:YES completion:NULL];
}

////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)meViewControllerDidAskToLogout:(TBMeViewController *)controller {
  if ([self.delegate respondsToSelector:@selector(chatViewControllerDidAskToLogout:)]) {
    [self dismissViewControllerAnimated:NO completion:^{
      [self.delegate chatViewControllerDidAskToLogout:self];
    }];
  }
}

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark UITextViewDelegate

////////////////////////////////////////////////////////////////////////////////////////////////////
- (BOOL)textView:(UITextView *)textView
shouldChangeTextInRange:(NSRange)range
 replacementText:(NSString *)text {
  NSUInteger oldLength = textView.text.length;
  NSUInteger newLength = textView.text.length + text.length - range.length;
  
  // if there's a string in the input field
  if (newLength > 0) {
    // if there wasn't a string in the input field before or typing had paused
    if (oldLength==0  || !self.isTyping) {
      TBLOG(@"-- composing");
      [self didStartComposing];
    }
    
    // start/restart timer
    [self setupTypingTimer];
  }
  else {
    // all the chars in the input field have been deleted
    TBLOG(@"-- active");
    [self cancelTypingTimer];
    [self didEndComposing];
  }
  
  return YES;
}


@end
