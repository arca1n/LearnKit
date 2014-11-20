//
//  LNKDecisionTreeClassifier.m
//  LearnKit
//
//  Copyright (c) 2014 Matt Rajca. All rights reserved.
//

#import "LNKDecisionTreeClassifier.h"

#import "LNKDecisionTree.h"
#import "LNKMatrix.h"
#import "NSIndexSetAdditions.h"

@implementation LNKDecisionTreeClassifier {
	LNKDecisionTreeNode *_learnedTree;
	NSMutableDictionary *_columnsToPossibleValues;
}

+ (NSArray *)supportedAlgorithms {
	return nil;
}

+ (NSArray *)supportedImplementationTypes {
	return @[ @(LNKImplementationTypeAccelerate) ];
}

+ (Class)_classForImplementationType:(LNKImplementationType)implementationType optimizationAlgorithm:(Class)algorithm {
	return [self class];
}

- (instancetype)initWithMatrix:(LNKMatrix *)matrix implementationType:(LNKImplementationType)implementation optimizationAlgorithm:(id<LNKOptimizationAlgorithm>)algorithm classes:(LNKClasses *)classes {
	if (!(self = [super initWithMatrix:matrix implementationType:implementation optimizationAlgorithm:algorithm classes:classes]))
		return nil;
	
	_columnsToPossibleValues = [[NSMutableDictionary alloc] init];
	
	return self;
}

- (void)dealloc {
	[_learnedTree release];
	[_columnsToPossibleValues release];
	
	[super dealloc];
}

- (void)registerBooleanValueForColumnAtIndex:(LNKSize)columnIndex {
	[self registerCategoricalValues:2 forColumnAtIndex:columnIndex];
}

- (void)registerCategoricalValues:(LNKSize)valueCount forColumnAtIndex:(LNKSize)columnIndex {
	if (columnIndex >= self.matrix.columnCount)
		[NSException raise:NSInvalidArgumentException format:@"`columnIndex` is out of bounds"];
	
	_columnsToPossibleValues[@(columnIndex)] = @(valueCount);
}

- (BOOL)_doExamplesAtIndicesHaveSameLabel:(NSIndexSet *)indices {
	NSParameterAssert(indices);
	
	const LNKFloat *outputVector = self.matrix.outputVector;
	LNKSize firstClass = outputVector[indices.firstIndex];
	
	__block BOOL allSame = YES;
	
	[indices enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) {
		if (outputVector[index] != firstClass) {
			allSame = NO;
			*stop = YES;
		}
	}];
	
	return allSame;
}

typedef void(^LNKDecisionTreeExampleEnumerator)(LNKSize index);

- (void)_enumerateExampleIndices:(NSIndexSet *)exampleIndices withColumnIndex:(LNKSize)columnIndex value:(LNKSize)value performBlock:(LNKDecisionTreeExampleEnumerator)block {
	NSParameterAssert(exampleIndices);
	NSParameterAssert(columnIndex != LNKSizeMax);
	NSParameterAssert(columnIndex < self.matrix.columnCount);
	NSParameterAssert(block);
	
	LNKMatrix *matrix = self.matrix;
	
	[exampleIndices enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) {
#pragma unused(stop)
		
		const LNKFloat *example = [matrix exampleAtIndex:index];
		
		if (example[columnIndex] == value)
			block(index);
	}];
}

- (NSIndexSet *)_filterExampleIndices:(NSIndexSet *)exampleIndices withColumnIndex:(LNKSize)columnIndex value:(LNKSize)value {
	NSMutableIndexSet *filteredExampleIndices = [[NSMutableIndexSet alloc] init];
	
	[self _enumerateExampleIndices:exampleIndices withColumnIndex:columnIndex value:value performBlock:^(LNKSize index) {
		[filteredExampleIndices addIndex:index];
	}];
	
	return [filteredExampleIndices autorelease];
}

- (LNKFloat)_countFractionOfExampleIndices:(NSIndexSet *)exampleIndices withColumnIndex:(LNKSize)columnIndex value:(LNKSize)value {
	__block LNKSize count = 0;
	
	[self _enumerateExampleIndices:exampleIndices withColumnIndex:columnIndex value:value performBlock:^(LNKSize index) {
#pragma unused(index)
		count++;
	}];
	
	return (LNKFloat)count / exampleIndices.count;
}

static LNKFloat _calculateEntropyForClasses(LNKSize positive, LNKSize negative) {
	const LNKFloat positiveFraction = (LNKFloat)positive / (positive + negative);
	const LNKFloat negativeFraction = (LNKFloat)negative / (positive + negative);
	
	LNKFloat sum = 0;
	
#warning TODO: write LNKLog2
	if (positive)
		sum += -positiveFraction * log2(positiveFraction);
	
	if (negative)
		sum += -negativeFraction * log2(negativeFraction);
	
	return sum;
}

- (LNKFloat)_calculateEntropyOfExampleIndices:(NSIndexSet *)exampleIndices withColumnIndex:(LNKSize)columnIndex value:(LNKSize)value  {
	LNKMatrix *matrix = self.matrix;
	
#warning TODO: support multi-class problems
	__block LNKSize positive = 0;
	__block LNKSize negative = 0;
	
	[self _enumerateExampleIndices:exampleIndices withColumnIndex:columnIndex value:value performBlock:^(LNKSize index) {
		if (matrix.outputVector[index] == 1)
			positive++;
		else
			negative++;
	}];
	
	return _calculateEntropyForClasses(positive, negative);
}

- (LNKFloat)_calculateEntropyOfExampleIndices:(NSIndexSet *)exampleIndices {
	NSParameterAssert(exampleIndices);
	
	LNKMatrix *matrix = self.matrix;
	
	__block LNKSize positive = 0;
	__block LNKSize negative = 0;
	
	[exampleIndices enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) {
#pragma unused(stop)
		
		if (matrix.outputVector[index] == 1)
			positive++;
		else
			negative++;
	}];
	
	return _calculateEntropyForClasses(positive, negative);
}

- (LNKSize)_chooseSplittingColumnFromColumnIndices:(NSIndexSet *)columnIndices exampleIndices:(NSIndexSet *)exampleIndices {
	NSParameterAssert(columnIndices);
	NSParameterAssert(exampleIndices);
	
	__block LNKFloat bestInformationGain = LNKFloatMin;
	__block LNKSize bestColumnIndex = LNKSizeMax;
	
	[columnIndices enumerateIndexesUsingBlock:^(NSUInteger columnIndex, BOOL *stop) {
#pragma unused(stop)
		
		LNKFloat expectation = 0;
		
		const LNKSize maxValues = [_columnsToPossibleValues[@(columnIndex)] LNKSizeValue];
		
		for (LNKSize value = 0; value < maxValues; value++) {
			const LNKFloat probability = [self _countFractionOfExampleIndices:exampleIndices withColumnIndex:columnIndex value:value];
			const LNKFloat entropy = [self _calculateEntropyOfExampleIndices:exampleIndices withColumnIndex:columnIndex value:value];
			
			expectation += probability * entropy;
		}
		
		const LNKFloat currentEntropy = [self _calculateEntropyOfExampleIndices:exampleIndices];
		const LNKFloat informationGain = currentEntropy - expectation;
		
		if (informationGain > bestInformationGain) {
			bestInformationGain = informationGain;
			bestColumnIndex = columnIndex;
		}
	}];
	
	NSAssert(bestColumnIndex != LNKSizeMax, @"Invalid column");
	
	return bestColumnIndex;
}

- (LNKDecisionTreeNode *)_learnTreeWithExampleIndices:(NSIndexSet *)exampleIndices columnIndices:(NSIndexSet *)columnIndices {
	NSParameterAssert(exampleIndices);
	NSParameterAssert(columnIndices);
	
	if (!exampleIndices.count) {
		return [LNKDecisionTreeClassificationNode unknownClass];
	}
	else if ([self _doExamplesAtIndicesHaveSameLabel:exampleIndices]) {
		const NSUInteger classPrimitive = self.matrix.outputVector[exampleIndices.firstIndex];
		return [LNKDecisionTreeClassificationNode withClass:[LNKClass classWithUnsignedInteger:classPrimitive]];
	}
	else if (!columnIndices.count) {
#warning TODO: vote with the most likely class
		NSAssertNotReachable(@"Not implemented", nil);
		return nil;
	}
	
	const LNKSize columnIndex = [self _chooseSplittingColumnFromColumnIndices:columnIndices exampleIndices:exampleIndices];
	LNKDecisionTreeSplitNode *tree = [[LNKDecisionTreeSplitNode alloc] initWithColumnIndex:columnIndex];
	
	const LNKSize maxValues = [_columnsToPossibleValues[@(columnIndex)] LNKSizeValue];
	
	for (LNKSize value = 0; value < maxValues; value++) {
		NSIndexSet *filteredExampleIndices = [self _filterExampleIndices:exampleIndices withColumnIndex:columnIndex value:value];
		NSIndexSet *reducedColumnIndices = [columnIndices indexSetByRemovingIndex:columnIndex];
		
		LNKDecisionTreeNode *subtree = [self _learnTreeWithExampleIndices:filteredExampleIndices columnIndices:reducedColumnIndices];
		[tree addBranch:subtree value:value];
	}
	
	return [tree autorelease];
}

- (void)validate {
	const LNKSize columnCount = self.matrix.columnCount;
	
	for (LNKSize column = 0; column < columnCount; column++) {
		if (!_columnsToPossibleValues[@(column)]) {
			[NSException raise:NSInternalInconsistencyException
						format:@"A value type has not been registered for column %lld.", column];
		}
	}
}

- (void)train {
	LNKMatrix *matrix = self.matrix;
	NSIndexSet *allColumns = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, matrix.columnCount)];
	NSIndexSet *allExamples = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, matrix.exampleCount)];
	
	_learnedTree = [[self _learnTreeWithExampleIndices:allExamples columnIndices:allColumns] retain];
}

- (LNKClass *)_predictValueForFeatureVector:(LNKVector)featureVector tree:(LNKDecisionTreeNode *)tree {
	NSParameterAssert(tree);
	
	if ([tree isKindOfClass:[LNKDecisionTreeClassificationNode class]])
		return ((LNKDecisionTreeClassificationNode *)tree).classification;
	
	LNKDecisionTreeSplitNode *splitNode = (LNKDecisionTreeSplitNode *)tree;
	const LNKSize actualValue = featureVector.data[splitNode.columnIndex];
	
	return [self _predictValueForFeatureVector:featureVector tree:[splitNode branchForValue:actualValue]];
}

- (id)predictValueForFeatureVector:(LNKVector)featureVector {
	if (!featureVector.data)
		[NSException raise:NSInvalidArgumentException format:@"The feature vector must contain data"];
	
	if (featureVector.length != self.matrix.columnCount)
		[NSException raise:NSInvalidArgumentException format:@"The feature vector's length should match the matrix's column count"];
	
	return [self _predictValueForFeatureVector:featureVector tree:_learnedTree];
}

@end