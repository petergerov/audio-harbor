#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block` and converts thrown NSExceptions into an NSError.
/// AVAudioEngine.connect can raise ObjC exceptions (e.g. -10868) that Swift cannot catch.
FOUNDATION_EXPORT BOOL AHPerformWithExceptionHandling(NS_NOESCAPE void (^block)(void), NSError * _Nullable * _Nullable outError);

NS_ASSUME_NONNULL_END
