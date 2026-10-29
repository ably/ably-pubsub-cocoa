#import <Foundation/Foundation.h>
#import <AblyPubSubDevice/ARTTypes.h>
#import "ARTMessageAnnotations.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Summary with total count and list of client IDs.
 */
NS_SWIFT_SENDABLE
NS_SWIFT_NAME(SummaryClientIdList)
@interface ARTSummaryClientIdList : NSObject

/// Total count of items
@property (nonatomic, readonly) NSInteger total;

/// Array of client IDs
@property (nonatomic, readonly, copy) NSArray<NSString *> *clientIds;

/// Whether the summary data is clipped (truncated)
@property (nonatomic, readonly) BOOL clipped;

/**
 * Initializes with all properties.
 * @param total The total count
 * @param clientIds Array of client ID strings
 * @param clipped Whether the data is clipped
 */
- (instancetype)initWithTotal:(NSInteger)total
                    clientIds:(NSArray<NSString *> *)clientIds
                      clipped:(BOOL)clipped;

@end

/**
 * Summary with total count and dictionary mapping client IDs to counts.
 */
NS_SWIFT_SENDABLE
NS_SWIFT_NAME(SummaryClientIdCounts)
@interface ARTSummaryClientIdCounts : NSObject

/// Total count of items
@property (nonatomic, readonly) NSInteger total;

/// Dictionary mapping client IDs to their counts
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSNumber *> *clientIds;

/// Whether the summary data is clipped (truncated)
@property (nonatomic, readonly) BOOL clipped;

/// Total number of unidentified annotations
@property (nonatomic, readonly) NSInteger totalUnidentified;

/// Total number of unique client IDs
@property (nonatomic, readonly) NSInteger totalClientIds;

/**
 * Initializes with all properties.
 * @param total The total count
 * @param clientIds Dictionary mapping client IDs to their counts
 * @param clipped Whether the data is clipped
 * @param totalUnidentified Total unidentified annotations
 * @param totalClientIds Total unique client IDs
 */
- (instancetype)initWithTotal:(NSInteger)total
                    clientIds:(NSDictionary<NSString *, NSNumber *> *)clientIds
                      clipped:(BOOL)clipped
            totalUnidentified:(NSInteger)totalUnidentified
               totalClientIds:(NSInteger)totalClientIds;

@end

/**
 * Summary with only total count.
 */
NS_SWIFT_SENDABLE
NS_SWIFT_NAME(SummaryTotal)
@interface ARTSummaryTotal : NSObject

/// Total count of items
@property (nonatomic, readonly) NSInteger total;

/**
 * Initializes with total count.
 * @param total The total count
 */
- (instancetype)initWithTotal:(NSInteger)total;

@end

// Global functions for parsing summary dictionaries (TM7b).

/**
 * A static method that takes the value of one of the keys in the `Message.annotations.summary` object for the `distinct.v1` annotation type, and outputs a strongly-typed summary entry.
 * @param dictionary The value of one of the keys of the `Message.annotations.summary`.
 * @return Map of annotation name to aggregated annotations.
 */
NSDictionary<NSString *, ARTSummaryClientIdList *> * _Nullable ARTSummaryDistinctV1(NSDictionary * _Nullable dictionary) NS_SWIFT_NAME(summaryDistinctV1(_:));

/**
 * A static method that takes the value of one of the keys in the `Message.annotations.summary` object for the `unique.v1` annotation type, and outputs a strongly-typed summary entry.
 * @param dictionary The value of one of the keys of the `Message.annotations.summary`.
 * @return Map of annotation name to aggregated annotations.
 */
NSDictionary<NSString *, ARTSummaryClientIdList *> * _Nullable ARTSummaryUniqueV1(NSDictionary * _Nullable dictionary) NS_SWIFT_NAME(summaryUniqueV1(_:));

/**
 * A static method that takes the value of one of the keys in the `Message.annotations.summary` object for the `multiple.v1` annotation type, and outputs a strongly-typed summary entry.
 * @param dictionary The value of one of the keys of the `Message.annotations.summary`.
 * @return Map of annotation name to aggregated annotations.
 */
NSDictionary<NSString *, ARTSummaryClientIdCounts *> * _Nullable ARTSummaryMultipleV1(NSDictionary * _Nullable dictionary) NS_SWIFT_NAME(summaryMultipleV1(_:));

/**
 * A static factory method that takes the value of one of the keys in the `Message.annotations.summary` object for the `flag.v1` annotation type, and outputs a strongly-typed summary entry.
 * @param dictionary The value of one of the keys of the `Message.annotations.summary`.
 * @return Aggregated annotations.
 */
ARTSummaryClientIdList * _Nullable ARTSummaryFlagV1(NSDictionary * _Nullable dictionary) NS_SWIFT_NAME(summaryFlagV1(_:));

/**
 * A static factory method that takes the value of one of the keys in the `Message.annotations.summary` object for the `total.v1` annotation type, and outputs a strongly-typed summary entry.
 * @param dictionary The value of one of the keys of the `Message.annotations.summary`.
 * @return Aggregated total summary.
 */
ARTSummaryTotal * _Nullable ARTSummaryTotalV1(NSDictionary * _Nullable dictionary) NS_SWIFT_NAME(summaryTotalV1(_:));

NS_ASSUME_NONNULL_END
