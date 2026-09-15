#import <AblyPubSubDevice/ARTPaginatedResult.h>

@class ARTRestInternal;
@class ARTInternalLog;

NS_ASSUME_NONNULL_BEGIN

@interface ARTPaginatedResult<ItemType> ()

@property (nonatomic, readonly) ARTRestInternal *rest;
@property (nonatomic, readonly) dispatch_queue_t userQueue;
@property (nonatomic, readonly) dispatch_queue_t queue;
@property (nonatomic, readonly) NSMutableURLRequest *relFirst;
@property (nonatomic, readonly) NSMutableURLRequest *relCurrent;
@property (nonatomic, readonly) NSMutableURLRequest *relNext;

typedef NSArray<ItemType> *_Nullable(^ARTPaginatedResultResponseProcessor)(NSHTTPURLResponse *_Nullable, NSData *_Nullable, NSError *_Nullable *_Nullable);

- (instancetype)initWithItems:(NSArray *)items
                         rest:(ARTRestInternal *)rest
                     relFirst:(NSMutableURLRequest *)relFirst
                   relCurrent:(NSMutableURLRequest *)relCurrent
                      relNext:(NSMutableURLRequest *)relNext
            responseProcessor:(ARTPaginatedResultResponseProcessor)responseProcessor
             wrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents
                       logger:(ARTInternalLog *)logger NS_DESIGNATED_INITIALIZER;

+ (void)executePaginated:(ARTRestInternal *)rest
             withRequest:(NSMutableURLRequest *)request
    andResponseProcessor:(ARTPaginatedResultResponseProcessor)responseProcessor
        wrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents
                  logger:(ARTInternalLog *)logger
                callback:(void (^)(ARTPaginatedResult<ItemType> *_Nullable result, ARTErrorInfo *_Nullable error))callback;

@end

NS_ASSUME_NONNULL_END
