// ObjCExceptions.h — some Apple audio calls report problems by throwing an Objective-C
// exception, which Swift can't catch and which ends the app. This runs a block and
// turns such an exception into an NSError instead.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block`; returns NO and fills `error` if it threw an Objective-C exception.
BOOL VOACatchException(NS_NOESCAPE void (^block)(void), NSError * _Nullable * _Nullable error);

NS_ASSUME_NONNULL_END
