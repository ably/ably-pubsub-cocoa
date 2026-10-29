#import "ARTTestClientOptions.h"
#import "ARTFallback+Private.h"
#import "ARTRealtimeTransportFactory.h"
#import "ARTJitterCoefficientGenerator.h"
#import "ARTSystemTimeProvider.h"
#import "ARTOSReachability.h"

@implementation ARTTestClientOptions

- (instancetype)init {
    if (self = [super init]) {
        _shuffleArray = ARTFallback_shuffleArray;
        _transportFactory = [[ARTDefaultRealtimeTransportFactory alloc] init];
        _jitterCoefficientGenerator = [[ARTDefaultJitterCoefficientGenerator alloc] init];
        _timeProvider = [[ARTSystemTimeProvider alloc] init];
        _reachabilityClass = [ARTOSReachability class];
    }

    return self;
}

- (nonnull id)copyWithZone:(nullable NSZone *)zone {
    ARTTestClientOptions *const copied = [[ARTTestClientOptions alloc] init];
    copied.channelNamePrefix = self.channelNamePrefix;
    copied.shuffleArray = self.shuffleArray;
    copied.transportFactory = self.transportFactory;
    copied.reconnectionRealtimeHost = self.reconnectionRealtimeHost;
    copied.jitterCoefficientGenerator = self.jitterCoefficientGenerator;
    copied.logLocalDeviceStorageValues = self.logLocalDeviceStorageValues;
    copied.disableLocalDevice = self.disableLocalDevice;
    copied.timeProvider = self.timeProvider;
    copied.reachabilityClass = self.reachabilityClass;
    copied.httpExecutor = self.httpExecutor;

    return copied;
}

@end
