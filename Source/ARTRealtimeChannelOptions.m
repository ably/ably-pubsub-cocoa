#import "ARTRealtimeChannelOptions.h"
#import "ARTChannelOptions+Private.h"

@implementation ARTRealtimeChannelOptions {
    NSStringDictionary *_params;
    ARTChannelMode _modes;
    BOOL _attachOnSubscribe;
}

- (instancetype)init {
    if (self = [super init]) {
        _attachOnSubscribe = true;
    }
    return self;
}

- (instancetype)initWithCipher:(ARTCipherParams *)cipherParams {
    if (self = [super initWithCipher:cipherParams]) {
        _attachOnSubscribe = true;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    ARTRealtimeChannelOptions *copied = [super copyWithZone:zone];

    copied->_params = _params;
    copied->_modes = _modes;
    copied->_attachOnSubscribe = _attachOnSubscribe;

    return copied;
}

- (NSStringDictionary *)params {
    return _params;
}

- (void)setParams:(NSStringDictionary *)params {
    if (self.isFrozen) {
        @throw [NSException exceptionWithName:NSObjectInaccessibleException
                                       reason:[NSString stringWithFormat:@"%@: You can't change options after you've passed it to receiver.", self.class]
                                     userInfo:nil];
    }
    _params = params;
}

- (ARTChannelMode)modes {
    return _modes;
}

- (void)setModes:(ARTChannelMode)modes {
    if (self.isFrozen) {
        @throw [NSException exceptionWithName:NSObjectInaccessibleException
                                       reason:[NSString stringWithFormat:@"%@: You can't change options after you've passed it to receiver.", self.class]
                                     userInfo:nil];
    }
    _modes = modes;
}

- (BOOL)attachOnSubscribe {
    return _attachOnSubscribe;
}

- (void)setAttachOnSubscribe:(BOOL)value {
    if (self.isFrozen) {
        @throw [NSException exceptionWithName:NSObjectInaccessibleException
                                       reason:[NSString stringWithFormat:@"%@: You can't change options after you've passed it to receiver.", self.class]
                                     userInfo:nil];
    }
    _attachOnSubscribe = value;
}

@end
