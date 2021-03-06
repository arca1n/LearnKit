//
//  _LNKNaiveBayesClassifierAC.m
//  LearnKit
//
//  Copyright (c) 2014 Matt Rajca. All rights reserved.
//

#import "_LNKNaiveBayesClassifierAC.h"

#import "LNKAccelerate.h"
#import "LNKMatrix.h"
#import "LNKNaiveBayesClassifierPrivate.h"

@implementation _LNKNaiveBayesClassifierAC {
	LNKFloat *_priorProbabilities;
	LNKFloat **_featureProbabilities;
}

- (void)train {
	LNKClasses *classes = self.classes;
	LNKMatrix *matrix = self.matrix;
	
	if (classes.count < 2)
		[NSException raise:NSGenericException format:@"There should be at least two classes"];
	
	if (matrix.hasBiasColumn)
		[NSException raise:NSGenericException format:@"Matrices used with a Naive Bayes classifier should not have a bias column"];
	
	NSPointerArray *columnsToValues = [self _columnsToValues];
	const LNKSize classCount = classes.count;
	const LNKSize exampleCount = matrix.exampleCount;
	const LNKSize columnCount = matrix.columnCount;
	const LNKFloat *outputVector = matrix.outputVector;
	
	if (_priorProbabilities)
		free(_priorProbabilities);
	
	if (_featureProbabilities)
		free(_featureProbabilities);
	
	_priorProbabilities = LNKFloatCalloc(classCount);
	_featureProbabilities = malloc(sizeof(LNKFloat *) * classCount * columnCount);
	
	LNKSize classIndex = 0;
	
	for (LNKClass *class in classes) {
		const LNKSize outputValue = class.unsignedIntegerValue;
		LNKSize hits = 0;
		
		for (LNKSize example = 0; example < exampleCount; example++) {
			if (outputVector[example] == outputValue)
				hits++;
		}
		
		_priorProbabilities[classIndex] = (LNKFloat)hits / exampleCount;
		
		for (LNKSize column = 0; column < columnCount; column++) {
			NSArray *values = [columnsToValues pointerAtIndex:column];
			
			LNKFloat *valuesVector = LNKFloatCalloc(values.count);
			_featureProbabilities[classIndex * columnCount + column] = valuesVector;
			
			NSUInteger valueIndex = 0;
			
			for (NSNumber *value in values) {
				for (LNKSize example = 0; example < exampleCount; example++) {
					if (outputVector[example] == outputValue) {
						const LNKFloat *exampleRow = [matrix exampleAtIndex:example];
						
						if (exampleRow[column] == value.unsignedIntegerValue) {
							valuesVector[valueIndex]++;
						}
					}
				}
				
				valuesVector[valueIndex] /= (LNKFloat)hits;
				valueIndex++;
			}
		}
		
		classIndex++;
	}
}

- (id)predictValueForFeatureVector:(LNKVector)featureVector {
	if (!featureVector.data || !featureVector.length)
		[NSException raise:NSGenericException format:@"The feature vector must have a non-zero length"];
	
	LNKClasses *classes = self.classes;
	const LNKSize columnCount = self.matrix.columnCount;
	LNKSize classIndex = 0;
	
	LNKClass *bestClass = nil;
	LNKFloat bestLikelihood = -1;
	
	for (LNKClass *class in classes) {
		LNKFloat expectation = _priorProbabilities[classIndex];
		
		for (LNKSize column = 0; column < columnCount; column++) {
			const LNKSize featureIndex = featureVector.data[column];
			
			expectation *= _featureProbabilities[classIndex * columnCount + column][featureIndex];
		}
		
		if (expectation > bestLikelihood) {
			bestLikelihood = expectation;
			bestClass = class;
		}
		
		classIndex++;
	}
	
	return bestClass;
}

- (void)dealloc {
	if (_priorProbabilities)
		free(_priorProbabilities);
	
	if (_featureProbabilities)
		free(_featureProbabilities);
	
	[super dealloc];
}

@end
