#import "AHExceptionCatcher.h"

BOOL AHPerformWithExceptionHandling(NS_NOESCAPE void (^block)(void), NSError * _Nullable * _Nullable outError) {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (outError != NULL) {
            NSMutableDictionary *info = [NSMutableDictionary dictionary];
            if (exception.reason != nil) {
                info[NSLocalizedDescriptionKey] = exception.reason;
            } else {
                info[NSLocalizedDescriptionKey] = @"Audio engine exception";
            }
            if (exception.name != nil) {
                info[@"exception.name"] = exception.name;
            }
            *outError = [NSError errorWithDomain:@"app.audioharbor.exception"
                                            code:1
                                        userInfo:info];
        }
        return NO;
    }
}
