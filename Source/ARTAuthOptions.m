#import "ARTAuthOptions+Private.h"
#import "ARTTokenDetails.h"
#import "ARTStatus.h"

@implementation ARTAuthOptions

NSString *const ARTAuthOptionsMethodDefault = @"GET";

- (instancetype)init {
    self = [super init];
    if (self) {
        return [self initDefaults];
    }
    return self;
}

- (instancetype)initWithKey:(NSString *)key {
    self = [super init];
    if (self) {
        if (key != nil && decomposeKey(key).count != 2) {
            [ARTException raise:@"Invalid key" format:@"%@ should be of the form <keyName>:<keySecret>", key];
        }
        else if (key != nil) {
            _key = [key copy];
        }
        return [self initDefaults];
    }
    return self;
}

- (instancetype)initWithToken:(NSString *)token {
    self = [super init];
    if (self) {
        [self setToken:token];
        return [self initDefaults];
    }
    return self;
}

- (instancetype)initWithTokenDetails:(ARTTokenDetails *)tokenDetails {
    self = [super init];
    if (self) {
        _tokenDetails = tokenDetails;
        return [self initDefaults];
    }
    return self;
}

- (instancetype)initDefaults {
    _authMethod = ARTAuthOptionsMethodDefault;
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    ARTAuthOptions *options = [[[self class] allocWithZone:zone] init];

    options.key = self.key;
    options.token = self.token;
    options.tokenDetails = self.tokenDetails;
    options.authCallback = self.authCallback;
    options.authUrl = self.authUrl;
    options.authMethod = self.authMethod;
    options.authHeaders = self.authHeaders;
    options.authParams = self.authParams;
    options.queryTime = self.queryTime;
    options.useTokenAuth = self.useTokenAuth;

    return options;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%@ - \n\t key: %@; \n\t token: %@; \n\t authUrl: %@; \n\t authMethod: %@; \n\t hasAuthCallback: %d;", [super description], self.key, self.token, self.authUrl, self.authMethod, self.authCallback != nil];
}

- (NSString *)token {
    if (self.tokenDetails) {
        return self.tokenDetails.token;
    }
    return nil;
}

- (void)setToken:(NSString *)token {
    if (token && ![token isEqualToString:@""]) {
        self.tokenDetails = [[ARTTokenDetails alloc] initWithToken:token];
    }
}

- (void)setAuthMethod:(NSString *)authMethod {
    // HTTP Method
    if (authMethod == nil || authMethod.length == 0) {
        authMethod = ARTAuthOptionsMethodDefault;
    }
    _authMethod = [authMethod copy];
}

- (ARTAuthOptions *)mergeWith:(ARTAuthOptions *)precedenceOptions {
    ARTAuthOptions *merged = [self copy];

    if (precedenceOptions.key)
        merged.key = precedenceOptions.key;
    if (precedenceOptions.authCallback)
        merged.authCallback = precedenceOptions.authCallback;
    if (precedenceOptions.authUrl)
        merged.authUrl = precedenceOptions.authUrl;
    if (precedenceOptions.authMethod)
        merged.authMethod = precedenceOptions.authMethod;
    if (precedenceOptions.authHeaders)
        merged.authHeaders = precedenceOptions.authHeaders;
    if (precedenceOptions.authParams)
        merged.authParams = precedenceOptions.authParams;
    if (precedenceOptions.queryTime)
        merged.queryTime = precedenceOptions.queryTime;
    if (precedenceOptions.useTokenAuth)
        merged.useTokenAuth = precedenceOptions.useTokenAuth;

    return merged;
}

- (BOOL)isMethodPOST {
    return [_authMethod isEqualToString:@"POST"];
}

- (BOOL)isMethodGET {
    return [_authMethod isEqualToString:@"GET"];
}

@end
