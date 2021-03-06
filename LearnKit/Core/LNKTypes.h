//
//  LNKTypes.h
//  LearnKit
//
//  Copyright (c) 2014 Matt Rajca. All rights reserved.
//

typedef NS_ENUM(NSUInteger, LNKImplementationType) {
	LNKImplementationTypeAccelerate,
	
#if TARGET_OS_MAC
	LNKImplementationTypeOpenCL,
#endif
	
#if TARGET_OS_IPHONE
	LNKImplementationTypeMetal,
#endif
};


#if USE_DOUBLE_PRECISION
typedef double LNKFloat;
#define LNKFloatMin	DBL_MIN
#define LNKFloatMax	DBL_MAX
#else
typedef float LNKFloat;
#define LNKFloatMin	FLT_MIN
#define LNKFloatMax	FLT_MAX
#endif

typedef uint64_t LNKSize;
#define LNKSizeMax UINT64_MAX

#define LNKFloatAlloc(size) (LNKFloat *)malloc((size) * sizeof(LNKFloat))
#define LNKFloatCalloc(size) (LNKFloat *)calloc((size), sizeof(LNKFloat))
#define LNKFloatCopy(dest, src, size) memcpy(dest, src, (size) * sizeof(LNKFloat))

#define LNKFloatAllocAndCopy(data, size) LNKFloatCopy(LNKFloatAlloc(size), data, size)


typedef struct {
	const LNKFloat *data;
	const LNKSize length;
} LNKVector;

#define LNKVectorAlloc(length) ((LNKVector) { LNKFloatAlloc(length), (length) })
#define LNKVectorAllocAndCopy(data, length) ((LNKVector) { LNKFloatAllocAndCopy(data, length), (length) })
#define LNKVectorMakeUnsafe(data, length) ((LNKVector) { (data), (length) })
#define LNKVectorFree(vector) free((void *)(vector).data)

@interface NSNumber (LNKTypes)

+ (NSNumber *)numberWithLNKFloat:(LNKFloat)value;
+ (NSNumber *)numberWithLNKSize:(LNKSize)value;

@property (nonatomic, readonly) LNKFloat LNKFloatValue;
@property (nonatomic, readonly) LNKSize LNKSizeValue;

@end
