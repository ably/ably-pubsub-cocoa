#import "ARTPushAdmin.h"
#import "ARTHttp.h"
#import "ARTHttpClient+Private.h"
#import "ARTPushDeviceRegistrations+Private.h"
#import "ARTPushChannelSubscriptions+Private.h"
#import "ARTInternalLog.h"
#import "ARTJsonEncoder.h"
#import "ARTJsonLikeEncoder.h"
#import "ARTGCD.h"

@implementation ARTPushAdmin {
    ARTQueuedDealloc *_dealloc;
}

- (instancetype)initWithInternal:(ARTPushAdminInternal *)internal queuedDealloc:(ARTQueuedDealloc *)dealloc {
    self = [super init];
    if (self) {
        _internal = internal;
        _dealloc = dealloc;
    }
    return self;
}

- (void)publish:(ARTPushRecipient *)recipient data:(ARTJsonObject *)data callback:(nullable ARTCallback)callback {
    [_internal publish:recipient data:data wrapperSDKAgents:nil callback:callback];
}

- (ARTPushDeviceRegistrations *)deviceRegistrations {
    return [[ARTPushDeviceRegistrations alloc] initWithInternal:_internal.deviceRegistrations queuedDealloc:_dealloc];
}

- (ARTPushChannelSubscriptions *)channelSubscriptions {
    return [[ARTPushChannelSubscriptions alloc] initWithInternal:_internal.channelSubscriptions queuedDealloc:_dealloc];
}

@end

@implementation ARTPushAdminInternal {
    __weak ARTHttpClientInternal *_rest; // weak because rest owns self
    ARTInternalLog *_logger;
    dispatch_queue_t _userQueue;
    dispatch_queue_t _queue;
}

- (instancetype)initWithRest:(ARTHttpClientInternal *)rest logger:(ARTInternalLog *)logger {
    if (self = [super init]) {
        _rest = rest;
        _logger = logger;
        _deviceRegistrations = [[ARTPushDeviceRegistrationsInternal alloc] initWithRest:rest logger:logger];
        _channelSubscriptions = [[ARTPushChannelSubscriptionsInternal alloc] initWithRest:rest logger:logger];
        _userQueue = rest.userQueue;
        _queue = rest.queue;
    }
    return self;
}

- (void)publish:(ARTPushRecipient *)recipient data:(ARTJsonObject *)data wrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents callback:(nullable ARTCallback)callback {
    if (callback) {
        ARTCallback userCallback = callback;
        callback = ^(ARTErrorInfo *error) {
            art_dispatch_async(self->_userQueue, ^{
                userCallback(error);
            });
        };
    }

    art_dispatch_async(_queue, ^{
            if (![[recipient allKeys] count]) {
                if (callback) callback([ARTErrorInfo createWithCode:0 message:@"Recipient is missing"]);
                return;
            }

            if (![[data allKeys] count]) {
                if (callback) callback([ARTErrorInfo createWithCode:0 message:@"Data payload is missing"]);
                return;
            }

            NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"/push/publish"]];
            request.HTTPMethod = @"POST";
            NSMutableDictionary *body = [NSMutableDictionary dictionary];
            [body setObject:recipient forKey:@"recipient"];
            [body addEntriesFromDictionary:data];
            request.HTTPBody = [[self->_rest defaultEncoder] encode:body error:nil];
            [request setValue:[[self->_rest defaultEncoder] mimeType] forHTTPHeaderField:@"Content-Type"];

            ARTLogDebug(self->_logger, @"push notification to a single device %@", request);
        [self->_rest executeRequest:request withAuthOption:ARTAuthenticationOn wrapperSDKAgents:wrapperSDKAgents completion:^(NSHTTPURLResponse *response, NSData *data, NSError *error) {
                if (error) {
                    ARTLogError(self->_logger, @"%@: push notification to a single device failed (%@)", NSStringFromClass(self.class), error.localizedDescription);
                    if (callback) callback([ARTErrorInfo createFromNSError:error]);
                    return;
                }
                if (callback) callback(nil);
            }];
    });
}

@end
