#import <AblyPubSubDevice/ARTClientInformation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ARTClientInformation_libraryVersion;

@interface ARTClientInformation (Private)

+ (NSString *)libraryAgentIdentifier;
+ (NSString *)platformAgentIdentifier;

// The resulting string only includes the given agents; it does not insert any default agents.
+ (NSString *)agentIdentifierForAgents:(NSDictionary<NSString *, NSString*> *)agents;

@end

NS_ASSUME_NONNULL_END
