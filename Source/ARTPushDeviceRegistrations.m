#import "ARTPushDeviceRegistrations+Private.h"
#import "ARTHTTPExecutor.h"
#import "ARTInternalLog.h"
#import "ARTPaginatedResult+Private.h"
#import "ARTDeviceDetails.h"
#import "ARTDevicePushDetails.h"
#import "ARTDeviceIdentityTokenDetails.h"
#import "ARTClientOptions.h"
#import "ARTEncoder.h"
#import "ARTHttpClient+Private.h"
#import "ARTLocalDevice.h"
#import "ARTNSMutableRequest+ARTPush.h"
#import "ARTGCD.h"

@implementation ARTPushDeviceRegistrations {
    ARTQueuedDealloc *_dealloc;
}

- (instancetype)initWithInternal:(ARTPushDeviceRegistrationsInternal *)internal queuedDealloc:(ARTQueuedDealloc *)dealloc {
    self = [super init];
    if (self) {
        _internal = internal;
        _dealloc = dealloc;
    }
    return self;
}

- (void)save:(ARTDeviceDetails *)deviceDetails callback:(ARTCallback)callback {
    [_internal save:deviceDetails wrapperSDKAgents:nil callback:callback];
}

- (void)get:(ARTDeviceId *)deviceId callback:(void (^)(ARTDeviceDetails *_Nullable,  ARTErrorInfo *_Nullable))callback {
    [_internal get:deviceId wrapperSDKAgents:nil callback:callback];
}

- (void)list:(NSStringDictionary *)params callback:(ARTPaginatedDeviceDetailsCallback)callback {
    [_internal list:params wrapperSDKAgents:nil callback:callback];
}

- (void)remove:(NSString *)deviceId callback:(ARTCallback)callback {
    [_internal remove:deviceId wrapperSDKAgents:nil callback:callback];
}

- (void)removeWhere:(NSStringDictionary *)params callback:(ARTCallback)callback {
    [_internal removeWhere:params wrapperSDKAgents:nil callback:callback];
}

@end

@implementation ARTPushDeviceRegistrationsInternal {
    __weak ARTHttpClientInternal *_rest; // weak because rest owns self
    ARTInternalLog *_logger;
    dispatch_queue_t _queue;
    dispatch_queue_t _userQueue;
}

- (instancetype)initWithRest:(ARTHttpClientInternal *)rest logger:(ARTInternalLog *)logger {
    if (self = [super init]) {
        _rest = rest;
        _logger = logger;
        _queue = rest.queue;
        _userQueue = rest.userQueue;
    }
    return self;
}

- (void)save:(ARTDeviceDetails *)deviceDetails wrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents callback:(ARTCallback)callback {
    if (callback) {
        ARTCallback userCallback = callback;
        callback = ^(ARTErrorInfo *error) {
            art_dispatch_async(self->_userQueue, ^{
                userCallback(error);
            });
        };
    }

    #if TARGET_OS_IOS
    ARTLocalDevice *local = _rest.device;
    #else
    ARTLocalDevice *local = nil;
    #endif

art_dispatch_async(_queue, ^{
    NSURLComponents *components = [[NSURLComponents alloc] initWithURL:[[NSURL URLWithString:@"/push/deviceRegistrations"] URLByAppendingPathComponent:deviceDetails.id] resolvingAgainstBaseURL:NO];
    if (self->_rest.options.pushFullWait) {
        components.queryItems = @[[NSURLQueryItem queryItemWithName:@"fullWait" value:@"true"]];
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[components URL]];
    request.HTTPMethod = @"PUT";
    request.HTTPBody = [[self->_rest defaultEncoder] encodeDeviceDetails:deviceDetails error:nil];
    [request setValue:[[self->_rest defaultEncoder] mimeType] forHTTPHeaderField:@"Content-Type"];
    [request setDeviceAuthentication:deviceDetails.id localDevice:local logger:self->_logger];

    ARTLogDebug(self->_logger, @"save device with request %@", request);
    [self->_rest executeRequest:request withAuthOption:ARTAuthenticationOn wrapperSDKAgents:wrapperSDKAgents completion:^(NSHTTPURLResponse *response, NSData *data, NSError *error) {
        if (response.statusCode == 200 /*OK*/) {
            NSError *decodeError = nil;
            ARTDeviceDetails *deviceDetails = [[self->_rest defaultEncoder] decodeDeviceDetails:data error:&decodeError];
            if (decodeError) {
                ARTLogDebug(self->_logger, @"%@: decode device failed (%@)", NSStringFromClass(self.class), error.localizedDescription);
                callback([ARTErrorInfo createFromNSError:decodeError]);
            }
            else {
                ARTLogDebug(self->_logger, @"%@: successfully saved device %@", NSStringFromClass(self.class), deviceDetails.id);
                callback(nil);
            }
        }
        else if (error) {
            ARTLogError(self->_logger, @"%@: save device failed (%@)", NSStringFromClass(self.class), error.localizedDescription);
            callback([ARTErrorInfo createFromNSError:error]);
        }
        else {
            ARTLogError(self->_logger, @"%@: save device failed with status code %ld", NSStringFromClass(self.class), (long)response.statusCode);
            NSString *plain = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            callback([ARTErrorInfo createWithCode:response.statusCode*100 status:response.statusCode message:[plain art_shortString]]);
        }
    }];
});
}

- (void)get:(ARTDeviceId *)deviceId wrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents callback:(void (^)(ARTDeviceDetails *, ARTErrorInfo *))callback {
    if (callback) {
        void (^userCallback)(ARTDeviceDetails *, ARTErrorInfo *error) = callback;
        callback = ^(ARTDeviceDetails *device, ARTErrorInfo *error) {
            art_dispatch_async(self->_userQueue, ^{
                userCallback(device, error);
            });
        };
    }

    #if TARGET_OS_IOS
    ARTLocalDevice *local = _rest.device;
    #else
    ARTLocalDevice *local = nil;
    #endif

art_dispatch_async(_queue, ^{
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[[NSURL URLWithString:@"/push/deviceRegistrations"] URLByAppendingPathComponent:deviceId]];
    request.HTTPMethod = @"GET";
    [request setDeviceAuthentication:deviceId localDevice:local logger:self->_logger];

    ARTLogDebug(self->_logger, @"get device with request %@", request);
    [self->_rest executeRequest:request withAuthOption:ARTAuthenticationOn wrapperSDKAgents:wrapperSDKAgents completion:^(NSHTTPURLResponse *response, NSData *data, NSError *error) {
        if (response.statusCode == 200 /*OK*/) {
            NSError *decodeError = nil;
            ARTDeviceDetails *device = [self->_rest.encoders[response.MIMEType] decodeDeviceDetails:data error:&decodeError];
            if (decodeError) {
                ARTLogDebug(self->_logger, @"%@: decode device failed (%@)", NSStringFromClass(self.class), error.localizedDescription);
                callback(nil, [ARTErrorInfo createFromNSError:decodeError]);
            }
            else if (device) {
                ARTLogDebug(self->_logger, @"%@: get device successfully", NSStringFromClass(self.class));
                callback(device, nil);
            }
            else {
                ARTLogDebug(self->_logger, @"%@: get device failed with unknown error", NSStringFromClass(self.class));
                callback(nil, [ARTErrorInfo createUnknownError]);
            }
        }
        else if (error) {
            ARTLogError(self->_logger, @"%@: get device failed (%@)", NSStringFromClass(self.class), error.localizedDescription);
            callback(nil, [ARTErrorInfo createFromNSError:error]);
        }
        else {
            ARTLogError(self->_logger, @"%@: get device failed with status code %ld", NSStringFromClass(self.class), (long)response.statusCode);
            NSString *plain = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            callback(nil, [ARTErrorInfo createWithCode:response.statusCode*100 status:response.statusCode message:[plain art_shortString]]);
        }
    }];
});
}

- (void)list:(NSStringDictionary *)params wrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents callback:(ARTPaginatedDeviceDetailsCallback)callback {
    if (callback) {
        void (^userCallback)(ARTPaginatedResult *, ARTErrorInfo *error) = callback;
        callback = ^(ARTPaginatedResult *result, ARTErrorInfo *error) {
            art_dispatch_async(self->_userQueue, ^{
                userCallback(result, error);
            });
        };
    }

art_dispatch_async(_queue, ^{
    NSURLComponents *components = [[NSURLComponents alloc] initWithURL:[NSURL URLWithString:@"/push/deviceRegistrations"] resolvingAgainstBaseURL:NO];
    components.queryItems = [params art_asURLQueryItems];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[components URL]];
    request.HTTPMethod = @"GET";

    ARTPaginatedResultResponseProcessor responseProcessor = ^(NSHTTPURLResponse *response, NSData *data, NSError **error) {
        return [self->_rest.encoders[response.MIMEType] decodeDevicesDetails:data error:error];
    };
    [ARTPaginatedResult executePaginated:self->_rest withRequest:request andResponseProcessor:responseProcessor wrapperSDKAgents:wrapperSDKAgents logger:self->_logger callback:callback];
});
}

- (void)remove:(NSString *)deviceId wrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents callback:(ARTCallback)callback {
    if (callback) {
        ARTCallback userCallback = callback;
        callback = ^(ARTErrorInfo *error) {
            art_dispatch_async(self->_userQueue, ^{
                userCallback(error);
            });
        };
    }

art_dispatch_async(_queue, ^{
    NSURLComponents *components = [[NSURLComponents alloc] initWithURL:[[NSURL URLWithString:@"/push/deviceRegistrations"] URLByAppendingPathComponent:deviceId] resolvingAgainstBaseURL:NO];
        if (self->_rest.options.pushFullWait) {
        components.queryItems = @[[NSURLQueryItem queryItemWithName:@"fullWait" value:@"true"]];
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[components URL]];
    request.HTTPMethod = @"DELETE";
    [request setValue:[[self->_rest defaultEncoder] mimeType] forHTTPHeaderField:@"Content-Type"];

    ARTLogDebug(self->_logger, @"remove device with request %@", request);
    [self->_rest executeRequest:request withAuthOption:ARTAuthenticationOn wrapperSDKAgents:wrapperSDKAgents completion:^(NSHTTPURLResponse *response, NSData *data, NSError *error) {
        if (response.statusCode == 200 /*Ok*/ || response.statusCode == 204 /*not returning any content*/) {
            ARTLogDebug(self->_logger, @"%@: save device successfully", NSStringFromClass(self.class));
            callback(nil);
        }
        else if (error) {
            ARTLogError(self->_logger, @"%@: remove device failed (%@)", NSStringFromClass(self.class), error.localizedDescription);
            callback([ARTErrorInfo createFromNSError:error]);
        }
        else {
            ARTLogError(self->_logger, @"%@: remove device failed with status code %ld", NSStringFromClass(self.class), (long)response.statusCode);
            NSString *plain = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            callback([ARTErrorInfo createWithCode:response.statusCode*100 status:response.statusCode message:[plain art_shortString]]);
        }
    }];
});
}

- (void)removeWhere:(NSStringDictionary *)params wrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents callback:(ARTCallback)callback {
    if (callback) {
        ARTCallback userCallback = callback;
        callback = ^(ARTErrorInfo *error) {
            art_dispatch_async(self->_userQueue, ^{
                userCallback(error);
            });
        };
    }

    #if TARGET_OS_IOS
    ARTLocalDevice *local = _rest.device;
    #else
    ARTLocalDevice *local = nil;
    #endif

art_dispatch_async(_queue, ^{
    NSURLComponents *components = [[NSURLComponents alloc] initWithURL:[NSURL URLWithString:@"/push/deviceRegistrations"] resolvingAgainstBaseURL:NO];
    components.queryItems = [params art_asURLQueryItems];
    if (self->_rest.options.pushFullWait) {
        components.queryItems = [components.queryItems arrayByAddingObject:[NSURLQueryItem queryItemWithName:@"fullWait" value:@"true"]];
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[components URL]];
    request.HTTPMethod = @"DELETE";
    [request setDeviceAuthentication:[params objectForKey:@"deviceId"] localDevice:local];

    ARTLogDebug(self->_logger, @"remove devices with request %@", request);
    [self->_rest executeRequest:request withAuthOption:ARTAuthenticationOn wrapperSDKAgents:wrapperSDKAgents completion:^(NSHTTPURLResponse *response, NSData *data, NSError *error) {
        if (response.statusCode == 200 /*Ok*/ || response.statusCode == 204 /*not returning any content*/) {
            ARTLogDebug(self->_logger, @"%@: remove devices successfully", NSStringFromClass(self.class));
            callback(nil);
        }
        else if (error) {
            ARTLogError(self->_logger, @"%@: remove devices failed (%@)", NSStringFromClass(self.class), error.localizedDescription);
            callback([ARTErrorInfo createFromNSError:error]);
        }
        else {
            ARTLogError(self->_logger, @"%@: remove devices failed with status code %ld", NSStringFromClass(self.class), (long)response.statusCode);
            NSString *plain = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            callback([ARTErrorInfo createWithCode:response.statusCode*100 status:response.statusCode message:[plain art_shortString]]);
        }
    }];
});
}

@end
