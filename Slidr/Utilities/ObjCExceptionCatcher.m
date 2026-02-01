#import "ObjCExceptionCatcher.h"

@implementation ObjCExceptionCatcher

+ (BOOL)catchException:(void(NS_NOESCAPE ^)(void))tryBlock error:(NSError * _Nullable __autoreleasing *)error {
    @try {
        tryBlock();
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            *error = [NSError errorWithDomain:exception.name
                                         code:0
                                     userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @""}];
        }
        return NO;
    }
}

@end
