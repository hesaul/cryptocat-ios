//
//  TBMessageCell.h
//  ChatView
//
//  Created by Thomas Balthazar on 07/11/13.
//  Copyright (c) 2013 Thomas Balthazar. All rights reserved.
//

#import <UIKit/UIKit.h>

@protocol TBMessageCellDelegate;

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
@interface TBMessageCell : UITableViewCell

@property (nonatomic, weak) id <TBMessageCellDelegate> delegate;
@property (nonatomic, strong) NSString *senderName;
@property (nonatomic, strong) NSString *message;
@property (nonatomic, strong) NSString *warningMessage;
@property (nonatomic, assign, getter=isMeSpeaking) BOOL meSpeaking;
@property (nonatomic, assign) BOOL isErrorMessage;

+ (CGFloat)heightForCellWithSenderName:(NSString *)senderName
                                  text:(NSString *)text
                           warningText:(NSString *)warningText;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
@protocol TBMessageCellDelegate <NSObject>

- (BOOL)messageCell:(TBMessageCell *)cell
shouldInteractWithURL:(NSURL *)URL
            inRange:(NSRange)characterRange;

@end